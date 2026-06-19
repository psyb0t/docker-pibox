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
import logging
import os
from typing import Any, ClassVar

from aicodebox.adapters.base import (
    AgentAdapter,
    RunRequest,
    RunResult,
    StreamEvent,
)

log = logging.getLogger(__name__)

VALID_THINKING = {"off", "minimal", "low", "medium", "high", "xhigh"}


def _truncate(value: Any, limit: int = 80) -> str:
    """Render a value as a short string for log fields. Never logs full
    prompts / schemas / tokens — capped so a malicious caller can't blow
    up log volume by sending huge inputs, and so prompts (which may carry
    user-private content) don't land in logs verbatim. ``...`` suffix
    signals truncation occurred.
    """
    if value is None:
        return ""
    s = str(value)
    return s if len(s) <= limit else s[:limit] + "..."


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
        # Base owns output_format vocab. Since aicodebox v0.6.0 the API
        # exposes ``jsonSchema`` as the only dial — server derives
        # output_format=json-verbose when schema is set, else text. The
        # adapter only adds pi-specific constraints.
        log.debug(
            "validate(req): output_format=%s thinking=%s no_tools=%s "
            "tools_allowlist=%s json_schema=%s resume=%s",
            req.output_format,
            req.thinking,
            req.no_tools,
            bool(req.tools_allowlist),
            req.json_schema is not None,
            bool(req.resume),
        )
        super().validate(req)
        if req.thinking and req.thinking not in VALID_THINKING:
            log.warning(
                "validate(req): rejecting unknown thinking level %r",
                req.thinking,
            )
            raise ValueError(
                f"thinking={req.thinking!r} invalid; "
                f"choose one of {sorted(VALID_THINKING)}"
            )
        if req.tools_allowlist and req.no_tools:
            log.warning(
                "validate(req): rejecting tools_allowlist + no_tools combination",
            )
            raise ValueError("tools_allowlist and no_tools are mutually exclusive")

    def build_argv(self, req: RunRequest) -> list[str]:
        argv: list[str] = [self.binary, "-p"]
        # Always invoke pi in `--mode json` so the adapter receives the full
        # session-event stream (session id, per-turn usage + cost, assistant
        # text). pi's `--mode text` emits only the assistant text with zero
        # side-channel for metadata — useless for an API. The caller's
        # `output_format` only affects post-processing (text extraction,
        # event parsing) — pi runs the same way regardless.
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
            # system prompt. Parse + retry happens at the base layer
            # (server._run_json_with_retry); the adapter only needs to make
            # sure the model is steered toward producing JSON.
            schema_text = (
                "You MUST respond with a single JSON document conforming to "
                "this JSON Schema. No prose, no fences, just JSON.\n\n"
                + json.dumps(req.json_schema)
            )
            argv += ["--append-system-prompt", schema_text]
            log.debug(
                "build_argv: bolted JSON schema onto system prompt "
                "(schema_keys=%s)",
                list(req.json_schema.keys()),
            )

        session_choice: str
        if req.resume:
            argv += ["--session", req.resume]
            session_choice = "resume"
        elif req.no_continue:
            argv += ["--no-session"]
            session_choice = "no-session"
        else:
            argv += ["--continue"]
            session_choice = "continue"

        tools_choice: str
        if req.no_tools:
            argv += ["--no-tools"]
            tools_choice = "none"
        elif req.tools_allowlist:
            argv += ["--tools", ",".join(req.tools_allowlist)]
            tools_choice = "allowlist"
        else:
            tools_choice = "default"

        if req.extra_args:
            argv += list(req.extra_args)

        # pi's built-in `zai` provider auto-claims `glm-*` model names, which
        # bypasses the ANTHROPIC_BASE_URL override seeded into models.json by
        # scripts/setup-anthropic-baseurl.sh. When the user has set an
        # Anthropic-compatible base URL, force the request through the
        # `anthropic` provider unless they explicitly chose one in extra_args.
        forced_anthropic = False
        if os.environ.get("ANTHROPIC_BASE_URL") and "--provider" not in argv:
            argv += ["--provider", "anthropic"]
            forced_anthropic = True

        log.debug(
            "build_argv: model=%s thinking=%s session=%s tools=%s "
            "extra_args=%d forced_provider_anthropic=%s argc=%d",
            req.model or "(default)",
            req.thinking or "(default)",
            session_choice,
            tools_choice,
            len(req.extra_args or []),
            forced_anthropic,
            len(argv),
        )

        # Prompt is piped to stdin by aicodebox.shared.runner — do NOT also
        # append it to argv. pi's `-p` mode merges stdin + positional with no
        # separator, so dual-channel = the prompt appears twice in the user
        # message and contaminates downstream text.
        return argv

    def translate_auth(self, env: dict[str, str]) -> dict[str, str]:
        # pi reads ANTHROPIC_API_KEY / OPENAI_API_KEY / OPENROUTER_API_KEY /
        # GEMINI_API_KEY / ZAI_API_KEY etc. natively — no aliasing needed.
        del env
        return {}

    def parse_output(self, stdout: str, req: RunRequest) -> RunResult:
        """Extract the canonical assistant text + session id + usage from
        pi's NDJSON event stream.

        `parse_output` populates only the fields the modes actually consume
        off RunResult — text, session_id, usage. The structured event log is
        exposed separately via ``parse_events`` when ``output_format=
        json-verbose`` (which the API picks unconditionally whenever
        ``jsonSchema`` is set, per the aicodebox v0.6.0 contract). Schema
        parsing + retry orchestration lives at the base layer; the adapter
        just needs to deliver the model's raw text in ``result.text`` so
        the base can validate it against ``jsonSchema``.
        """
        del req
        line_count = 0
        decoded_count = 0
        decode_errors = 0
        session_id = ""
        text_parts: list[str] = []
        usage: dict[str, Any] | None = None
        last_provider_error: str | None = None

        for line in stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            line_count += 1
            try:
                evt = json.loads(line)
            except json.JSONDecodeError as exc:
                # pi's --mode json should never emit malformed lines, but
                # we tolerate it best-effort. Count + log so the operator
                # sees something is off; raw bytes reachable via
                # includeRaw=true.
                decode_errors += 1
                log.warning(
                    "parse_output: dropping malformed NDJSON line (err=%s, sample=%r)",
                    exc.msg,
                    _truncate(line, 80),
                )
                continue
            decoded_count += 1

            etype = evt.get("type")
            if etype == "session" and not session_id:
                sid = evt.get("id")
                if isinstance(sid, str):
                    session_id = sid
                continue
            if etype == "message_end":
                msg = evt.get("message") or {}
                if not isinstance(msg, dict) or msg.get("role") != "assistant":
                    continue
                # Capture upstream provider errors (e.g. 401 / rate-limit /
                # ByteString) — pi reports them under stopReason=error +
                # errorMessage on the assistant message. Without surfacing
                # these the operator sees an empty .text and zero clue
                # what went wrong.
                if msg.get("stopReason") == "error":
                    err_msg = msg.get("errorMessage")
                    if isinstance(err_msg, str) and err_msg:
                        last_provider_error = err_msg
                        log.warning(
                            "parse_output: assistant turn errored "
                            "(provider=%s model=%s err=%s)",
                            msg.get("provider"),
                            msg.get("model"),
                            _truncate(err_msg, 200),
                        )
                content = msg.get("content")
                if isinstance(content, str):
                    if content:
                        text_parts.append(content)
                elif isinstance(content, list):
                    for blk in content:
                        if not isinstance(blk, dict):
                            continue
                        if blk.get("type") == "text":
                            t = blk.get("text")
                            if isinstance(t, str):
                                text_parts.append(t)
                u = msg.get("usage")
                if isinstance(u, dict):
                    usage = dict(u)
                continue
            if etype == "turn_end":
                u = evt.get("usage")
                if isinstance(u, dict):
                    usage = dict(u)

        text = "\n".join(p for p in text_parts if p).strip()
        # pi emits `input` / `output` token counts; the OAI compat layer
        # reads `input_tokens` / `output_tokens`. Carry both naming
        # conventions so /v1/chat/completions returns real numbers.
        if isinstance(usage, dict):
            if "input" in usage:
                usage.setdefault("input_tokens", usage["input"])
            if "output" in usage:
                usage.setdefault("output_tokens", usage["output"])

        log.info(
            "parse_output: text_len=%d session_id=%s lines=%d decoded=%d "
            "decode_errors=%d usage_keys=%s provider_error=%s",
            len(text),
            session_id or "(none)",
            line_count,
            decoded_count,
            decode_errors,
            sorted(usage.keys()) if usage else [],
            bool(last_provider_error),
        )

        return RunResult(
            text=text,
            raw_stdout=stdout,
            raw_stderr="",
            exit_code=0,
            session_id=session_id,
            usage=usage,
        )

    def parse_events(
        self, stdout: str, req: RunRequest,
    ) -> list[dict[str, Any]]:
        """JSON-decode every line of pi's `--mode json` event stream.

        Returned verbatim to /run callers as the ``events`` field when
        ``output_format=json-verbose``. Lines that fail to decode or aren't
        objects are warned + dropped — events is best-effort; the raw bytes
        are reachable via ``includeRaw: true`` if a caller needs them.
        """
        del req
        events: list[dict[str, Any]] = []
        decode_errors = 0
        non_dict = 0
        for line in stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError as exc:
                decode_errors += 1
                log.warning(
                    "parse_events: dropping malformed NDJSON line "
                    "(err=%s, sample=%r)",
                    exc.msg,
                    _truncate(line, 80),
                )
                continue
            if isinstance(evt, dict):
                events.append(evt)
            else:
                non_dict += 1
                log.warning(
                    "parse_events: dropping non-object event (type=%s)",
                    type(evt).__name__,
                )

        log.debug(
            "parse_events: events=%d decode_errors=%d non_dict=%d",
            len(events),
            decode_errors,
            non_dict,
        )
        return events

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
        don't contaminate the OAI ``content`` stream.

        Returning ``None`` skips lines that carry no useful event
        (``agent_start``, message echoes, queue updates, tool-use deltas,
        compaction notices, the prompt's own ``message_end``, etc.).
        """
        del req
        if not line:
            return None
        try:
            evt = json.loads(line)
        except json.JSONDecodeError as exc:
            log.warning(
                "parse_stream_event: dropping malformed NDJSON line "
                "(err=%s, sample=%r)",
                exc.msg,
                _truncate(line, 80),
            )
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
