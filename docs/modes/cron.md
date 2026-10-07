# Cron Mode

`PIBOX_CRON_MODE=1` + `PIBOX_CRON_MODE_FILE=/path/to/cron.yaml`. YAML-defined scheduled jobs — 6-field schedules via croniter. Each job fires pi with the given instruction.

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
    model: glm-4.6
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
      - ANTHROPIC_AUTH_TOKEN=your-token
      - ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
      - ANTHROPIC_MODEL=glm-4.6
    volumes:
      - ~/.aicodebox:/home/aicode/.aicodebox
      - ~/workspaces:/workspace
```

The schedule field is 6-field (seconds first), so `"0 0 9 * * 1-5"` is 09:00:00 on weekdays.

## Run history

`PIBOX_CRON_MODE_HISTORY_DIR` (default `$HOME/.aicodebox/cron`) is the whole cron state root. Each run gets a history dir under `<root>/history/<workspace>/<timestamp>-<job>/` with `meta.json`, `stdout.log`, `stderr.log`, `result.txt`. If telegram is configured, `telegram.json` lands there too and the next run's prompt gets a "prior run" hint so pi can reference its own history without you wiring it up. A per-job summary jsonl is appended at `<root>/<job>.jsonl`.

Setting the env var moves the whole root, including run history, job summaries, and the telegram reply bridge's `telegram_messages.json`. Do not point it at the `history` child directory.

## Notifications

A job with `telegram_chat_id` set sends its result to that chat when it finishes. It requires telegram mode to also be configured (see below). Setting a job's `telegram_chat_id` to `0` opts it out of an inherited default. A successful job with an explicit recipient notifies even when its result text is empty; a failed job sends a failure notice.

## Cron mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_CRON_MODE` | `0` | Boot the cron scheduler (foreground; in-thread when telegram is also on) |
| `PIBOX_CRON_MODE_FILE` | — | Path to the cron yaml |
| `PIBOX_CRON_MODE_HISTORY_DIR` | `~/.aicodebox/cron` | Cron state root; run history, job summaries, and the telegram reply bridge's message inbox all live under it |

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Combined with telegram mode

Setting `PIBOX_TELEGRAM_MODE=1` alongside cron is supported — cron then runs in-thread inside telegram, which is what makes `telegram_chat_id` on a job deliver its result to a chat. See [telegram.md](telegram.md).

## Combined with MCP mode

Cron is a foreground mode, so [mcp.md](mcp.md) runs as a sidecar next to it — scheduled jobs on their own schedule, the same box reachable as a tool the whole time.
