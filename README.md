# docker-pibox

[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/pibox?style=flat-square)](https://hub.docker.com/r/psyb0t/pibox)
[![License: WTFPL](https://img.shields.io/badge/License-WTFPL-brightgreen.svg?style=flat-square)](http://www.wtfpl.net/)

[pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) inside an [aicodebox](https://github.com/psyb0t/docker-aicodebox) container. One image, five ways in: interactive shell, one-shot API, OpenAI-compatible endpoint, MCP server, Telegram bot, and a cron scheduler that fires pi on whatever schedule you want.

You talk to pibox. pibox talks to pi. pi talks to whatever LLM you point it at. Nobody cares about the middle.

## Table of Contents

- [Quick start](#quick-start)
- [Modes](#modes)
  - [API mode](#api-mode)
  - [Telegram mode](#telegram-mode)
  - [Cron mode](#cron-mode)
- [Configuration](#configuration)
- [Auth](#auth)
- [Development](#development)
- [Tests](#tests)
- [License](#license)

## Quick start

```bash
# one-shot prompt
docker run --rm \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"

# API server
docker run -d --network host \
  -e PIBOX_API_MODE=1 \
  -e PIBOX_API_MODE_TOKEN=your-secret \
  -e PIBOX_AVAILABLE_MODELS=glm-4.6,glm-4.5-air \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

## Modes

**Foreground modes** (API / Telegram / Cron) are mutually exclusive — except `PIBOX_TELEGRAM_MODE=1` + `PIBOX_CRON_MODE=1`, which run together (cron in-thread inside telegram). API wins if set alongside anything else.

**MCP mode** (`PIBOX_MCP_MODE=1`) is independent — it coexists with whatever foreground mode is running. In API mode it's mounted at `/mcp` on the API port; in other modes it runs as a sidecar uvicorn on its own port.

### API mode

`PIBOX_API_MODE=1`. FastAPI server on `:8080` (override with `PIBOX_API_MODE_PORT`).

> **Required:** `PIBOX_AVAILABLE_MODELS=<csv>` (e.g. `glm-4.6,claude-sonnet-4-6`). API mode refuses to boot without it — `/v1/models` needs a real list and there's no sensible default (pi can drive any provider's models). Pick the ones your configured `ANTHROPIC_BASE_URL` / provider actually serves.

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/healthz` | liveness |
| `GET` | `/status` | in-flight runs |
| `POST` | `/run` | sync agent run → `{text, exit_code, ...}` |
| `POST` | `/run/async` | fire and get a job id back |
| `GET` | `/run/{id}` | poll async job |
| `POST` | `/run/{id}/cancel` | kill in-flight run |
| `GET` | `/files` | list the workspace root (`{entries: [{name, type, size?}, ...]}`) |
| `GET` | `/files/{path}` | list a sub-directory, or stream a file's bytes |
| `PUT` | `/files/{path}` | upload — raw request body becomes the file contents; parent dirs auto-created |
| `DELETE` | `/files/{path}` | delete a file (refuses directories — 400) |
| `POST` | `/v1/chat/completions` | OpenAI-compatible (streaming + non-streaming) |
| `GET` | `/v1/models` | model list |
| `POST` | `/mcp` | MCP server (streamable HTTP) — mounted only when `PIBOX_MCP_MODE=1` |

All `/files/*` paths are resolved against the workspace root with traversal checking — `..` segments that escape the root return 400. Same `Authorization: Bearer ...` token gates them as the rest of the API.

```bash
# upload a file
curl -sS -X PUT \
  -H "Authorization: Bearer your-secret" \
  --data-binary @local.txt \
  http://localhost:8080/files/notes/hello.txt

# download it back
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt

# list the dir
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes | jq

# delete it
curl -sS -X DELETE -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt
```

**`POST /run`** body: `prompt` (required), `workspace`, `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `outputFormat`, `noContinue`, `resume`, `timeoutSeconds`, `thinking`, `noTools`, `toolsAllowlist`.

```bash
curl -s http://localhost:8080/run \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "say HELLO", "workspace": "/workspace"}'
```

### Telegram mode

`PIBOX_TELEGRAM_MODE=1` + `PIBOX_TELEGRAM_MODE_TOKEN=<token>`.

- Text in → pi runs → Markdown→HTML rendered response back.
- File uploads land in the chat's workspace. `[SEND_FILE: path]` in pi's output delivers workspace files as Telegram attachments.
- Per-chat overrides: `/model`, `/effort` (maps to pi's `--thinking` levels), `/system_prompt`, `/append_system_prompt`. Persisted across restarts.
- `/cancel` kills the in-flight run. `/reload` re-reads config. `/config` dumps merged settings. `/fetch <path>` downloads a file.
- Replies to cron messages inject the job's instruction + result so pi has full context for follow-ups.

Config at `$HOME/.aicodebox/telegram.yml` (override via `PIBOX_TELEGRAM_MODE_CONFIG`):

```yaml
allowed_chats: [-100123, 42]
default:
  model: glm-4.6
  workspace: shared
chats:
  -100123:
    workspace: alpha
    allowed_users: [10, 20]
```

### Cron mode

`PIBOX_CRON_MODE=1` + `PIBOX_CRON_MODE_FILE=/path/to/cron.yaml`. 6-field schedules via croniter. Each job fires pi with the given instruction.

```yaml
jobs:
  - name: morning-standup
    schedule: "0 0 9 * * 1-5"
    instruction: |
      Summarize what changed in /workspace since yesterday.
      Be brief. One paragraph max.
    workspace: myproject
    telegram_chat_id: -100123
    model: glm-4.6
    thinking: low
```

Each run gets a history dir at `$HOME/.aicodebox/cron/history/<workspace>/<timestamp>-<job>/` with `meta.json`, `stdout.log`, `stderr.log`, `result.txt`. If telegram is configured, `telegram.json` lands there too and the next run's prompt gets a "prior run" hint so pi can reference its own history without you wiring it up.

### MCP mode

`PIBOX_MCP_MODE=1`. Exposes the MCP (Model Context Protocol) surface — `run_prompt`, `list_files`, `read_file`, `write_file`, `delete_file` as tools. Coexists with any foreground mode:

| Foreground | MCP placement |
|---|---|
| API mode (`PIBOX_API_MODE=1`) | mounted at `/mcp` on the API port — no extra process |
| Telegram / Cron / passthrough | sidecar uvicorn on `PIBOX_MCP_MODE_PORT` (default `8081`) |

Auth: `PIBOX_MCP_MODE_TOKEN=<token>` — bearer in the `Authorization: Bearer …` header, or `?apiToken=…` for clients that can't set headers. Empty = no auth. **No fallback to `API_MODE_TOKEN`** — MCP has its own bearer.

## Configuration

Naming convention: `PIBOX_<MODE>_MODE=1` is the on/off flag, `PIBOX_<MODE>_MODE_<KNOB>=...` is its config. Non-mode-scoped vars (workspace, container name, available models) are bare.

The image is built on top of [aicodebox](https://github.com/psyb0t/docker-aicodebox), so the equivalent `AICODEBOX_*` names also work — the entrypoint translates `PIBOX_X` to `AICODEBOX_X` when only the pibox-prefixed one is set. If you set both, `AICODEBOX_*` wins.

### Mode flags

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_API_MODE` | `0` | Boot the HTTP API server (foreground) |
| `PIBOX_TELEGRAM_MODE` | `0` | Boot the Telegram bot (foreground) |
| `PIBOX_CRON_MODE` | `0` | Boot the cron scheduler (foreground; in-thread when telegram is also on) |
| `PIBOX_MCP_MODE` | `0` | Expose MCP — mounted at `/mcp` in API mode, or as a sidecar elsewhere |

### API mode config

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_API_MODE_PORT` | `8080` | Port the API server binds to |
| `PIBOX_API_MODE_TOKEN` | empty | Bearer token for the API surface. Empty = no auth |

### Telegram mode config

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_TELEGRAM_MODE_TOKEN` | — | Bot token from @BotFather |
| `PIBOX_TELEGRAM_MODE_CONFIG` | `~/.aicodebox/telegram.yml` | Path to the telegram config yaml |
| `PIBOX_TELEGRAM_MODE_OVERRIDES` | `~/.aicodebox/telegram_overrides.json` | Per-chat override store (model/effort/system prompts) |

### Cron mode config

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_CRON_MODE_FILE` | — | Path to the cron yaml |
| `PIBOX_CRON_MODE_HISTORY_DIR` | `~/.aicodebox/cron/history` | Where cron writes per-run history dirs (`meta.json`, `stdout.log`, `stderr.log`, `result.txt`, `telegram.json`) |

### MCP mode config

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_MCP_MODE_PORT` | `8081` | Port the sidecar MCP server binds to (ignored when mounted inside API) |
| `PIBOX_MCP_MODE_TOKEN` | empty | Bearer token for MCP. Empty = no auth. **No fallback to `API_MODE_TOKEN`** |

### Workspace & runtime

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_WORKSPACE` | `/workspace` | Root workspace dir inside the container |
| `PIBOX_CONTAINER_NAME` | `aicodebox` | Used to scope per-container state files (auth, etc.) |
| `PIBOX_AVAILABLE_MODELS` | — | **Required for API mode.** CSV list returned by `/v1/models` and shown in the telegram `/model` picker. API mode refuses to boot without it; telegram `/model` picker degrades to a "set this env var" reply. |
| `PIBOX_AVAILABLE_EFFORTS` | adapter list | Override the effort/`--thinking` list shown by the telegram `/effort` picker (comma-separated) |

## Auth

pi speaks the Anthropic wire protocol. Point it at any Anthropic-compatible endpoint:

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_AUTH_TOKEN` | Bearer token (Z.AI, direct Anthropic, etc.) |
| `ANTHROPIC_API_KEY` | Same thing — pi reads both |
| `ANTHROPIC_BASE_URL` | Endpoint override (default: `https://api.anthropic.com`) |
| `ANTHROPIC_MODEL` | Default model when the caller doesn't specify one |

Z.AI's GLM models are fast and cheap for most tasks — `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic` + `ANTHROPIC_MODEL=glm-4.6` is the recommended default.

pi's thinking levels (`--thinking`): `off`, `minimal`, `low`, `medium`, `high`, `xhigh`. Exposed as the `/effort` command in telegram mode and as `thinking` in API requests.

## Development

Requires `psyb0t/docker-aicodebox` checked out next to this repo (`../docker-aicodebox`).

```bash
make help        # list targets
make build-base  # build aicodebox-base from ../docker-aicodebox
make build       # build pibox:local on top of it
make test        # run the full e2e suite (needs .env.test)
make clean       # remove built images
```

## Tests

End-to-end tests build the image and run it against a real LLM endpoint. Telegram tests use [psyb0t/telethon-plus](https://github.com/psyb0t/docker-telethon) as a real MTProto userbot.

```bash
cp .env.test.example .env.test
$EDITOR .env.test   # fill in ANTHROPIC_* and optionally Telegram creds
make test
```

Telegram tests auto-skip if `AICODEBOX_TELEGRAM_MODE_TOKEN` is empty. Everything else only needs `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`.

## License

WTFPL — see [LICENSE](LICENSE). Do what the fuck you want.
