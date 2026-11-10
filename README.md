# pibox

[![CI](https://github.com/psyb0t/docker-pibox/actions/workflows/pipeline.yml/badge.svg?branch=main)](https://github.com/psyb0t/docker-pibox/actions/workflows/pipeline.yml)
[![version](https://raw.githubusercontent.com/psyb0t/docker-pibox/badges/version.svg)](https://github.com/psyb0t/docker-pibox/releases)
[![license](https://raw.githubusercontent.com/psyb0t/docker-pibox/badges/license.svg)](https://github.com/psyb0t/docker-pibox/blob/main/LICENSE)
[![Docker Pulls](https://img.shields.io/docker/pulls/psyb0t/pibox?style=flat-square)](https://hub.docker.com/r/psyb0t/pibox)

[pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) inside an [aicodebox](https://github.com/psyb0t/docker-aicodebox) container. One image, several ways in: interactive shell, one-shot prompt, HTTP API (with an OpenAI-compatible endpoint), MCP server, Telegram bot, and a cron scheduler that fires pi on whatever schedule you want.

You talk to pibox. pibox talks to pi. pi talks to whatever LLM you point it at. Nobody cares about the middle.

## Table of Contents

- [Quick start](#quick-start)
- [Image variants](#image-variants)
- [Modes](#modes)
- [Documentation](#documentation)
- [Agent integrations](#agent-integrations)
- [Development](#development)
- [Sponsor](#sponsor)
- [License](#license)

## Quick start

Install the host wrapper.

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-pibox/main/install.sh | bash

# Install the full image as the wrapper default.
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-pibox/main/install.sh | PIBOX_FULL=1 bash
```

The installer creates the Pi, pibox state, and SSH directories, pulls the selected image, and installs `pibox` on `PATH`. Run `pibox` from the directory you want Pi to work in. The wrapper mounts that directory at the same path inside the container, keeps Pi's state between runs, forwards every `PIBOX_*` variable, and passes Pi arguments through unchanged.

```bash
# point Pi at an upstream model
export PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic
export PIBOX_PROVIDER_API=anthropic-messages
export PIBOX_PROVIDER_API_KEY=your-z-ai-api-key
export PIBOX_PROVIDER_MODEL=your-model-id

# interactive Pi in the current directory
pibox

# one prompt, then exit
pibox -p "list the files in this workspace"

# the full image for this run only
PIBOX_FULL=1 pibox -p "run the test suite"
```

`PIBOX_DETACH=1` starts a long-running mode in the background:

```bash
PIBOX_DETACH=1 \
PIBOX_API_MODE=1 \
PIBOX_API_MODE_TOKEN=your-secret \
PIBOX_AVAILABLE_MODELS=your-model-id \
pibox
```

Install `pibox`, `codexbox`, and `claudebox` in the same command directory when you want one box to launch another. The [install guide](https://psyb0t.github.io/docker-pibox/install/) covers nested launches, plain `docker run`, upgrades and removal.

## Image variants

- `psyb0t/pibox:latest` is the minimal image.
- `psyb0t/pibox:latest-full` starts from the shared `aicodebox:v0.18.4-full` base, then adds Pi and pibox. It carries the shared development toolchain without rebuilding it in this repository.

## Modes

| Flag | What you get |
| --- | --- |
| `PIBOX_API_MODE=1` | FastAPI server on `:8080`: agent runs, workspace files, and an OpenAI-compatible `chat/completions` with streaming and client-executed tool calls |
| `PIBOX_TELEGRAM_MODE=1` | Talk to pi from Telegram, with per-chat workspaces, allowlists and settings |
| `PIBOX_CRON_MODE=1` | YAML-scheduled pi runs with per-run history |
| `PIBOX_MCP_MODE=1` | `run_prompt` and workspace file tools over MCP, next to any other mode |

API wins over the other foreground modes. Telegram and cron run together. MCP coexists with all of them. The [modes page](https://psyb0t.github.io/docker-pibox/modes/) has the rules and a page per mode.

## Documentation

The full documentation lives at **[psyb0t.github.io/docker-pibox](https://psyb0t.github.io/docker-pibox/)**.

| Section | What it covers |
| --- | --- |
| [Install and the wrapper](https://psyb0t.github.io/docker-pibox/install/) | Installer options, wrapper settings, image variants, nested launches |
| [Configuration](https://psyb0t.github.io/docker-pibox/configuration/) | Every environment variable, aliasing, Git identity, startup hooks |
| [LLM providers](https://psyb0t.github.io/docker-pibox/providers/) | OpenAI-compatible, Anthropic Messages and Google endpoints |
| [Modes](https://psyb0t.github.io/docker-pibox/modes/) | API, Telegram, cron and MCP |
| [GitHub Action](https://psyb0t.github.io/docker-pibox/github-action/) | Pi in a workflow on read-only context |
| [Agent integrations](https://psyb0t.github.io/docker-pibox/agent-integrations/) | Claude Code, Codex and OpenClaw |
| [Security](https://psyb0t.github.io/docker-pibox/security/) | Tokens, exposure and where secrets are stored |
| [Troubleshooting](https://psyb0t.github.io/docker-pibox/troubleshooting/) | Startup refusals and their fixes |
| [Architecture](https://psyb0t.github.io/docker-pibox/architecture/) | Wrapper, entrypoint, adapter and the Pi CLI |
| [Development](https://psyb0t.github.io/docker-pibox/development/) | Builds, tests, CI and releases |

## Agent integrations

The [skill](https://github.com/psyb0t/docker-pibox/tree/main/.agents/skills/pibox) works in any agent that reads `.agents/skills/` (such as [peen](https://github.com/psyb0t/peen)), and installs natively in Claude Code, Codex and OpenClaw:

```bash
claude plugin marketplace add psyb0t/agents
claude plugin install pibox@psyb0t

codex plugin marketplace add psyb0t/agents
codex plugin add pibox@psyb0t

openclaw skills install @psyb0t/pibox
```

The [agent integrations page](https://psyb0t.github.io/docker-pibox/agent-integrations/) covers tokens and the stdio MCP bridge plugin.

## Development

```bash
make help        # list targets
make build-all   # build both variants
make lint        # shellcheck, ruff and pyright, in containers
make test-ci     # offline tests, what CI runs
make test        # the e2e suite (needs .env.test)
make docs        # build the documentation site
```

The [development page](https://psyb0t.github.io/docker-pibox/development/) explains the tests, CI and releases.

## Sponsor

<a href="https://www.buymeacoffee.com/psyb0t"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-blue.png" alt="Buy Me a Coffee" height="60" width="217"></a>

## License

WTFPL, see [LICENSE](https://github.com/psyb0t/docker-pibox/blob/main/LICENSE). Do what the fuck you want.
