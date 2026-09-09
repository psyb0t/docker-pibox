# pibox setup

## Requirements

- Docker
- An LLM endpoint supported by Pi's custom HTTP provider configuration. `PIBOX_PROVIDER_*` accepts an endpoint URL, protocol, API key or token, and model. It covers LiteLLM, Anthropic Messages endpoints, and Google Generative AI. `ANTHROPIC_*` remains available for existing Anthropic-compatible deployments. Pi drives the model; pibox drives Pi.
- A host workspace directory to bind-mount (`-v $PWD/workspace:/workspace`), so agent output/session state persists across container restarts.

## Quick Install

### Interactive / one-shot (no server)

```bash
docker run -it --rm \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

Append `-p "your prompt"` (or any other pi CLI flags) to the `docker run` line for one-shot exec instead of an interactive shell.

### REST / OpenAI-compatible / MCP server

```bash
docker run -d --name pibox --network host \
  -e PIBOX_API_MODE=1 \
  -e PIBOX_API_MODE_TOKEN=your-secret \
  -e PIBOX_AVAILABLE_MODELS=glm-4.6,glm-4.5-air \
  -e PIBOX_MCP_MODE=1 \
  -e PIBOX_MCP_MODE_TOKEN=your-mcp-secret \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

`--network host` is convenient for local use; for anything else publish the port explicitly (`-p 8080:8080`) instead.

**Verify:** `curl http://localhost:8080/healthz` returns `{"ok": true, "adapter": "pi"}`.

### Telegram bot

```bash
docker run -d --name pibox-tg \
  -e PIBOX_TELEGRAM_MODE=1 \
  -e PIBOX_TELEGRAM_MODE_TOKEN=your-bot-token \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  -v "$PWD/telegram.yml:/home/aicode/.aicodebox/telegram.yml:ro" \
  psyb0t/pibox:latest
```

Requires a `telegram.yml` with at least `allowed_chats` set (see [Telegram bot mode](../SKILL.md#telegram-bot-mode)) — the bot ignores messages from chats not on the allowlist.

### Cron scheduler

```bash
docker run -d --name pibox-cron \
  -e PIBOX_CRON_MODE=1 \
  -e PIBOX_CRON_MODE_FILE=/config/cron.yaml \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  -v "$PWD/cron.yaml:/config/cron.yaml:ro" \
  psyb0t/pibox:latest
```

### docker-compose (API + MCP)

```yaml
services:
  pibox:
    image: psyb0t/pibox:latest
    environment:
      PIBOX_API_MODE: "1"
      PIBOX_API_MODE_TOKEN: your-secret
      PIBOX_AVAILABLE_MODELS: glm-4.6,glm-4.5-air
      PIBOX_MCP_MODE: "1"
      PIBOX_MCP_MODE_TOKEN: your-mcp-secret
      ANTHROPIC_AUTH_TOKEN: your-token
      ANTHROPIC_BASE_URL: https://api.z.ai/api/anthropic
      ANTHROPIC_MODEL: glm-4.6
    ports:
      - "8080:8080"
    volumes:
      - ./workspace:/workspace
    restart: unless-stopped
```

## Foreground Mode Rules

`PIBOX_API_MODE`, `PIBOX_TELEGRAM_MODE`, `PIBOX_CRON_MODE` are the foreground modes. Priority order if multiple are set: API wins over everything. Telegram + Cron together is the one allowed pairing (cron runs in-thread inside the telegram process). If none are set, the container falls through to pi's own CLI (interactive shell, or one-shot exec if args are passed).

`PIBOX_MCP_MODE` is independent of the above — it coexists with any foreground mode (mounted at `/mcp` in API mode, sidecar elsewhere) or with none at all (sidecar only, no other surface reachable).

## Environment Variables

Naming convention: `PIBOX_<MODE>_MODE=1` is the on/off flag, `PIBOX_<MODE>_MODE_<KNOB>=...` is its config. Non-mode-scoped vars (workspace, container name, available models) are bare `PIBOX_*`.

The image is built on [aicodebox](https://github.com/psyb0t/docker-aicodebox); the equivalent `AICODEBOX_*` names also work — the entrypoint translates `PIBOX_X` to `AICODEBOX_X` when only the pibox-prefixed one is set. If both are set, `AICODEBOX_*` wins.

### Mode flags

| Var | Default | What it does |
|-----|---------|---------------|
| `PIBOX_API_MODE` | `0` | Boot the HTTP API server (foreground) |
| `PIBOX_TELEGRAM_MODE` | `0` | Boot the Telegram bot (foreground) |
| `PIBOX_CRON_MODE` | `0` | Boot the cron scheduler (foreground; in-thread when telegram is also on) |
| `PIBOX_MCP_MODE` | `0` | Expose MCP — mounted at `/mcp` in API mode, or as a sidecar elsewhere |

### API mode config

| Var | Default | What it does |
|-----|---------|---------------|
| `PIBOX_API_MODE_PORT` | `8080` | Port the API server binds to |
| `PIBOX_API_MODE_TOKEN` | empty | Bearer token for the REST + OpenAI-compatible surface. Empty = no auth — see [Security & safety](../SKILL.md#security--safety) |

### Telegram mode config

| Var | Default | What it does |
|-----|---------|---------------|
| `PIBOX_TELEGRAM_MODE_TOKEN` | — | Bot token from @BotFather (required) |
| `PIBOX_TELEGRAM_MODE_CONFIG` | `~/.aicodebox/telegram.yml` | Path to the telegram config yaml |
| `PIBOX_TELEGRAM_MODE_OVERRIDES` | `~/.aicodebox/telegram_overrides.json` | Per-chat override store (model/effort/system prompts) |

### Cron mode config

| Var | Default | What it does |
|-----|---------|---------------|
| `PIBOX_CRON_MODE_FILE` | — | Path to the cron yaml (required) |
| `PIBOX_CRON_MODE_HISTORY_DIR` | `~/.aicodebox/cron/history` | Where cron writes per-run history dirs (`meta.json`, `stdout.log`, `stderr.log`, `result.txt`, `telegram.json`) |

### MCP mode config

| Var | Default | What it does |
|-----|---------|---------------|
| `PIBOX_MCP_MODE_PORT` | `8081` | Port the sidecar MCP server binds to (ignored when mounted inside API mode) |
| `PIBOX_MCP_MODE_TOKEN` | empty | Bearer token for MCP. Empty = no auth — see [Security & safety](../SKILL.md#security--safety). No fallback to `PIBOX_API_MODE_TOKEN` |

### Workspace & runtime

| Var | Default | What it does |
|-----|---------|---------------|
| `PIBOX_WORKSPACE` | `/workspace` | Root workspace dir inside the container |
| `PIBOX_CONTAINER_NAME` | `aicodebox` | Used to scope per-container state files (auth, etc.) |
| `PIBOX_AVAILABLE_MODELS` | — | **Required for API mode.** CSV list returned by `/openai/v1/models` and shown in the telegram `/model` picker |
| `PIBOX_AVAILABLE_EFFORTS` | adapter list (`off,minimal,low,medium,high,xhigh`) | Override the effort/`--thinking` list shown by the telegram `/effort` picker (comma-separated) |

### LLM upstream

#### Generic custom HTTP provider

Use these variables for Pi's documented custom HTTP APIs. They configure the upstream model Pi uses, not pibox's own OpenAI-compatible `/openai/v1` endpoint.

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_PROVIDER_NAME` | `pibox` | Provider identifier. Lowercase letters, numbers, and `-` only. |
| `PIBOX_PROVIDER_API` | `openai-completions` | `openai-completions`, `openai-responses`, `anthropic-messages`, or `google-generative-ai` |
| `PIBOX_PROVIDER_BASE_URL` | none | Required upstream HTTP base URL |
| `PIBOX_PROVIDER_API_KEY` | none | Required upstream API key or token |
| `PIBOX_PROVIDER_MODEL` | none | Required default upstream model ID |

LiteLLM example:

```bash
docker run --rm --network host \
  -e PIBOX_PROVIDER_BASE_URL=http://127.0.0.1:4000/v1 \
  -e PIBOX_PROVIDER_API=openai-completions \
  -e PIBOX_PROVIDER_API_KEY=your-litellm-virtual-key \
  -e PIBOX_PROVIDER_MODEL=your-model-id \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"
```

For API mode, set `PIBOX_AVAILABLE_MODELS=your-model-id` too. Do not combine `PIBOX_PROVIDER_*` with `ANTHROPIC_BASE_URL`. pibox rejects the ambiguous configuration. The generic variables cover Pi's documented custom HTTP APIs, not every cloud-specific built-in provider.

#### Anthropic compatibility

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_AUTH_TOKEN` | Bearer token (Z.AI, direct Anthropic, etc.) |
| `ANTHROPIC_API_KEY` | Same thing — pi reads both |
| `ANTHROPIC_BASE_URL` | Endpoint override (default `https://api.anthropic.com`) |
| `ANTHROPIC_MODEL` | Default model when the caller doesn't specify one |

## OpenAI endpoint headers

Non-standard `x-aicodebox-*` request headers extend `POST /openai/v1/chat/completions` beyond stock OpenAI fields (legacy `x-claude-*` aliases also work for `workspace`/`continue`/`append-system-prompt`):

| Header | Purpose |
|---|---|
| `x-aicodebox-workspace` | Pin the run to a workspace subpath instead of the ephemeral/default one |
| `x-aicodebox-continue` | `1`/`true`/`yes` to continue the most recent session in that workspace instead of starting fresh |
| `x-aicodebox-append-system-prompt` | Append text to the system prompt |
| `x-aicodebox-json-schema` | JSON-encoded schema — fallback for clients that can't set the standard `response_format` body field (body field wins if both are set) |
| `x-aicodebox-resume` | Resume a specific session id |
| `x-aicodebox-extra-args` | Extra pi CLI args — JSON array or comma-separated string |
| `x-aicodebox-timeout-seconds` | Per-request run timeout |
| `x-aicodebox-tools-allowlist` | Restrict pi's own internal tools — JSON array or comma-separated string |
| `x-aicodebox-no-tools` | `1`/`true`/`yes` to disable pi's internal tools; in OpenAI-tools mode this is the override to re-enable them (send `0`) |

## Ports

| Port | Default | Service |
|---|---|---|
| API/OAI/MCP-in-API | `8080` (`PIBOX_API_MODE_PORT`) | REST, `/openai/v1/*`, `/mcp` (when `PIBOX_MCP_MODE=1`) |
| MCP sidecar | `8081` (`PIBOX_MCP_MODE_PORT`) | MCP only, used when API mode is not the foreground |

No ports are opened for Telegram, cron, interactive, or one-shot exec modes — they're outbound-only or container-boundary-trusted.

## Management

```bash
docker logs -f pibox    # tail logs
docker stop pibox       # stop
docker rm pibox          # remove
docker pull psyb0t/pibox:latest  # update
```

Check what's running inside a live API-mode container:

```bash
curl -s http://localhost:8080/status -H "Authorization: Bearer your-secret" | jq
```

## OpenClaw / ClawHub Config

```bash
export PIBOX_URL=http://localhost:8080
export PIBOX_API_MODE_TOKEN=<token>  # only if the server requires it
```

Or via `~/.openclaw/openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "pibox": {
        "env": {
          "PIBOX_URL": "http://localhost:8080",
          "PIBOX_API_MODE_TOKEN": "<token>"
        }
      }
    }
  }
}
```
