---
title: "Configuration"
description: "Every pibox environment variable: mode flags, workspace and runtime settings, PIBOX_ to AICODEBOX_ aliasing, Git identity, bin/ and init.d/ hooks, subagents."
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

The bundled [MCP bridge extension](https://github.com/psyb0t/docker-pibox/blob/main/pibox/extensions/mcp-bridge/index.ts) gives Pi what each MCP server listed in a `.mcp.json` file in the directory Pi starts in offers the model: its tools, its instructions and its resources. It uses the same shape as Claude Code, with stdio servers (`command`) and streamable HTTP servers (`url`):

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
    },
    "docs": {
      "type": "http",
      "url": "https://mcp.example.invalid/mcp",
      "headers": {
        "Authorization": "Bearer ${DOCS_TOKEN}"
      }
    }
  }
}
```

Each tool is registered as `mcp__<server>__<tool>`, with characters outside `A-Za-z0-9_-` replaced by `_`. A server that fails to start or to list its tools is logged and skipped.

- **Instructions:** the `instructions` a server sends when it connects go into Pi's system prompt, under the server's name, before every run. Servers put their how-to there: which tool to use first, which to avoid, how a multi-step task goes. Each server's text is cut at 8,000 characters.
- **Resources:** a server that offers resources also gets `mcp__<server>__list_resources` and `mcp__<server>__read_resource`, so Pi can read the guides and documents it points at.
- **HTTP servers:** an entry with `url` connects over streamable HTTP. `${NAME}` in a header value is replaced with that environment variable from the container, so the token stays out of the file. Give the exact endpoint path the server serves. This is the opposite direction from [MCP mode](modes/mcp.md), which lets other agents call pibox.

## Subagents

The image ships Pi's [subagent example extension](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent/examples/extensions/subagent), off by default. It gives Pi a `subagent` tool that runs agent definitions in separate Pi processes, one at a time, in parallel or as a chain. pibox installs it at build time with [`install-subagent-extension.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/scripts/install-subagent-extension.sh), which makes its limits and the thinking level of model-pinned agents configurable.

| Variable | Default | What it does |
| --- | --- | --- |
| `PIBOX_SUBAGENTS` | `false` | `true` or `1` adds the extension to `~/.pi/agent/settings.json`. `false`, `0` or unset removes it |
| `PIBOX_SUBAGENT_MAX_TASKS` | `8` | Most tasks one parallel call may hold |
| `PIBOX_SUBAGENT_MAX_CONCURRENCY` | `4` | Most parallel tasks running at once |
| `PIBOX_SUBAGENT_THINKING` | none | Thinking level for agents whose definition sets its own `model:`: `off`, `minimal`, `low`, `medium`, `high`, `xhigh` or `max`. Agents without `model:` inherit the calling session's model and thinking level, as upstream |
| `PIBOX_AGENTS_DIR` | none | Absolute path inside the container to a directory of agent definitions (`*.md`). Each one is linked into `~/.pi/agent/agents` |

[`setup-subagents.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/scripts/setup-subagents.sh) applies these at every start and writes the limits to `~/.pi/agent/pibox-subagent.json`. Invalid values stop the container before any mode starts.

An agent definition is Markdown with YAML front matter:

```markdown
---
name: reviewer
description: Reviews a diff and lists defects
tools: read, grep, find, ls
model: pibox/your-model-id
---

Review the change you are given and list concrete defects.
```

Use `PIBOX_AGENTS_DIR` rather than mounting a directory onto `~/.pi/agent/agents`. Docker creates the missing parents of a bind mount as root, so `~/.pi/agent` would become root-owned and provider setup would fail. Through the wrapper, mount the directory with a `PIBOX_MOUNT_*` variable and point `PIBOX_AGENTS_DIR` at the same path:

```bash
PIBOX_SUBAGENTS=true \
PIBOX_MOUNT_AGENTS="$HOME/pi-agents" \
PIBOX_AGENTS_DIR="$HOME/pi-agents" \
pibox -p "use the reviewer agent on the last commit"
```

pibox records the links it made in `~/.pi/agent/pibox-agents.json` and replaces them at the next start. An existing file with the same name in `~/.pi/agent/agents` is kept, with a warning. The example's sample agents name Anthropic models, so pibox does not install them.
