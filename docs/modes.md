---
title: "Modes"
description: "How pibox's API, Telegram, cron and MCP modes start, which ones run together, and where MCP is served in each combination."
nav_order: 5
has_children: true
---

# Modes

With no mode flag, the container runs Pi itself: an interactive session, or a one-shot run when you pass `-p`. A mode flag turns the container into a long-lived service instead.

## Foreground modes

API, Telegram and cron are foreground modes. The container lives as long as the foreground process does.

| Flags set | What runs |
| --- | --- |
| `PIBOX_API_MODE=1`, alone or with anything else | The HTTP API. The other foreground flags are ignored |
| `PIBOX_TELEGRAM_MODE=1` and `PIBOX_CRON_MODE=1` | The Telegram bot, with the cron scheduler running inside it |
| `PIBOX_TELEGRAM_MODE=1` | The Telegram bot |
| `PIBOX_CRON_MODE=1` | The cron scheduler |
| none | Pi, interactive or one-shot |

Telegram with cron is the one pair that runs together. That pairing is what lets a cron job post its result to a chat and lets you reply to it.

## MCP

`PIBOX_MCP_MODE=1` is not a foreground mode. It runs next to whatever else the container does.

| Foreground | Where MCP is served |
| --- | --- |
| API mode | `/mcp/` on the API port, with no extra process. The slashless `/mcp` reaches the same handler |
| Telegram, cron, or none | A sidecar server on `PIBOX_MCP_MODE_PORT` (default `8081`), at the port root `/` |

## Mode pages

| Page | Flag | Summary |
| --- | --- | --- |
| [API mode](modes/api.md) | `PIBOX_API_MODE=1` | A FastAPI server on `:8080`: synchronous and background runs, workspace file transfer, and an OpenAI-compatible chat endpoint with streaming and client-executed tool calls |
| [Telegram mode](modes/telegram.md) | `PIBOX_TELEGRAM_MODE=1` | Talk to Pi from Telegram, with per-chat workspaces, allowlists, file transfer and per-chat settings that survive restarts |
| [Cron mode](modes/cron.md) | `PIBOX_CRON_MODE=1` | Scheduled Pi runs from a YAML file, with per-run history and optional Telegram notifications |
| [MCP mode](modes/mcp.md) | `PIBOX_MCP_MODE=1` | `run_prompt` and workspace file tools over streamable HTTP, so other agents can use Pi as a tool |

Each mode page lists its own variables. Every `PIBOX_*` name there is an alias for the `AICODEBOX_*` name the base image reads, as described in [Configuration](configuration.md#naming).
