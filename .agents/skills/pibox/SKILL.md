---
name: pibox
description: pi-coding-agent (earendil-works) running on the network inside an aicodebox container. Exposes seven programmatic surfaces on one image — interactive shell, one-shot exec (`-p "..."`), an HTTP REST API (run/async/cancel, workspace file ops), an OpenAI-compatible `/openai/v1/chat/completions` endpoint (streaming, client-executed tool calling, response_format/JSON-schema), an MCP server at `/mcp` (mounted in API mode or as a sidecar), a Telegram bot, and a cron scheduler that fires pi on a schedule. Foreground modes (API/Telegram/Cron) are mutually exclusive except Telegram+Cron; MCP coexists with any of them. Bearer-token auth per surface (`PIBOX_API_MODE_TOKEN`, `PIBOX_MCP_MODE_TOKEN`), empty = no auth. Use when the user wants to drive pi-coding-agent programmatically over HTTP/MCP/Telegram/cron instead of a local terminal session, or needs to reason about which pibox mode/endpoint fits a given integration.
homepage: https://github.com/psyb0t/docker-pibox
user-invocable: true
metadata:
  { "openclaw": { "emoji": "🥧", "primaryEnv": "PIBOX_URL", "requires": { "bins": ["docker", "curl"] } } }
---

# pibox

[pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) inside an [aicodebox](https://github.com/psyb0t/docker-aicodebox) container. One image, seven ways in: interactive shell, one-shot exec, HTTP REST API, OpenAI-compatible endpoint, MCP server, Telegram bot, cron scheduler.

You talk to pibox, pibox talks to pi, pi talks to whatever Anthropic-compatible LLM you point it at (`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN`).

For installation and configuration, see [references/setup.md](references/setup.md).

## Security & safety

- **No auth when `PIBOX_API_MODE_TOKEN` is unset.** With it empty the REST/OpenAI-compatible API surface is UNAUTHENTICATED — anyone who can reach it gets full agent-execution and workspace file-read/write/delete access. NEVER expose such an instance on a network or to untrusted agents; set the token and bind to loopback / behind an authenticating proxy.
- **No auth when `PIBOX_MCP_MODE_TOKEN` is unset.** Same story for the MCP surface (`/mcp` or the sidecar) — empty token means unauthenticated `run_prompt`/file-tool access, and it does not fall back to `PIBOX_API_MODE_TOKEN`. Set it explicitly.
- **Destructive & irreversible.** `DELETE /run/{id}`, `DELETE /files/{path}`, and the MCP `delete_file` tool remove state with no undo (canceled runs can't be resumed; deleted files are gone). An agent must NEVER call these unless the user explicitly asked for that exact action; confirm the specific target first, scope it to the current task, and never enumerate-then-bulk-delete. On a shared/multi-tenant instance a deletion can destroy another caller's in-flight run or workspace file — treat these routes as admin-only.

## When To Use

- Drive pi-coding-agent from a script/service instead of an interactive terminal (`/run`, `/openai/v1/chat/completions`, or MCP tools).
- Wire pi into an OpenAI-SDK-compatible client (LangChain, openai-python) via the `/openai/v1/*` surface.
- Give an MCP-aware agent (Claude, Cursor, OpenClaw) remote tool access to a pi-driven workspace.
- Chat with pi from Telegram, with per-chat model/effort overrides and file transfer.
- Schedule recurring pi runs (standups, digests, periodic maintenance) via cron mode.
- One-off container run for a single prompt (CI step, quick script) via one-shot exec.

## When NOT To Use

- Don't run two foreground modes together except Telegram+Cron (cron runs in-thread inside telegram) — API set alongside anything else wins and the others don't start.
- Don't expect `/openai/v1/chat/completions` to stream token-by-token when `tools` or a JSON schema is in play — those modes compute the full answer first and replay it as a single-shot SSE stream (still a valid stream, just not incremental). Plain chat streams incrementally.
- Don't rely on `PIBOX_MCP_MODE_TOKEN` falling back to `PIBOX_API_MODE_TOKEN` — MCP has its own bearer, no fallback.
- Don't point multiple concurrent runs at the same workspace — the API/OAI layer returns 409 "workspace busy" while a run is in flight in that workspace.

## Interactive shell mode

No mode env var set, no args passed to `docker run`. Falls through to pi's own CLI, invoked directly — a normal interactive pi session inside the container.

```bash
docker run -it --rm \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

Auth: none at the container boundary — you're inside it. pi itself uses the `ANTHROPIC_*` env vars.

## One-shot exec mode

No mode env var set, args passed after the image name are forwarded verbatim to the `pi` binary (passthrough). `-p "<prompt>"` runs pi non-interactively and prints the result to stdout, then exits.

```bash
docker run --rm \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"
```

Any pi CLI flag works here (`--model`, `--thinking`, `--session`, etc.) — the entrypoint just execs `pi "$@"`. Auth: none at the container boundary; pi uses `ANTHROPIC_*`.

## REST API mode

`PIBOX_API_MODE=1`. FastAPI server on `:8080` (override `PIBOX_API_MODE_PORT`). **Requires `PIBOX_AVAILABLE_MODELS=<csv>`** — the server refuses to boot without it (no sensible default; pi can drive any provider's models).

```bash
docker run -d --network host \
  -e PIBOX_API_MODE=1 \
  -e PIBOX_API_MODE_TOKEN=your-secret \
  -e PIBOX_AVAILABLE_MODELS=glm-4.6,glm-4.5-air \
  -e ANTHROPIC_AUTH_TOKEN=your-token \
  -e ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
  -e ANTHROPIC_MODEL=glm-4.6 \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/healthz` | liveness — `{ok, adapter}`, unauthenticated |
| `GET` | `/status` | in-flight runs + busy workspaces |
| `POST` | `/run` | run the agent — sync by default; body `async` or `fireAndForget` makes it fire-and-poll |
| `GET` | `/run/result?runId=<id>` | poll a run started with `async`/`fireAndForget` |
| `DELETE` | `/run/{id}` | cancel an in-flight run (kills the subprocess) |
| `GET` | `/files` | list the workspace root — `{entries: [{name, type, size?}, ...]}` |
| `GET` | `/files/{path}` | list a sub-directory, or stream a file's bytes |
| `PUT` | `/files/{path}` | upload — raw request body becomes the file contents; parent dirs auto-created |
| `DELETE` | `/files/{path}` | delete a file (refuses directories — 400) |
| `POST` | `/openai/v1/chat/completions` | OpenAI-compatible chat (see below) |
| `GET` | `/openai/v1/models` | model list, from `PIBOX_AVAILABLE_MODELS` |
| `POST` | `/mcp` | MCP server (streamable HTTP) — mounted only when `PIBOX_MCP_MODE=1` |

All `/files/*` paths resolve against the workspace root with traversal checking — `..` segments that escape the root return 400. Every route except `/healthz` is gated by `Authorization: Bearer <PIBOX_API_MODE_TOKEN>` when that var is set; empty/unset token = no auth.

**No auth when `PIBOX_API_MODE_TOKEN` is unset.** With it empty the API is UNAUTHENTICATED — anyone who can reach it gets run-the-agent and workspace file-read/write/delete access. NEVER expose such an instance on a network or to untrusted agents; set the token and bind to loopback / behind an authenticating proxy.

**Destructive & irreversible.** `DELETE /run/{id}` kills the in-flight subprocess with no undo, and `DELETE /files/{path}` deletes a workspace file with no undo. An agent must NEVER call either unless the user explicitly asked for that exact action; confirm the specific target first; scope it to the current task; never enumerate-then-bulk-delete. On a shared/multi-tenant instance this can disrupt or destroy another caller's run or data — treat these routes as admin-only.

```bash
# sync run
curl -s http://localhost:8080/run \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "say HELLO", "workspace": "/workspace"}'

# async run, then poll
RUN_ID=$(curl -s http://localhost:8080/run \
  -H "Authorization: Bearer your-secret" -H "Content-Type: application/json" \
  -d '{"prompt": "long task", "async": true}' | jq -r .runId)
curl -s "http://localhost:8080/run/result?runId=$RUN_ID" \
  -H "Authorization: Bearer your-secret"

# cancel it
curl -s -X DELETE "http://localhost:8080/run/$RUN_ID" \
  -H "Authorization: Bearer your-secret"

# upload / download / list / delete a workspace file
curl -sS -X PUT -H "Authorization: Bearer your-secret" \
  --data-binary @local.txt http://localhost:8080/files/notes/hello.txt
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes | jq
curl -sS -X DELETE -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt
```

**`POST /run`** body fields: `prompt` (required), `workspace`, `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `noContinue`, `resume`, `timeoutSeconds`, `thinking`, `noTools`, `toolsAllowlist`, `extraArgs`, `async`, `fireAndForget`, `includeRaw`. With `jsonSchema` set the response is verbose: `text`, `json` (schema-validated), `events`, `sessionId`, `usage`, `attempts` (per-retry breakdown, up to 3 self-correction retries on parse/validation failure). Without `jsonSchema` the response is lean: `{runId, workspace, exitCode, text}`.

## OpenAI-compatible endpoint mode

Same `PIBOX_API_MODE=1` server, `POST /openai/v1/chat/completions` and `GET /openai/v1/models`. Drop-in for any OpenAI-SDK client — point the base URL at `http://host:8080/openai/v1` and set the model to one of `PIBOX_AVAILABLE_MODELS`.

```bash
curl -s http://localhost:8080/openai/v1/chat/completions \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-4.6",
    "messages": [{"role": "user", "content": "say HELLO"}]
  }'
```

**Streaming** (`"stream": true`): plain chat streams incrementally, one SSE chunk per token delta. Requests carrying `tools` or a JSON-schema constraint can't stream token-by-token (the answer only exists once fully computed) — they're **buffered**: the whole response is computed, then replayed as a single-shot SSE stream (role chunk → one content/tool_calls delta → finish chunk → `[DONE]`). The client's streaming parser is satisfied either way.

**Tools / `tool_choice`** (OpenAI client-executed tool calling): send `tools` (OpenAI function-schema array) and optionally `tool_choice` (`auto`/`none`/`required`/`{"type":"function","function":{"name":...}}`). pibox's own internal tools (bash, file edits) default OFF while in tool mode so the model behaves as a pure function-calling LLM — override with header `x-aicodebox-no-tools: 0` to re-enable the hybrid. The response comes back as `tool_calls` + `finish_reason: "tool_calls"`, exactly like OpenAI; you execute the tool client-side and send the result back in the next message round.

**`response_format` / JSON-schema**: standard OpenAI `response_format` body field —`{"type": "text"}` (default), `{"type": "json_object"}` (force parseable JSON, no shape constraint), or `{"type": "json_schema", "json_schema": {"name": ..., "schema": {...}}}` (schema-validated, with up to 3 self-correction retries on failure → 422 if still invalid). `tools` and `response_format` **compose** in one request: a tool-call turn returns `tool_calls` (not schema-checked); the model's final answer (no more tool calls) is what gets schema-validated.

Extra `x-aicodebox-*` headers (workspace pinning, session continuation, extra args, timeout, tools allowlist) are documented in [references/setup.md](references/setup.md#openai-endpoint-headers). Upstream provider errors (auth failure, rate limit, content-safety rejection) surface as HTTP 400, not a silent empty response.

## MCP server mode

`PIBOX_MCP_MODE=1`. Exposes an [MCP](https://modelcontextprotocol.io) (streamable HTTP) surface with 5 tools: `run_prompt`, `list_files`, `read_file`, `write_file`, `delete_file`. Coexists with any foreground mode:

| Foreground | MCP placement |
|---|---|
| API mode (`PIBOX_API_MODE=1`) | mounted at `/mcp` on the API port — no extra process |
| Telegram / Cron / passthrough / none | sidecar uvicorn on its own port, `PIBOX_MCP_MODE_PORT` (default `8081`), mounted at the port root |

```bash
claude mcp add --transport http pibox http://localhost:8080/mcp \
  --header "Authorization: Bearer your-mcp-token"
```

Raw JSON-RPC (debugging, non-MCP-aware callers):

```bash
curl -s http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer your-mcp-token" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

`run_prompt(prompt, workspace?, model?, system_prompt?, append_system_prompt?, no_continue=true, resume?, thinking?, json_schema?)` invokes the agent and returns its text. `list_files`/`read_file`/`write_file`/`delete_file` operate on workspace-relative paths with the same traversal guard as the REST `/files` endpoints.

**Destructive & irreversible.** `delete_file` removes a workspace file with no undo. An agent must NEVER call it unless the user explicitly asked for that exact action; confirm the specific target first; scope it to the current task; never enumerate-then-bulk-delete. On a shared/multi-tenant instance this can destroy another caller's workspace data — treat it as admin-only.

Auth: `PIBOX_MCP_MODE_TOKEN=<token>` — bearer via `Authorization: Bearer …`, or `?apiToken=…` query param for clients that can't set headers. Empty = no auth. **No fallback to `PIBOX_API_MODE_TOKEN`.**

**No auth when `PIBOX_MCP_MODE_TOKEN` is unset.** With it empty the MCP surface is UNAUTHENTICATED — anyone who can reach it gets `run_prompt` (arbitrary agent execution) and workspace file read/write/delete access. NEVER expose such an instance on a network or to untrusted agents; set the token and bind to loopback / behind an authenticating proxy.

## Telegram bot mode

`PIBOX_TELEGRAM_MODE=1` + `PIBOX_TELEGRAM_MODE_TOKEN=<token from @BotFather>`.

- Text in → pi runs → Markdown→HTML rendered response back.
- File uploads land in the chat's workspace. `[SEND_FILE: path]` in pi's output delivers workspace files as Telegram attachments.
- Per-chat overrides: `/model`, `/effort` (maps to pi's `--thinking` levels), `/system_prompt`, `/append_system_prompt`. Persisted across restarts.
- `/cancel` kills the in-flight run. `/reload` re-reads config. `/config` dumps merged settings. `/status` shows in-flight state. `/fetch <path>` downloads a file. `/start`, `/help` for basics.
- Replies to cron messages inject the job's instruction + result so pi has full context for follow-ups.

Config at `$HOME/.aicodebox/telegram.yml` (override via `PIBOX_TELEGRAM_MODE_CONFIG`):

```yaml
allowed_chats: [-100123, 42]
default:
  model: glm-4.6
  workspace: shared
chats:
  -100123:
    workspace: alpha
    allowed_users: [10, 20]
```

Auth: chat/user allowlisting via the config yaml (`allowed_chats`, per-chat `allowed_users`) — no separate bearer token, the bot token itself gates who can even message it.

## Cron scheduler mode

`PIBOX_CRON_MODE=1` + `PIBOX_CRON_MODE_FILE=/path/to/cron.yaml`. 6-field cron schedules via croniter. Each job fires pi with the given instruction on schedule.

```yaml
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

Each run gets a history dir at `$HOME/.aicodebox/cron/history/<workspace>/<timestamp>-<job>/` (override root via `PIBOX_CRON_MODE_HISTORY_DIR`) with `meta.json`, `stdout.log`, `stderr.log`, `result.txt`. If telegram is also configured, `telegram.json` lands there too and the next run's prompt gets a "prior run" hint so pi can reference its own history without you wiring it up. Running alongside Telegram mode (`PIBOX_TELEGRAM_MODE=1` + `PIBOX_CRON_MODE=1`) runs cron in-thread inside the telegram process — the only foreground-mode pairing allowed.

Auth: none — this is a scheduled background job, not a request-driven surface. `telegram_chat_id` on a job routes its result through the (already-authenticated) Telegram bot if set.

## Auth (LLM upstream)

pi speaks the Anthropic wire protocol. Point it at any Anthropic-compatible endpoint via env vars, forwarded into every mode:

| Var | Purpose |
|-----|---------|
| `ANTHROPIC_AUTH_TOKEN` | Bearer token (Z.AI, direct Anthropic, etc.) |
| `ANTHROPIC_API_KEY` | Same thing — pi reads both |
| `ANTHROPIC_BASE_URL` | Endpoint override (default `https://api.anthropic.com`) |
| `ANTHROPIC_MODEL` | Default model when the caller doesn't specify one |

Z.AI's GLM models are a fast/cheap default: `ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic` + `ANTHROPIC_MODEL=glm-4.6`.

pi's thinking levels (`--thinking`): `off`, `minimal`, `low`, `medium`, `high`, `xhigh`. Exposed as `/effort` in Telegram mode and `thinking` in API/OAI requests.

**Surface-level auth** (separate from the LLM upstream) is per-mode: `PIBOX_API_MODE_TOKEN` gates the REST + OAI routes, `PIBOX_MCP_MODE_TOKEN` gates MCP (no fallback between the two), Telegram gates by bot-token possession + chat/user allowlist, cron and interactive/exec modes have no surface auth (container-boundary trust). Both `PIBOX_API_MODE_TOKEN` and `PIBOX_MCP_MODE_TOKEN` default to empty, which means no auth — see [Security & safety](#security--safety) above before exposing either surface beyond localhost.

## Typical Workflows

**One-off task from a script, no server:**

```bash
docker run --rm -e ANTHROPIC_AUTH_TOKEN=$TOKEN -e ANTHROPIC_BASE_URL=$BASE_URL \
  -e ANTHROPIC_MODEL=glm-4.6 -v "$PWD:/workspace" \
  psyb0t/pibox:latest -p "summarize the diff in /workspace"
```

**Long-running server, drive it with curl:**

```bash
docker run -d --network host -e PIBOX_API_MODE=1 -e PIBOX_API_MODE_TOKEN=$SECRET \
  -e PIBOX_AVAILABLE_MODELS=glm-4.6 -e ANTHROPIC_AUTH_TOKEN=$TOKEN \
  -e ANTHROPIC_BASE_URL=$BASE_URL -v "$PWD/workspace:/workspace" psyb0t/pibox:latest
curl -s http://localhost:8080/run -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" -d '{"prompt": "run the tests and report failures"}'
```

**Structured extraction via JSON schema:**

```bash
curl -s http://localhost:8080/run -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "extract TODOs from /workspace", "jsonSchema": {"type":"object","properties":{"todos":{"type":"array","items":{"type":"string"}}},"required":["todos"]}}'
```

**Wire an MCP-aware agent (Claude Code, OpenClaw) to a running pibox:**

```bash
claude mcp add --transport http pibox http://localhost:8080/mcp \
  --header "Authorization: Bearer $MCP_TOKEN"
```

**Chat + Telegram + scheduled digest, all on one box:**

```bash
docker run -d --network host \
  -e PIBOX_TELEGRAM_MODE=1 -e PIBOX_TELEGRAM_MODE_TOKEN=$BOT_TOKEN \
  -e PIBOX_CRON_MODE=1 -e PIBOX_CRON_MODE_FILE=/config/cron.yaml \
  -e ANTHROPIC_AUTH_TOKEN=$TOKEN -e ANTHROPIC_BASE_URL=$BASE_URL \
  -v "$PWD/workspace:/workspace" -v "$PWD/cron.yaml:/config/cron.yaml:ro" \
  psyb0t/pibox:latest
```
