---
title: "Telegram mode"
description: "pibox Telegram mode: talk to Pi from a bot with per-chat workspaces, chat and user allowlists, file transfer and per-chat model settings."
parent: "Modes"
nav_order: 2
---

# Telegram mode

`PIBOX_TELEGRAM_MODE=1` + `PIBOX_TELEGRAM_MODE_TOKEN=<token>`. Talk to Pi from Telegram, with per-chat workspaces and settings that survive restarts.

## Setup

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy the token.
2. Find the chat IDs you want to allow (a group's ID is negative, for example `-100123`).
3. Write a config file and point the container at it.

```yaml
# ~/.aicodebox/telegram.yml
allowed_chats: [-100123, 42]
default:
  model: your-model-id
  workspace: shared
chats:
  -100123:
    workspace: alpha
    allowed_users: [10, 20]
```

```yaml
# docker-compose.yml
services:
  pibox:
    image: psyb0t/pibox:latest
    environment:
      - PIBOX_TELEGRAM_MODE=1
      - PIBOX_TELEGRAM_MODE_TOKEN=123456:ABC
      - PIBOX_AVAILABLE_MODELS=your-model-id
      - PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic
      - PIBOX_PROVIDER_API=anthropic-messages
      - PIBOX_PROVIDER_API_KEY=your-z-ai-api-key
      - PIBOX_PROVIDER_MODEL=your-model-id
    volumes:
      - ~/.aicodebox:/home/aicode/.aicodebox
      - ~/workspaces:/workspace
```

The config lives at `$HOME/.aicodebox/telegram.yml` by default. Override it with `PIBOX_TELEGRAM_MODE_CONFIG`.

| Key | Meaning |
| --- | --- |
| `allowed_chats` | Chat IDs the bot answers. Messages from any other chat are ignored. **An empty or missing list allows every chat** |
| `default` | Settings for every chat, such as `model` and `workspace` |
| `chats.<id>` | Settings for one chat, merged over `default`. `allowed_users` limits who may talk to the bot in that chat |

Settings merge in this order, later wins: `default`, then `chats.<id>`, then the chat's runtime overrides. A chat without a `workspace` setting gets its own directory, `chat_<id>` with the ID's minus sign dropped, under the workspace root.

Without a config file, the bot falls back to `TELEGRAM_CHAT_ID` as its only allowed chat. Through the wrapper, send that as `PIBOX_ENV_TELEGRAM_CHAT_ID`. With neither, the bot answers anyone who finds it, and anyone who can message it can run Pi in your container. Always set `allowed_chats`.

## What it does

- Text in, Pi runs, and the Markdown reply comes back rendered as Telegram HTML.
- File uploads land in the chat's workspace. `[SEND_FILE: path]` in Pi's output delivers workspace files as Telegram attachments.
- Per-chat overrides: `/model`, `/effort` (Pi's `--thinking` levels), `/system_prompt` and `/append_system_prompt`. They persist across restarts.
- `/cancel` kills the in-flight run. `/reload` re-reads the config. `/config` shows the merged settings. `/status` shows what is running. `/fetch <path>` downloads a file. `/start` and `/help` cover the basics.
- A reply to a cron message adds the job's instruction and result to the prompt, so Pi has the context for a follow-up.

## Telegram mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_TELEGRAM_MODE` | `0` | Boot the Telegram bot (foreground) |
| `PIBOX_TELEGRAM_MODE_TOKEN` | none | Bot token from @BotFather |
| `PIBOX_TELEGRAM_MODE_CONFIG` | `~/.aicodebox/telegram.yml` | Path to the Telegram config file |
| `PIBOX_TELEGRAM_MODE_OVERRIDES` | `~/.aicodebox/telegram_overrides.json` | Per-chat override store (model, effort, system prompts) |

The `/model` and `/effort` pickers are populated from `PIBOX_AVAILABLE_MODELS` and `PIBOX_AVAILABLE_EFFORTS`. Unlike API mode, Telegram still boots without `PIBOX_AVAILABLE_MODELS`. The `/model` picker then replies with a hint to set it.

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Combined with cron mode

Telegram and cron are the one foreground pair that runs together. Set both flags and cron runs inside the bot, which lets a job post its result into a chat and lets you reply to it. See [Cron mode](cron.md).
