---
title: "Cron mode"
description: "pibox cron mode: schedule Pi runs from a YAML file with six-field schedules, per-run history directories and Telegram notifications."
parent: "Modes"
nav_order: 3
---

# Cron mode

`PIBOX_CRON_MODE=1` + `PIBOX_CRON_MODE_FILE=/path/to/cron.yaml`. YAML-defined scheduled jobs on six-field [croniter](https://github.com/pallets-eco/croniter) schedules. Each job fires Pi with its instruction.

## Setup

```yaml
# cron.yaml
jobs:
  - name: morning-standup
    schedule: "0 0 9 * * 1-5"
    instruction: |
      Summarize what changed in /workspace since yesterday.
      Be brief. One paragraph max.
    workspace: myproject
    telegram_chat_id: -100123
    model: your-model-id
    thinking: low
```

```yaml
# docker-compose.yml
services:
  pibox:
    image: psyb0t/pibox:latest
    environment:
      - PIBOX_CRON_MODE=1
      - PIBOX_CRON_MODE_FILE=/home/aicode/.aicodebox/cron.yaml
      - PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic
      - PIBOX_PROVIDER_API=anthropic-messages
      - PIBOX_PROVIDER_API_KEY=your-z-ai-api-key
      - PIBOX_PROVIDER_MODEL=your-model-id
    volumes:
      - ~/.aicodebox:/home/aicode/.aicodebox
      - ~/workspaces:/workspace
```

The schedule field has six fields with seconds first, so `"0 0 9 * * 1-5"` is 09:00:00 on weekdays.

## File format

The file is a mapping with a `jobs` list. Keys at the top level, next to `jobs`, set defaults for every job.

| Key | Where | Meaning |
| --- | --- | --- |
| `jobs` | top level | Required, a non-empty list |
| `name` | job | Required, unique, letters, digits, `_` and `-` only |
| `schedule` | job | Required, a six-field cron expression |
| `instruction` | job | Required, the prompt Pi runs |
| `workspace` | job | Workspace subpath to run in. Default `.`, the workspace root |
| `no_continue` | job | `true` starts a fresh session each run. Default `false`, which continues the last session in that workspace |
| `model` | job or top level | Model for the run |
| `thinking` | job or top level | Pi thinking level |
| `effort` | job or top level | Used as the thinking level when `thinking` is not set |
| `system_prompt` | job or top level | Replaces the system prompt |
| `append_system_prompt` | job or top level | Appended to the system prompt |
| `telegram_chat_id` | job or top level | Chat that receives the result. `0` on a job opts out of the top-level default |

An invalid file stops the scheduler with a message naming the job and the key.

## Run history

`PIBOX_CRON_MODE_HISTORY_DIR` (default `$HOME/.aicodebox/cron`) is the whole cron state root. Each run gets a history directory under `<root>/history/<workspace>/<timestamp>-<job>/` with `meta.json`, `stdout.log`, `stderr.log` and `result.txt`. If Telegram is configured, `telegram.json` lands there too, and the next run's prompt gets a "prior run" hint so Pi can read its own history without you wiring it up. A per-job summary is appended to `<root>/<job>.jsonl`.

Setting the variable moves the whole root, including run history, job summaries, and the Telegram reply bridge's `telegram_messages.json`. Do not point it at the `history` child directory.

## Notifications

A job with `telegram_chat_id` set sends its result to that chat when it finishes. That needs Telegram mode running in the same container, see below. A successful job with an explicit recipient notifies even when its result text is empty, and a failed job sends a failure notice.

## Cron mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_CRON_MODE` | `0` | Boot the cron scheduler (foreground, or inside the bot when Telegram is also on) |
| `PIBOX_CRON_MODE_FILE` | none | Path to the cron file |
| `PIBOX_CRON_MODE_HISTORY_DIR` | `~/.aicodebox/cron` | Cron state root. Run history, job summaries and the Telegram reply bridge's message inbox all live under it |

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Combined with Telegram mode

Setting `PIBOX_TELEGRAM_MODE=1` alongside cron runs the scheduler inside the bot, which is what makes `telegram_chat_id` on a job deliver its result to a chat. See [Telegram mode](telegram.md).

## Combined with MCP mode

Cron is a foreground mode, so [MCP](mcp.md) runs as a sidecar next to it: scheduled jobs on their own schedule, and the same box reachable as a tool the whole time.
