# docker-pibox

[![CI](https://github.com/psyb0t/docker-pibox/actions/workflows/pipeline.yml/badge.svg?branch=main)](https://github.com/psyb0t/docker-pibox/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-pibox/badges/version.svg)](https://github.com/psyb0t/docker-pibox/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-pibox/badges/license.svg)](LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/pibox?style=flat-square)](https://hub.docker.com/r/psyb0t/pibox)

[pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) inside an [aicodebox](https://github.com/psyb0t/docker-aicodebox) container. One image, several ways in: interactive shell, one-shot prompt, HTTP API (with an OpenAI-compatible endpoint), MCP server, Telegram bot, and a cron scheduler that fires pi on whatever schedule you want.

You talk to pibox. pibox talks to pi. pi talks to whatever LLM you point it at. Nobody cares about the middle.

## Table of Contents

- [Quick start](#quick-start)
- [Modes](#modes)
  - [API mode](docs/modes/api.md)
  - [Telegram mode](docs/modes/telegram.md)
  - [Cron mode](docs/modes/cron.md)
  - [MCP mode](docs/modes/mcp.md)
- [Configuration](#configuration)
- [Auth](#auth)
- [Agent integrations](#agent-integrations)
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

Each mode has its own page with full setup, env vars, and examples.

### [API Mode →](docs/modes/api.md)

Long-lived FastAPI server on `:8080`. Agent runs (sync, async with run-id polling, cancellable), workspace file upload/download/list/delete with traversal checking, and an OpenAI-compatible `chat/completions` endpoint with streaming and client-executed tool calling.

```yaml
environment:
  - PIBOX_API_MODE=1
  - PIBOX_API_MODE_TOKEN=your-secret
  - PIBOX_AVAILABLE_MODELS=glm-4.6,glm-4.5-air
```

### [Telegram Mode →](docs/modes/telegram.md)

Talk to pi from Telegram. Per-chat isolated workspaces, allowed-chats and per-chat allowed-users gating, file ingestion, `[SEND_FILE: path]` to get files back, and per-chat `/model`, `/effort`, `/system_prompt`, `/append_system_prompt` overrides that persist across restarts.

```yaml
environment:
  - PIBOX_TELEGRAM_MODE=1
  - PIBOX_TELEGRAM_MODE_TOKEN=123456:ABC
```

### [Cron Mode →](docs/modes/cron.md)

YAML-defined scheduled jobs on 6-field croniter schedules. Per-run history dirs with `meta.json`, `stdout.log`, `stderr.log`, `result.txt`, and a "prior run" hint so a job can reference its own history.

```yaml
environment:
  - PIBOX_CRON_MODE=1
  - PIBOX_CRON_MODE_FILE=/home/aicode/.aicodebox/cron.yaml
```

### [MCP Mode →](docs/modes/mcp.md)

Exposes `run_prompt` plus workspace-confined file tools over streamable HTTP, so other agents can drive pi as a tool. Coexists with any foreground mode — mounted at `/mcp` on the API port in API mode, a sidecar on its own port everywhere else.

```yaml
environment:
  - PIBOX_MCP_MODE=1
  - PIBOX_MCP_MODE_TOKEN=your-secret
```

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

Each mode's own knobs (ports, tokens, config paths, history dirs) live on that mode's page: [api.md](docs/modes/api.md), [telegram.md](docs/modes/telegram.md), [cron.md](docs/modes/cron.md), [mcp.md](docs/modes/mcp.md).

### Workspace & runtime

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_WORKSPACE` | `/workspace` | Root workspace dir inside the container |
| `PIBOX_CONTAINER_NAME` | `aicodebox` | Used to scope per-container state files (auth, etc.) |
| `PIBOX_AVAILABLE_MODELS` | — | **Required for API mode.** CSV list returned by `/openai/v1/models` and shown in the telegram `/model` picker. API mode refuses to boot without it; telegram `/model` picker degrades to a "set this env var" reply. |
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

## Agent integrations

The [skill](.agents/skills/pibox) works in any agent that reads `.agents/skills/`, and
installs natively in the clients below.

### Claude Code

```bash
claude plugin marketplace add psyb0t/agents
claude plugin install pibox@psyb0t
```

Claude Code prompts for the pibox URL and, if auth is enabled, the API and MCP tokens —
sensitive values are stored in your OS keychain.

### Codex

```bash
codex plugin marketplace add psyb0t/agents
codex plugin add pibox@psyb0t
```

Installed via the marketplace, the skill invokes as `$pibox:pibox`. Codex also picks the
skill up automatically with no install in any repo containing `.agents/skills/`, where it
invokes as plain `$pibox`.

### OpenClaw

The skill is published to ClawHub on every release:

```bash
openclaw skills install @psyb0t/pibox
```

For MCP clients that speak local stdio, the [`@psyb0t/pibox`](.agents/plugins/pibox) plugin
bridges to the service's `/mcp` endpoint:

```bash
openclaw plugins install clawhub:@psyb0t/pibox
```

Then set `PIBOX_URL` (and `PIBOX_MCP_MODE_TOKEN` if the server was started with MCP auth
enabled).

## Development

```bash
make help   # list targets
make build  # pull the published aicodebox base, build + tag psyb0t/pibox:v<VERSION> and :latest
make test   # run the full e2e suite (needs .env.test)
make clean  # remove built images
```

`VERSION` is read from `pibox/pyproject.toml`. `make build` pulls the published `psyb0t/aicodebox` base pinned in the Dockerfile; set `SKIP_BASE_PULL=1` to use a locally-built base instead (e.g. from a sibling `../docker-aicodebox` checkout), or override with `make build BASE_IMAGE=...`.

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
