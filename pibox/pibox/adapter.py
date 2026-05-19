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
from typing import ClassVar

from aicodebox.adapters.base import (
    AgentAdapter,
    RunRequest,
    RunResult,
    parse_json_response,
)

VALID_THINKING = {"off", "minimal", "low", "medium", "high", "xhigh"}


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
        super().validate(req)
        if req.thinking and req.thinking not in VALID_THINKING:
            raise ValueError(
                f"thinking={req.thinking!r} invalid; "
                f"choose one of {sorted(VALID_THINKING)}"
            )
        if req.tools_allowlist and req.no_tools:
            raise ValueError("tools_allowlist and no_tools are mutually exclusive")

    def build_argv(self, req: RunRequest) -> list[str]:
        argv: list[str] = [self.binary, "-p"]
        argv += ["--mode", "json" if req.output_format == "json" else "text"]

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

        argv.append(req.prompt)
        return argv

    def translate_auth(self, env: dict[str, str]) -> dict[str, str]:
        # pi reads ANTHROPIC_API_KEY / OPENAI_API_KEY / OPENROUTER_API_KEY /
        # GEMINI_API_KEY / ZAI_API_KEY etc. natively — no aliasing needed.
        del env
        return {}

    def parse_output(self, stdout: str, req: RunRequest) -> RunResult:
        if req.output_format == "json":
            return self._parse_json_stream(stdout, req)
        result = RunResult(
            text=stdout.strip(),
            raw_stdout=stdout,
            raw_stderr="",
            exit_code=0,
        )
        self.post_validate_json(result, req)
        return result

    def _parse_json_stream(self, stdout: str, req: RunRequest) -> RunResult:
        session_id = ""
        text_parts: list[str] = []
        usage: dict[str, object] | None = None
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
            elif etype == "message_end":
                msg = evt.get("message") or {}
                content = msg.get("content")
                if isinstance(content, str):
                    text_parts.append(content)
                elif isinstance(content, list):
                    for blk in content:
                        if isinstance(blk, dict) and blk.get("type") == "text":
                            t = blk.get("text")
                            if isinstance(t, str):
                                text_parts.append(t)
                u = msg.get("usage")
                if isinstance(u, dict):
                    usage = u
            elif etype == "turn_end":
                u = evt.get("usage")
                if isinstance(u, dict):
                    usage = u

        text = "\n".join(p for p in text_parts if p).strip()
        result = RunResult(
            text=text,
            raw_stdout=stdout,
            raw_stderr="",
            exit_code=0,
            session_id=session_id,
            usage=usage,
        )
        if req.json_schema:
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
