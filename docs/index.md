---
title: "Home"
description: "docker-pibox runs pi-coding-agent in a Docker image with a host wrapper, an HTTP API, an OpenAI-compatible endpoint, MCP, Telegram and cron."
nav_order: 1
permalink: /
seo:
  type: WebSite
---

# docker-pibox

docker-pibox puts [pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) inside an [aicodebox](https://github.com/psyb0t/docker-aicodebox) container. One image, several ways in: an interactive shell, a one-shot prompt, an HTTP API with an OpenAI-compatible endpoint, an MCP server, a Telegram bot, and a cron scheduler that fires Pi on whatever schedule you want.

You talk to pibox. pibox talks to Pi. Pi talks to whatever LLM you point it at.

## Quick start

Install the host wrapper, then run it from the directory you want Pi to work in:

```bash
curl -fsSL https://raw.githubusercontent.com/psyb0t/docker-pibox/main/install.sh | bash
```

```bash
PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic \
PIBOX_PROVIDER_API=anthropic-messages \
PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
PIBOX_PROVIDER_MODEL=your-model-id \
pibox -p "list the files in this workspace"
```

The wrapper forwards every `PIBOX_*` variable into the container, so the provider settings above reach Pi without extra flags. [Install and the wrapper](install.md) covers the installer, the image variants and long-running containers.

## What is on this site

| Page | What it covers |
| --- | --- |
| [Install and the wrapper](install.md) | Installer options, wrapper usage, image variants, nested launches, upgrades and removal |
| [Configuration](configuration.md) | Every pibox environment variable, the `PIBOX_*` to `AICODEBOX_*` aliasing, Git identity and startup hooks |
| [LLM providers](providers.md) | Pointing Pi at OpenAI-compatible, Anthropic Messages or Google endpoints |
| [Modes](modes.md) | How the API, Telegram, cron and MCP modes combine, with a page for each |
| [GitHub Action](github-action.md) | Running Pi in a workflow on read-only context |
| [Agent integrations](agent-integrations.md) | The skill and plugins for Claude Code, Codex and OpenClaw |
| [Security](security.md) | What the container can reach, which surfaces need tokens, and where secrets end up |
| [Troubleshooting](troubleshooting.md) | Startup refusals, provider errors and their fixes |
| [Architecture](architecture.md) | How a request travels from the wrapper to the Pi CLI |
| [Development](development.md) | Building the images, running the tests, CI and releases |

## The base image

pibox is a thin layer. The modes, the HTTP server, the Telegram bot, the cron scheduler and the container entrypoint come from the shared [aicodebox](https://github.com/psyb0t/docker-aicodebox) base, which also has its own [documentation site](https://psyb0t.github.io/docker-aicodebox/). pibox adds Pi, the adapter that turns aicodebox run requests into Pi command lines, the `PIBOX_*` names, the provider bootstrap and the host wrapper. This site documents the pibox names and behavior in full, so you do not need the base documentation to run pibox.
