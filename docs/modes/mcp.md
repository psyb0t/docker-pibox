# MCP Mode

`PIBOX_MCP_MODE=1`. Exposes the [MCP](https://modelcontextprotocol.io/) (Model Context Protocol) surface over streamable HTTP — `run_prompt`, `list_files`, `read_file`, `write_file`, `delete_file` as tools — so other agents can drive pi as a tool.

MCP is the one mode that is not a foreground mode. It coexists with whatever else the container is doing.

| Foreground | MCP placement |
|---|---|
| API mode (`PIBOX_API_MODE=1`) | mounted at `/mcp` on the API port — no extra process |
| Telegram / Cron / passthrough | sidecar uvicorn on `PIBOX_MCP_MODE_PORT` (default `8081`) |

## Setup

Standalone alongside cron — scheduled jobs running on their own, and the same box reachable as a tool while they run:

```yaml
# docker-compose.yml
services:
  pibox:
    image: psyb0t/pibox:latest
    ports:
      - "8081:8081"
    environment:
      - PIBOX_CRON_MODE=1
      - PIBOX_CRON_MODE_FILE=/home/aicode/.aicodebox/cron.yaml
      - PIBOX_MCP_MODE=1
      - PIBOX_MCP_MODE_TOKEN=some-long-random-string
      - ANTHROPIC_AUTH_TOKEN=your-token
      - ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
      - ANTHROPIC_MODEL=glm-4.6
    volumes:
      - ~/.aicodebox:/home/aicode/.aicodebox
      - ~/workspaces:/workspace
```

Cron is the foreground process, so the container's lifetime follows the scheduler. MCP rides along in the background. Swap the cron flags for `PIBOX_TELEGRAM_MODE=1` and the same holds for the bot.

In API mode you publish no second port — MCP is already at `/mcp` on the API port. See [api.md](api.md).

## Tools

| Tool | What it does |
|---|---|
| `run_prompt` | Runs a prompt through pi and returns the response |
| `list_files` | Lists a directory under the workspace root |
| `read_file` | Reads a file |
| `write_file` | Writes a file |
| `delete_file` | Removes a file |

The file tools resolve their path under the workspace root and reject anything that climbs out of it. This does not sandbox `run_prompt` — pi runs with the container's own permissions.

## Auth

`PIBOX_MCP_MODE_TOKEN=<token>` — bearer in the `Authorization: Bearer …` header, or `?apiToken=…` for clients that can't set headers.

Two things that will bite you if you assume otherwise:

- **Empty means no auth at all.** Not "no access" — open. Anyone who can reach the port gets `run_prompt`, and `run_prompt` runs code. Leave it unset only when the port is bound to loopback or an internal network.
- **No fallback to `API_MODE_TOKEN`.** MCP has its own bearer; setting the API token does nothing for it.

## MCP mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_MCP_MODE` | `0` | Expose MCP — mounted at `/mcp` in API mode, or as a sidecar elsewhere |
| `PIBOX_MCP_MODE_PORT` | `8081` | Port the sidecar MCP server binds to (ignored when mounted inside API) |
| `PIBOX_MCP_MODE_TOKEN` | empty | Bearer token for MCP. Empty = no auth. **No fallback to `API_MODE_TOKEN`** |

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Connecting a client

```bash
claude mcp add --transport http pibox http://host:8081/mcp \
  --header "Authorization: Bearer some-long-random-string"
```
