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
  -e AICODEBOX_MODE_API=1 \
  -e AICODEBOX_AUTH_TOKENS=your-secret \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

## Modes

One mode per container, with one exception: `AICODEBOX_MODE_TELEGRAM=1` and `AICODEBOX_MODE_CRON=1` can run together — cron runs in-thread inside the telegram process. API mode always takes priority if set alongside anything else.

### API mode

`AICODEBOX_MODE_API=1`. FastAPI server on `:8080`.

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/healthz` | liveness |
| `GET` | `/status` | in-flight runs |
| `POST` | `/run` | sync agent run → `{text, exit_code, ...}` |
| `POST` | `/run/async` | fire and get a job id back |
| `GET` | `/run/{id}` | poll async job |
| `POST` | `/run/{id}/cancel` | kill in-flight run |
| `POST` | `/v1/chat/completions` | OpenAI-compatible (streaming + non-streaming) |
| `GET` | `/v1/models` | model list |
| `POST` | `/mcp` | MCP server (streamable HTTP) |

**`POST /run`** body: `prompt` (required), `workspace`, `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `outputFormat`, `noContinue`, `resume`, `timeoutSeconds`, `thinking`, `noTools`, `toolsAllowlist`.

```bash
curl -s http://localhost:8080/run \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "say HELLO", "workspace": "/workspace"}'
```

### Telegram mode

`AICODEBOX_MODE_TELEGRAM=1` + `AICODEBOX_TELEGRAM_BOT_TOKEN=<token>`.

- Text in → pi runs → Markdown→HTML rendered response back.
- File uploads land in the chat's workspace. `[SEND_FILE: path]` in pi's output delivers workspace files as Telegram attachments.
- Per-chat overrides: `/model`, `/effort` (maps to pi's `--thinking` levels), `/system_prompt`, `/append_system_prompt`. Persisted across restarts.
- `/cancel` kills the in-flight run. `/reload` re-reads config. `/config` dumps merged settings. `/fetch <path>` downloads a file.
- Replies to cron messages inject the job's instruction + result so pi has full context for follow-ups.

Config at `$HOME/.aicodebox/telegram.yml`:

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

`AICODEBOX_MODE_CRON=1` + `AICODEBOX_MODE_CRON_FILE=/path/to/cron.yaml`. 6-field schedules via croniter. Each job fires pi with the given instruction.

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

## Configuration

| Var | Default | What it does |
|-----|---------|--------------|
| `AICODEBOX_MODE_API` | `0` | Boot the HTTP API server |
| `AICODEBOX_MODE_TELEGRAM` | `0` | Boot the Telegram bot |
| `AICODEBOX_MODE_CRON` | `0` | Boot the cron scheduler |
| `AICODEBOX_MODE_CRON_FILE` | — | Path to cron yaml |
| `AICODEBOX_TELEGRAM_BOT_TOKEN` | — | Bot token from @BotFather |
| `AICODEBOX_TELEGRAM_CONFIG` | `~/.aicodebox/telegram.yml` | Telegram config yaml |
| `AICODEBOX_AUTH_TOKENS` | empty | Comma-separated bearer tokens for API + MCP |
| `AICODEBOX_WORKSPACE` | `/workspace` | Root workspace dir |
| `AICODEBOX_AVAILABLE_MODELS` | adapter list | Override model list in `/v1/models` + `/model` picker |

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

Telegram tests auto-skip if `AICODEBOX_TELEGRAM_BOT_TOKEN` is empty. Everything else only needs `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL`.

## License

WTFPL — see [LICENSE](LICENSE). Do what the fuck you want.
