# Adapter contract

`pibox/pibox/adapter.py` implements `aicodebox.adapters.base.AgentAdapter` for Pi. The base calls it from every mode, so a change here changes the API, MCP, Telegram and cron at once.

- `build_argv` always emits `pi -p --mode json`. The base and the API depend on the JSON event stream for session IDs, usage and provider errors; `--mode text` carries none of them.
- The prompt is written to Pi's stdin by the base runner. Never add it to argv.
- Session flags: `resume` maps to `--session <id>`, `no_continue` to `--no-session`, otherwise `--continue`. Tools: `no_tools` maps to `--no-tools`, `tools_allowlist` to `--tools <csv>`. `extra_args` go last, before the provider pin.
- Append `--provider` only when the caller did not pass one: the name from `pibox-provider.json` when that marker is valid, else `anthropic` when `ANTHROPIC_BASE_URL` is set. Use `--model` from the marker only when neither the request nor `extra_args` names a model.
- `_configured_provider` treats `pibox-provider.json` as untrusted: refuse symlinks, files over `MAX_CUSTOM_PROVIDER_STATE_BYTES`, bad JSON, a `managedBy` other than `pibox`, provider names outside `^[a-z][a-z0-9-]*$`, and model IDs that are empty, too long or multiline.
- `validate` accepts only the thinking levels in `VALID_THINKING` and rejects `tools_allowlist` with `no_tools`. Keep `available_thinking_levels` and `VALID_THINKING` in step with each other and with the docs.
- `parse_output` returns the joined assistant text from `message_end` events, the first `session` id, the last usage seen, and the last `errorMessage` from an assistant turn with `stopReason: error` as `provider_error`. Usage carries both `input`/`output` and `input_tokens`/`output_tokens`. Malformed lines are counted, logged and skipped, never raised.
- `parse_events` returns every decoded object line unchanged. Callers rely on native Pi events, including thinking and tool events.
- `parse_stream_event` emits only `session`, `delta` (from `text_delta`), `usage` (from `turn_end`) and `stop` (from `agent_end`). Thinking and tool deltas must not reach the stream.
- `auth_paths` lists the Pi state the base preserves. Add a path there when Pi or the bootstrap starts writing a new state file.
- Every behavior change gets a test in `pibox/tests/test_adapter.py`.
