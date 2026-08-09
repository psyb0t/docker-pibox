# Telegram Mode

`PIBOX_TELEGRAM_MODE=1` + `PIBOX_TELEGRAM_MODE_TOKEN=<token>`. Talk to pi from Telegram, with per-chat workspaces and settings that survive restarts.

## Setup

1. Create a bot with [@BotFather](https://t.me/BotFather) and copy the token.
2. Find the chat IDs you want to allow (a group's ID is negative, e.g. `-100123`).
3. Write a config yaml and point the container at it.

```yaml
# ~/.aicodebox/telegram.yml
allowed_chats: [-100123, 42]
default:
  model: glm-4.6
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
      - ANTHROPIC_AUTH_TOKEN=your-token
      - ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
      - ANTHROPIC_MODEL=glm-4.6
    volumes:
      - ~/.aicodebox:/home/aicode/.aicodebox
      - ~/workspaces:/workspace
```

Config lives at `$HOME/.aicodebox/telegram.yml` by default — override with `PIBOX_TELEGRAM_MODE_CONFIG`.

## What it does

- Text in → pi runs → Markdown→HTML rendered response back.
- File uploads land in the chat's workspace. `[SEND_FILE: path]` in pi's output delivers workspace files as Telegram attachments.
- Per-chat overrides: `/model`, `/effort` (maps to pi's `--thinking` levels), `/system_prompt`, `/append_system_prompt`. Persisted across restarts.
- `/cancel` kills the in-flight run. `/reload` re-reads config. `/config` dumps merged settings. `/fetch <path>` downloads a file.
- Replies to cron messages inject the job's instruction + result so pi has full context for follow-ups.

## Telegram mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_TELEGRAM_MODE` | `0` | Boot the Telegram bot (foreground) |
| `PIBOX_TELEGRAM_MODE_TOKEN` | — | Bot token from @BotFather |
| `PIBOX_TELEGRAM_MODE_CONFIG` | `~/.aicodebox/telegram.yml` | Path to the telegram config yaml |
| `PIBOX_TELEGRAM_MODE_OVERRIDES` | `~/.aicodebox/telegram_overrides.json` | Per-chat override store (model/effort/system prompts) |

The `/model` and `/effort` pickers are populated from `PIBOX_AVAILABLE_MODELS` and `PIBOX_AVAILABLE_EFFORTS`. Unlike API mode, telegram still boots without `PIBOX_AVAILABLE_MODELS` — the `/model` picker degrades to a "set this env var" reply.

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Combined with cron mode

Telegram and cron are the one foreground pair that runs together — set both flags and cron runs in-thread inside telegram, which is what lets a job post its result into a chat and lets you reply to it. See [cron.md](cron.md).
