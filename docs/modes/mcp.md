---
title: "MCP mode"
description: "pibox MCP mode: expose run_prompt and workspace file tools over streamable HTTP, with its own bearer token and DNS rebinding protection."
parent: "Modes"
nav_order: 4
---

# MCP mode

`PIBOX_MCP_MODE=1`. Exposes an [MCP](https://modelcontextprotocol.io/) (Model Context Protocol) server over streamable HTTP, with `run_prompt`, `list_files`, `read_file`, `write_file` and `delete_file` as tools, so other agents can drive Pi as a tool.

MCP is the one mode that is not a foreground mode. It runs next to whatever else the container is doing.

| Foreground | MCP placement |
|---|---|
| API mode (`PIBOX_API_MODE=1`) | Mounted at `/mcp/` on the API port, with no extra process |
| Telegram, cron, or none | A sidecar server on `PIBOX_MCP_MODE_PORT` (default `8081`), serving at the port root `/` |

The slashless `/mcp` spelling reaches the same handler as `/mcp/` without a redirect.

## Setup

Next to cron: scheduled jobs running on their own, and the same box reachable as a tool while they run.

```yaml
# docker-compose.yml
services:
  pibox:
    image: psyb0t/pibox:latest
    ports:
      - "127.0.0.1:8081:8081"
    environment:
      - PIBOX_CRON_MODE=1
      - PIBOX_CRON_MODE_FILE=/home/aicode/.aicodebox/cron.yaml
      - PIBOX_MCP_MODE=1
      - PIBOX_MCP_MODE_TOKEN=some-long-random-string
      - PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic
      - PIBOX_PROVIDER_API=anthropic-messages
      - PIBOX_PROVIDER_API_KEY=your-z-ai-api-key
      - PIBOX_PROVIDER_MODEL=your-model-id
    volumes:
      - ~/.aicodebox:/home/aicode/.aicodebox
      - ~/workspaces:/workspace
```

Cron is the foreground process, so the container's lifetime follows the scheduler, and MCP rides along in the background. Swap the cron flags for `PIBOX_TELEGRAM_MODE=1` and the same holds for the bot.

In API mode you publish no second port, because MCP is already at `/mcp/` on the API port. See [API mode](api.md).

## Tools

| Tool | What it does |
|---|---|
| `run_prompt` | Runs a prompt through Pi and returns the reply text |
| `list_files` | Lists a directory under the workspace root |
| `read_file` | Reads a file |
| `write_file` | Writes a file |
| `delete_file` | Removes a file |

`run_prompt` takes `prompt` plus optional `workspace`, `model`, `system_prompt`, `append_system_prompt`, `no_continue`, `resume`, `thinking` and `json_schema`. Unlike `/run`, it starts a fresh session by default (`no_continue` is `true`).

The file tools resolve their path under the workspace root and reject anything that climbs out of it. This does not sandbox `run_prompt`: Pi runs with the container's own permissions.

## Auth

`PIBOX_MCP_MODE_TOKEN=<token>` is the bearer in the `Authorization: Bearer ...` header, or `?apiToken=...` for clients that cannot set headers.

Two things that will bite you if you assume otherwise:

- **Empty means no auth at all.** Not "no access", open. Anyone who can reach the port gets `run_prompt`, and `run_prompt` runs code. Leave it unset only when the port is bound to loopback or an internal network.
- **No fallback to `PIBOX_API_MODE_TOKEN`.** MCP has its own bearer, and setting the API token does nothing for it.

## Reverse proxies and public hosts

MCP keeps DNS rebinding protection enabled. Loopback hosts and origins work by default. If a reverse proxy, tunnel, or public DNS name forwards MCP, allow the exact values it sends. A browser MCP client also needs its exact Origin, including the scheme.

```dotenv
PIBOX_MCP_MODE_ALLOWED_HOSTS=localhost,localhost:*,127.0.0.1,127.0.0.1:*,[::1],[::1]:*,mcp.example.net
PIBOX_MCP_MODE_ALLOWED_ORIGINS=http://localhost:*,http://127.0.0.1:*,http://[::1]:*,https://mcp.example.net
```

An unexpected Host returns `421`, and an unexpected browser Origin returns `403`. Setting either variable replaces the loopback defaults, so keep the loopback entries as above. Keep the port bound to loopback when a local proxy terminates TLS. Do not disable the protection or allow broad wildcards for an internet-facing endpoint.

## MCP mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_MCP_MODE` | `0` | Expose MCP, mounted at `/mcp/` in API mode or as a sidecar elsewhere |
| `PIBOX_MCP_MODE_PORT` | `8081` | Port the sidecar MCP server binds to (ignored when mounted inside API) |
| `PIBOX_MCP_MODE_TOKEN` | empty | Bearer token for MCP. Empty means no auth. **No fallback to `PIBOX_API_MODE_TOKEN`** |
| `PIBOX_MCP_MODE_ALLOWED_HOSTS` | loopback hosts | Comma-separated MCP `Host` allowlist. Add each proxy host name |
| `PIBOX_MCP_MODE_ALLOWED_ORIGINS` | loopback HTTP origins | Comma-separated MCP browser Origin allowlist. Add each proxy origin |

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Connecting a client

The sidecar:

```bash
claude mcp add --transport http pibox http://host:8081/ \
  --header "Authorization: Bearer some-long-random-string"
```

Inside API mode:

```bash
claude mcp add --transport http pibox http://host:8080/mcp/ \
  --header "Authorization: Bearer some-long-random-string"
```

For clients that only speak stdio, use the OpenClaw bridge described in [Agent integrations](../agent-integrations.md#openclaw).
