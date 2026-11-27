#!/usr/bin/env python3
"""A scripted OpenAI-compatible chat model for offline Pi tests.

    server.py <port> <scenario.json> <requests.jsonl>

Each POST to /v1/chat/completions answers with the next step of the scenario:
a tool call ({"tool": name, "args": {...}}) or, once the steps run out, a
plain text reply. Every request body is appended to requests.jsonl so the test
can check what Pi sent back (tool results, injected context). It answers both
streaming (SSE) and non-streaming requests. No real model is ever called.
"""

from __future__ import annotations

import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FINAL_TEXT = "done"


class Script:
    def __init__(self, steps: list[dict]):
        self.steps = steps
        self.index = 0
        self.lock = threading.Lock()

    def next(self) -> dict | None:
        with self.lock:
            if self.index >= len(self.steps):
                return None
            step = self.steps[self.index]
            self.index += 1
            return step


def make_handler(script: Script, log_path: str):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):  # noqa: N802 - http.server naming
            body = json.dumps({"data": [{"id": "scripted", "object": "model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):  # noqa: N802 - http.server naming
            raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            with open(log_path, "a", encoding="utf-8") as fh:
                fh.write(raw.decode("utf-8", "replace") + "\n")
            request = json.loads(raw or b"{}")
            step = script.next()
            if request.get("stream"):
                self.stream(step)
            else:
                self.whole(step)

        def message(self, step: dict | None) -> tuple[dict, str]:
            if step is None:
                return {"role": "assistant", "content": FINAL_TEXT}, "stop"
            call = {
                "id": f"call_{script.index}",
                "type": "function",
                "function": {"name": step["tool"], "arguments": json.dumps(step["args"])},
            }
            return {"role": "assistant", "content": None, "tool_calls": [call]}, "tool_calls"

        def whole(self, step: dict | None) -> None:
            message, finish = self.message(step)
            body = json.dumps({
                "id": "mock", "object": "chat.completion", "model": "scripted",
                "choices": [{"index": 0, "message": message, "finish_reason": finish}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def stream(self, step: dict | None) -> None:
            message, finish = self.message(step)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()

            def send(payload: dict) -> None:
                self.wfile.write(b"data: " + json.dumps(payload).encode() + b"\n\n")
                self.wfile.flush()

            base = {"id": "mock", "object": "chat.completion.chunk", "model": "scripted"}
            if message.get("tool_calls"):
                call = message["tool_calls"][0]
                delta = {"role": "assistant", "tool_calls": [{"index": 0, **call}]}
            else:
                delta = {"role": "assistant", "content": message["content"]}
            send({**base, "choices": [{"index": 0, "delta": delta, "finish_reason": None}]})
            send({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": finish}]})
            send({**base, "choices": [],
                  "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}})
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

    return Handler


def main() -> int:
    port, scenario_path, log_path = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    with open(scenario_path, encoding="utf-8") as fh:
        script = Script(json.load(fh))
    ThreadingHTTPServer(("127.0.0.1", port), make_handler(script, log_path)).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
