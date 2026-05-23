"""PiAdapter — wires the aicodebox AgentAdapter contract to pi-coding-agent.

pi CLI surface used here (see .research_files/pi-deep-dive.md for the full map):
  -p / --print                non-interactive
  --mode text|json            output protocol
  --model <id>                model override
  --thinking <level>          off|minimal|low|medium|high|xhigh
  --system-prompt <text>      replace default system prompt
  --append-system-prompt <t>  append (repeatable)
  --continue                  continue most recent session in cwd
  --session <id>              resume specific session
  --no-session                ephemeral run (nothing persisted)
  --tools <csv>               tool allowlist
  --no-tools                  disable all tools
"""

from __future__ import annotations

import json
import os
from typing import Any, ClassVar

from aicodebox.adapters.base import (
    AgentAdapter,
    RunRequest,
    RunResult,
    StreamEvent,
    parse_json_response,
)

VALID_THINKING = {"off", "minimal", "low", "medium", "high", "xhigh"}
VALID_OUTPUT_FORMATS = {"text", "json", "json-verbose"}


def _normalize_content_blocks(content: Any) -> list[dict[str, Any]]:
    """Coerce a `message.content` field into a uniform list-of-blocks shape.

    pi (like every other Anthropic-style agent) sometimes emits content as
    a bare string (one-shot text) and sometimes as a list of typed blocks
    (text / thinking / tool_use / tool_result). The verbose envelope needs
    a single shape, so wrap strings and drop anything we can't recognize.
    """
    if isinstance(content, str):
        return [{"type": "text", "text": content}] if content else []
    if not isinstance(content, list):
        return []
    out: list[dict[str, Any]] = []
    for blk in content:
        if isinstance(blk, dict) and isinstance(blk.get("type"), str):
            out.append(blk)
    return out


class PiAdapter(AgentAdapter):
    name: ClassVar[str] = "pi"
    binary: ClassVar[str] = "pi"
    available_thinking_levels: ClassVar[list[str]] = [
        "off",
        "minimal",
        "low",
        "medium",
        "high",
        "xhigh",
    ]

    def validate(self, req: RunRequest) -> None:
        # NOT calling super().validate(req): the base only knows about
        # output_format in {"text", "json"} and would reject "json-verbose".
        # The pibox adapter owns this check.
        if req.output_format not in VALID_OUTPUT_FORMATS:
            raise ValueError(
                f"output_format={req.output_format!r} invalid; "
                f"choose one of {sorted(VALID_OUTPUT_FORMATS)}"
            )
        if req.output_format == "json-verbose" and req.json_schema:
            raise ValueError(
                "output_format=json-verbose is incompatible with json_schema; "
                "json-verbose returns the full turn envelope, schema mode "
                "validates the flat text — pick one"
            )
        if req.thinking and req.thinking not in VALID_THINKING:
            raise ValueError(
                f"thinking={req.thinking!r} invalid; "
                f"choose one of {sorted(VALID_THINKING)}"
            )
        if req.tools_allowlist and req.no_tools:
            raise ValueError("tools_allowlist and no_tools are mutually exclusive")

    def build_argv(self, req: RunRequest) -> list[str]:
        argv: list[str] = [self.binary, "-p"]
        # Always invoke pi in `--mode json` so the adapter receives the full
        # session-event stream (session id, per-turn usage + cost, assistant
        # text). pi's `--mode text` emits only the assistant text with zero
        # side-channel for metadata — useless for an API. The caller's
        # `output_format` only affects post-processing (schema validation),
        # not pi's invocation.
        argv += ["--mode", "json"]

        if req.model:
            argv += ["--model", req.model]
        if req.thinking:
            argv += ["--thinking", req.thinking]
        if req.system_prompt:
            argv += ["--system-prompt", req.system_prompt]
        if req.append_system_prompt:
            argv += ["--append-system-prompt", req.append_system_prompt]
        if req.json_schema:
            # pi has no native schema enforcement — bolt the schema onto the
            # system prompt and post-validate.
            schema_text = (
                "You MUST respond with a single JSON document conforming to "
                "this JSON Schema. No prose, no fences, just JSON.\n\n"
                + json.dumps(req.json_schema)
            )
            argv += ["--append-system-prompt", schema_text]

        if req.resume:
            argv += ["--session", req.resume]
        elif req.no_continue:
            argv += ["--no-session"]
        else:
            argv += ["--continue"]

        if req.no_tools:
            argv += ["--no-tools"]
        elif req.tools_allowlist:
            argv += ["--tools", ",".join(req.tools_allowlist)]

        if req.extra_args:
            argv += list(req.extra_args)

        # pi's built-in `zai` provider auto-claims `glm-*` model names, which
        # bypasses the ANTHROPIC_BASE_URL override seeded into models.json by
        # init.d/20-anthropic-baseurl.sh. When the user has set an Anthropic-
        # compatible base URL, force the request through the `anthropic`
        # provider unless they explicitly chose one in extra_args.
        if os.environ.get("ANTHROPIC_BASE_URL") and "--provider" not in argv:
            argv += ["--provider", "anthropic"]

        # Prompt is piped to stdin by aicodebox.shared.runner — do NOT also
        # append it to argv. pi's `-p` mode merges stdin + positional with no
        # separator, so dual-channel = the prompt appears twice in the user
        # message and contaminates text / parseError downstream.
        return argv

    def translate_auth(self, env: dict[str, str]) -> dict[str, str]:
        # pi reads ANTHROPIC_API_KEY / OPENAI_API_KEY / OPENROUTER_API_KEY /
        # GEMINI_API_KEY / ZAI_API_KEY etc. natively — no aliasing needed.
        del env
        return {}

    def parse_output(self, stdout: str, req: RunRequest) -> RunResult:
        # pi is always invoked in `--mode json` (see build_argv); a single
        # parser handles both text and json output_formats — schema-bolt
        # branching happens inside _parse_json_stream based on req.json_schema.
        return self._parse_json_stream(stdout, req)

    def parse_stream_event(
        self, line: str, req: RunRequest,
    ) -> StreamEvent | None:
        """Decode one line of pi's ``--mode json`` event stream into a
        canonical ``StreamEvent``.

        pi emits per-token deltas under
        ``message_update.assistantMessageEvent`` with subtypes
        ``text_start``/``text_delta``/``text_end`` for visible assistant
        text, and ``thinking_*`` for the model's internal reasoning. Only
        text deltas reach the wire — thinking deltas are skipped so they
        don't contaminate the OAI ``content`` stream (clients streaming
        chat completions never want to see chain-of-thought).

        Returning ``None`` skips lines that carry no useful event
        (``agent_start``, message echoes, queue updates, tool-use deltas,
        compaction notices, the prompt's own ``message_end``, etc.).
        """
        del req
        if not line:
            return None
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            return None

        etype = evt.get("type")

        if etype == "session":
            sid = evt.get("id")
            if isinstance(sid, str) and sid:
                return StreamEvent(type="session", data={"id": sid})
            return None

        if etype == "message_update":
            inner = evt.get("assistantMessageEvent") or {}
            if inner.get("type") == "text_delta":
                delta = inner.get("delta")
                if isinstance(delta, str) and delta:
                    return StreamEvent(type="delta", text=delta)
            # thinking_*, tool_use_*, *_start, *_end — all silent.
            return None

        if etype == "turn_end":
            u = evt.get("usage")
            if not isinstance(u, dict):
                msg = evt.get("message") or {}
                u = msg.get("usage") if isinstance(msg, dict) else None
            if isinstance(u, dict):
                # Normalize to OAI-style names so the base's `_usage_tokens`
                # helper finds them — pi natively emits input/output, the
                # canonical RunResult.usage shape carries input_tokens too.
                norm = dict(u)
                if "input" in norm:
                    norm.setdefault("input_tokens", norm["input"])
                if "output" in norm:
                    norm.setdefault("output_tokens", norm["output"])
                return StreamEvent(type="usage", data=norm)
            return None

        if etype == "agent_end":
            # pi's terminal event. Surface a stop reason if any assistant
            # message carries one; default to "stop".
            reason = "stop"
            msgs = evt.get("messages")
            if isinstance(msgs, list):
                for m in reversed(msgs):
                    if isinstance(m, dict) and m.get("role") == "assistant":
                        sr = m.get("stopReason") or m.get("stop_reason")
                        if isinstance(sr, str) and sr:
                            reason = sr
                        break
            return StreamEvent(type="stop", data={"reason": reason})

        return None

    def _parse_json_stream(self, stdout: str, req: RunRequest) -> RunResult:
        session_id = ""
        text_parts: list[str] = []
        usage: dict[str, Any] | None = None
        turns: list[dict[str, Any]] = []
        model = ""
        stop_reason = ""
        cost: dict[str, Any] | None = None

        for line in stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                continue

            etype = evt.get("type")
            if etype == "session" and not session_id:
                session_id = str(evt.get("id") or "")
                # Some session events carry the resolved model name.
                m = evt.get("model")
                if isinstance(m, str) and m:
                    model = m

            elif etype == "message_end":
                msg = evt.get("message") or {}
                role = msg.get("role")
                content = msg.get("content")
                blocks = _normalize_content_blocks(content)

                # Verbose envelope captures EVERY message — user prompt,
                # assistant text+thinking+tool_use, tool_result echoes.
                if role and blocks:
                    turns.append({"role": role, "content": blocks})

                # Flat `text` field stays assistant-only — that is the
                # contract the OAI compat layer + json+schema mode rely on.
                if role == "assistant":
                    for blk in blocks:
                        if blk.get("type") == "text":
                            t = blk.get("text")
                            if isinstance(t, str):
                                text_parts.append(t)
                    u = msg.get("usage")
                    if isinstance(u, dict):
                        usage = dict(u)
                    sr = msg.get("stop_reason") or msg.get("stopReason")
                    if isinstance(sr, str) and sr:
                        stop_reason = sr
                    m = msg.get("model")
                    if isinstance(m, str) and m:
                        model = m

            elif etype == "turn_end":
                u = evt.get("usage")
                if isinstance(u, dict):
                    usage = dict(u)
                c = evt.get("cost")
                if isinstance(c, dict):
                    cost = c
                sr = evt.get("stop_reason") or evt.get("stopReason")
                if isinstance(sr, str) and sr:
                    stop_reason = sr
                m = evt.get("model")
                if isinstance(m, str) and m:
                    model = m

        text = "\n".join(p for p in text_parts if p).strip()
        # pi emits `input` / `output` token counts; the base OAI compat layer
        # (aicodebox/modes/api/oai.py) reads `input_tokens` / `output_tokens`.
        # Add both naming conventions so /openai/v1/chat/completions returns
        # real numbers instead of zeros.
        if isinstance(usage, dict):
            if "input" in usage:
                usage.setdefault("input_tokens", usage["input"])
            if "output" in usage:
                usage.setdefault("output_tokens", usage["output"])

        result = RunResult(
            text=text,
            raw_stdout=stdout,
            raw_stderr="",
            exit_code=0,
            session_id=session_id,
            usage=usage,
        )

        if req.output_format == "json-verbose":
            # Full envelope goes into `parsed` so the API layer surfaces it
            # under the canonical structured-output field. Schema validation
            # is intentionally forbidden in this mode (see validate()).
            envelope: dict[str, Any] = {
                "sessionId": session_id,
                "model": model,
                "stopReason": stop_reason,
                "turns": turns,
                "usage": usage,
                "text": text,
            }
            if cost is not None:
                envelope["cost"] = cost
            result.parsed = envelope
        elif req.json_schema:
            value, err = parse_json_response(text, req.json_schema)
            result.parsed = value
            result.parse_error = err

        return result

    def interactive_argv(self, workspace: str) -> list[str]:
        del workspace
        return [self.binary]

    def passthrough_argv(self, args: list[str]) -> list[str]:
        return [self.binary, *args]

    def auth_paths(self) -> list[str]:
        home = os.environ.get("HOME", "/home/aicode")
        return [
            f"{home}/.pi/agent/auth.json",
            f"{home}/.pi/agent/settings.json",
            f"{home}/.pi/agent/models.json",
            f"{home}/.pi/agent/sessions",
        ]
