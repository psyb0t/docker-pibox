---
title: "Configuration"
description: "Every pibox environment variable: mode flags, workspace and runtime settings, PIBOX_ to AICODEBOX_ aliasing, Git identity, bin/ and init.d/ hooks."
nav_order: 3
---

# Configuration

pibox is configured with environment variables. Through the wrapper, set them on the host and the wrapper forwards every `PIBOX_*` variable into the container. With plain `docker run`, pass them with `-e` or `--env-file`. [`.env.example`](https://github.com/psyb0t/docker-pibox/blob/main/.env.example) lists the container settings.

The wrapper's own host-side settings (`PIBOX_IMAGE`, `PIBOX_FULL`, `PIBOX_DETACH`, the data directories and the memory limit) are on [Install and the wrapper](install.md#wrapper-settings). The upstream LLM settings are on [LLM providers](providers.md).

## Naming

`PIBOX_<MODE>_MODE=1` turns a mode on. `PIBOX_<MODE>_MODE_<KNOB>` configures it. Settings that do not belong to one mode, such as the workspace or the model list, have a bare `PIBOX_` name.

The base image reads `AICODEBOX_*` names. [`pibox-entrypoint.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox-entrypoint.sh) copies each `PIBOX_X` to `AICODEBOX_X` when `AICODEBOX_X` is unset or empty, then starts the base entrypoint. So both spellings work, and if you set both, the `AICODEBOX_*` value wins. The aliased names are the ones in the tables below.

## Mode flags

| Variable | Default | What it does |
| --- | --- | --- |
| `PIBOX_API_MODE` | `0` | Start the HTTP API server in the foreground |
| `PIBOX_TELEGRAM_MODE` | `0` | Start the Telegram bot in the foreground |
| `PIBOX_CRON_MODE` | `0` | Start the cron scheduler in the foreground, or inside the bot when Telegram is also on |
| `PIBOX_MCP_MODE` | `0` | Expose MCP, at `/mcp/` in API mode or as a sidecar otherwise |

[Modes](modes.md) explains which flags combine. Each mode's own settings (ports, tokens, configuration files, history) are on its page: [API](modes/api.md), [Telegram](modes/telegram.md), [cron](modes/cron.md) and [MCP](modes/mcp.md).

## Workspace and runtime

| Variable | Default | What it does |
| --- | --- | --- |
| `PIBOX_WORKSPACE` | `/workspace` | Root workspace directory inside the container. The wrapper sets it to the host directory you ran `pibox` from |
| `PIBOX_CONTAINER_NAME` | `aicodebox` | Scopes per-container state files. The wrapper sets a per-workspace name |
| `PIBOX_AVAILABLE_MODELS` | none | Comma-separated model IDs. Required for API mode. Listed by `/openai/v1/models`, offered by the Telegram `/model` picker, and registered with the upstream provider |
| `PIBOX_AVAILABLE_EFFORTS` | `off,minimal,low,medium,high,xhigh` | Comma-separated thinking levels offered by the Telegram `/effort` picker |
| `DEBUG` | `false` | `1`, `true` or `yes` switches the mode logs to debug level and to one JSON object per line. It has no `PIBOX_` alias, so through the wrapper send it as `PIBOX_ENV_DEBUG` |

Pi's thinking levels are `off`, `minimal`, `low`, `medium`, `high` and `xhigh`. The API takes them as `thinking`, Telegram as `/effort`, and the Pi CLI as `--thinking`. The adapter rejects any other value.

## Git identity

| Variable | What it does |
| --- | --- |
| `PIBOX_GIT_NAME` | Global Git `user.name` for the runtime user |
| `PIBOX_GIT_EMAIL` | Global Git `user.email` for the runtime user |

The identity is applied before the startup hooks run. A nonempty `AICODEBOX_GIT_NAME` or `AICODEBOX_GIT_EMAIL` inside the container wins over the pibox value. Through the wrapper, send those shared values as `AICODEBOX_ENV_AICODEBOX_GIT_NAME` and `AICODEBOX_ENV_AICODEBOX_GIT_EMAIL`. An empty setting leaves the existing Git configuration alone, and a value with a line break is rejected at startup.

## The state directory

The state directory is `/home/aicode/.aicodebox` inside the container, mounted from `PIBOX_STATE_DIR` (`~/.aicodebox` by default) by the wrapper. Besides mode configuration and history, it holds two hook directories:

- `bin/`: executables here are on `PATH` ahead of everything else, for Pi in every mode, for startup scripts, and for `docker exec` shells.
- `init.d/*.sh`: scripts here run once per container, after the image's own startup scripts, as `aicode` with passwordless sudo. A failing script is logged and the rest still run. A new container runs them again, so make them safe to repeat.

The image's own startup script, [`10-pi-extensions.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/init.d/10-pi-extensions.sh), adds the bundled MCP bridge extension to `~/.pi/agent/settings.json` and creates that file with `quietStartup: true` if it is missing.

## MCP servers inside Pi

The bundled [MCP bridge extension](https://github.com/psyb0t/docker-pibox/blob/main/pibox/extensions/mcp-bridge/index.ts) gives Pi the tools of any stdio MCP server listed in a `.mcp.json` file in the directory Pi starts in. It uses the same shape as Claude Code:

```json
{
  "mcpServers": {
    "fetch": {
      "command": "uvx",
      "args": [
        "mcp-server-fetch"
      ],
      "env": {
        "EXAMPLE": "value"
      }
    }
  }
}
```

Each tool is registered as `mcp__<server>__<tool>`, with characters outside `A-Za-z0-9_-` replaced by `_`. A server that fails to start or to list its tools is logged and skipped. This is the opposite direction from [MCP mode](modes/mcp.md), which lets other agents call pibox.
