"""Regression tests for Pi's native JSON event preservation."""

from __future__ import annotations

import json

from aicodebox.adapters.base import RunRequest

from pibox.adapter import PiAdapter


def test_build_argv_keeps_json_stream_in_full_event_mode() -> None:
    adapter = PiAdapter()
    request = RunRequest(prompt="hi", no_continue=True, event_mode="full")
    adapter.validate(request)

    argv = adapter.build_argv(request)

    mode_index = argv.index("--mode")
    assert argv[mode_index + 1] == "json"


def test_parse_events_preserves_thinking_and_tool_lifecycle() -> None:
    adapter = PiAdapter()
    source_events = [
        {"type": "session", "id": "pi-session"},
        {
            "type": "message_update",
            "assistantMessageEvent": {
                "type": "thinking_delta",
                "contentIndex": 0,
                "delta": "checking",
            },
        },
        {
            "type": "tool_execution_start",
            "toolCallId": "call-1",
            "toolName": "bash",
            "args": {"command": "pwd"},
        },
        {
            "type": "tool_execution_end",
            "toolCallId": "call-1",
            "toolName": "bash",
            "result": {"content": [{"type": "text", "text": "/workspace"}]},
            "isError": False,
        },
        {"type": "agent_settled"},
    ]

    events = adapter.parse_events(
        "\n".join(json.dumps(event) for event in source_events),
        RunRequest(event_mode="full"),
    )

    assert events == source_events
