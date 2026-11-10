---
title: "Architecture"
description: "How pibox layers on aicodebox: the host wrapper, the pibox entrypoint and provider bootstrap, the base modes, and the PiAdapter that drives the Pi CLI."
nav_order: 10
---

# Architecture

pibox is a thin layer on the [aicodebox](https://github.com/psyb0t/docker-aicodebox) base image. The base owns the container entrypoint, the user and permission setup, the startup hooks, and every mode: the HTTP API, the OpenAI-compatible endpoint, MCP, Telegram and cron. pibox adds Pi and the pieces that connect it.

```text
host:      pibox (wrapper.sh)
             docker run psyb0t/pibox
container: pibox-entrypoint      PIBOX_* -> AICODEBOX_*, provider bootstrap
             aicodebox-entrypoint    user, hooks, mode selection
               mode (API, Telegram, cron, MCP) or plain Pi
                 PiAdapter           run request -> pi argv, NDJSON -> result
                   pi -p --mode json
                     upstream LLM
```

## The pieces

| Piece | Source | Role |
| --- | --- | --- |
| Host wrapper | [`wrapper.sh`](https://github.com/psyb0t/docker-pibox/blob/main/wrapper.sh) | Builds the `docker run` command: workspace and state mounts, forwarded variables, image choice, nested launch context |
| Installer | [`install.sh`](https://github.com/psyb0t/docker-pibox/blob/main/install.sh) | Creates the host directories and SSH key, pulls the image, installs the wrapper |
| pibox entrypoint | [`pibox-entrypoint.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox-entrypoint.sh) | Copies `PIBOX_*` to `AICODEBOX_*`, exports the provider key, runs the provider bootstrap, adds `--provider` and `--model` for plain Pi runs, then hands over to the base entrypoint |
| Provider bootstrap | [`setup-provider-env.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/scripts/setup-provider-env.sh) | Writes the managed provider into Pi's `models.json` and the selected provider and model into `pibox-provider.json` |
| Adapter | [`adapter.py`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/pibox/adapter.py) | `PiAdapter`, the aicodebox `AgentAdapter` for Pi |
| Startup script | [`10-pi-extensions.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/init.d/10-pi-extensions.sh) | Registers the MCP bridge extension in Pi's settings on first start |
| MCP bridge extension | [`mcp-bridge/index.ts`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/extensions/mcp-bridge/index.ts) | Gives Pi the tools of stdio MCP servers listed in a workspace `.mcp.json` |
| Images | [`Dockerfile`](https://github.com/psyb0t/docker-pibox/blob/main/Dockerfile), [`Dockerfile.full`](https://github.com/psyb0t/docker-pibox/blob/main/Dockerfile.full) | Install Pi from npm, the adapter with `uv pip --no-deps`, the extension's npm dependencies, and set `AICODEBOX_ADAPTER=pibox.adapter:PiAdapter` |

## The adapter

The base modes turn every request into a run request and hand it to the adapter named by `AICODEBOX_ADAPTER`. `PiAdapter` then:

- **Builds the command line.** It always runs `pi -p --mode json`, because only the JSON event stream carries the session ID, usage and errors. It maps the request to `--model`, `--thinking`, `--system-prompt`, `--append-system-prompt`, `--session`, `--no-session` or `--continue`, `--tools` or `--no-tools`, then appends any extra arguments. A JSON schema becomes an extra appended system prompt, since Pi has no schema option. The prompt goes to stdin, never to the arguments.
- **Pins the provider.** When the provider bootstrap left a marker in `pibox-provider.json`, or `ANTHROPIC_BASE_URL` is set, it adds `--provider` unless the caller chose one, so a model name cannot be claimed by one of Pi's built-in providers.
- **Validates.** It rejects unknown thinking levels and a tool allowlist combined with `noTools`.
- **Parses the output.** It reads the NDJSON stream for the session ID, the assistant text from `message_end` events, usage from `turn_end`, and provider errors from assistant turns that stop with `stopReason: error`. Usage is reported under both Pi's names (`input`, `output`) and the OpenAI-style names (`input_tokens`, `output_tokens`).
- **Streams.** For streaming chat, it turns `text_delta` events into text chunks and `agent_end` into the stop reason. Thinking and tool events are not sent to the stream.
- **Names Pi's state.** `auth_paths` lists `auth.json`, `settings.json`, `models.json`, `pibox-provider.json` and `sessions` under `~/.pi/agent`.

## The provider flow

1. The entrypoint sees a `PIBOX_PROVIDER_*` variable, or `ANTHROPIC_BASE_URL`.
2. The bootstrap runs as `aicode`, validates the settings, and writes the provider entry with every model from the primary model plus `PIBOX_AVAILABLE_MODELS`. For the generic path, the key stays in the environment as `OPENAI_API_KEY`.
3. Plain `pibox` and `pibox -p` runs get `--provider` and `--model` from the entrypoint. Mode runs get them from the adapter.

## What lives where

| Path in the container | Host source with the wrapper | Contents |
| --- | --- | --- |
| The workspace path | The directory you ran `pibox` from | Your files |
| `/home/aicode/.pi` | `PIBOX_DATA_DIR`, default `~/.pi` | Pi settings, auth, `models.json`, `pibox-provider.json`, sessions |
| `/home/aicode/.aicodebox` | `PIBOX_STATE_DIR`, default `~/.aicodebox` | Mode configuration, cron history, Telegram overrides, `bin/`, `init.d/` |
| `/home/aicode/.ssh` | `PIBOX_SSH_DIR`, default `~/.ssh/pibox` | The SSH key from the installer |
| `/opt/pibox` | The image | The adapter, scripts and the MCP bridge extension |
