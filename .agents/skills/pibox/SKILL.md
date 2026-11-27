---
name: pibox
description: "Run pi-coding-agent through an already-installed pibox: interactive and one-shot `pibox -p` calls, plus its HTTP /run API, OpenAI-compatible endpoint, MCP tools, Telegram bot and cron results. Use when the user asks to run pi in the pibox container or to call a pibox server."
homepage: https://github.com/psyb0t/docker-pibox
user-invocable: true
permissions:
  network:
    - "the pibox server the user runs, http://localhost:8080 by default or the PIBOX_URL the user sets"
    - "the model provider URL the user configured for pibox: pibox sends prompts and workspace content there"
    - "api.telegram.org, only when the user's pibox runs Telegram mode"
  filesystem:
    read:
      - "the current workspace"
    write:
      - "the current workspace (pibox runs the agent with read-write access to it)"
  shell:
    - "curl *"
    - "pibox *"
metadata:
  { "openclaw": { "emoji": "🥧", "primaryEnv": "PIBOX_URL", "requires": { "bins": ["pibox", "curl"] } } }
---

# pibox

[pi-coding-agent](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent) inside an [aicodebox](https://github.com/psyb0t/docker-aicodebox) container. One image, seven ways in: interactive shell, one-shot exec, HTTP REST API, OpenAI-compatible endpoint, MCP server, Telegram bot, cron scheduler.

You talk to pibox, pibox talks to pi, and pi talks to the upstream LLM the operator configured.

## Setup

pibox must already be installed and running; this skill only covers using it. Installation, the model provider and server configuration are in the docs at https://psyb0t.github.io/docker-pibox/ and the README at https://github.com/psyb0t/docker-pibox. For the HTTP, OpenAI and MCP surfaces, read `PIBOX_URL` (default `http://localhost:8080`), `PIBOX_API_MODE_TOKEN` and `PIBOX_MCP_MODE_TOKEN` from the environment the user set. For the local `pibox` command, run it from the workspace the user named.

## Agent execution

Use `pibox` when it is on `PATH`, from the workspace the user named.

```bash
pibox                                      # interactive Pi
pibox -p "inspect this workspace"           # one-shot work
pibox -p "review this change" --thinking high
```

Use an HTTP or MCP endpoint only when the user asks for a service or provides an already-running remote URL.

## Security & safety

- **An empty token means no authentication.** With `PIBOX_API_MODE_TOKEN` empty, the REST and OpenAI-compatible API is open: anyone who can reach it can run the agent and read, write and delete workspace files. `PIBOX_MCP_MODE_TOKEN` does the same for the MCP surface and does not fall back to the API token. If the user's server is open, tell them rather than relying on it.
- **pibox is not isolated from the host.** The agent runs with broad access to the workspace and to host resources the wrapper provides, so use it only in a workspace the user trusts the agent with, and do not feed it untrusted prompts or repositories.
- **Deletes cannot be undone.** `DELETE /run/{id}`, `DELETE /files/{path}` and the MCP `delete_file` tool cancel a run or remove a file for good. Use them only on a run or file the current task created, and only when the user asked for that specific action.
- **Where data goes.** Prompts, tool output and workspace content go to the model provider the user configured. Telegram mode sends replies and files to `api.telegram.org`. The `curl` examples call the pibox server on `localhost:8080` by default, so change that address only to a pibox the user runs.
- **Credentials.** Read tokens from the environment, never print them. The values shown below are placeholders.

## When To Use

- Drive pi-coding-agent from a script/service instead of an interactive terminal (`/run`, `/openai/v1/chat/completions`, or MCP tools).
- Wire pi into an OpenAI-SDK-compatible client (LangChain, openai-python) via the `/openai/v1/*` surface.
- Give an MCP-aware agent (Claude, Cursor, OpenClaw) remote tool access to a pi-driven workspace.
- Chat with pi from Telegram, with per-chat model/effort overrides and file transfer.
- Read the results of scheduled pi runs (standups, digests, periodic maintenance).
- One-off run for a single prompt (CI step, quick script) via one-shot exec.

## When NOT To Use

- Don't expect `/openai/v1/chat/completions` to stream token-by-token when `tools` or a JSON schema is in play. Those modes compute the full answer first and replay it as a single-shot SSE stream (still a valid stream, just not incremental). Plain chat streams incrementally.
- Don't rely on `PIBOX_MCP_MODE_TOKEN` falling back to `PIBOX_API_MODE_TOKEN`. MCP has its own bearer, no fallback.
- Don't point multiple concurrent runs at the same workspace. The API/OAI layer returns 409 "workspace busy" while a run is in flight in that workspace.

## Interactive shell mode

Run `pibox` with no arguments. The wrapper starts Pi in the current workspace and preserves its host state.

```bash
pibox
```

## One-shot exec mode

`pibox -p "<prompt>"` runs Pi non-interactively and writes the result to stdout, then exits. The wrapper forwards Pi flags unchanged.

```bash
pibox -p "list the files in this workspace"
```

Any Pi CLI flag works here (`--model`, `--thinking`, `--session`, etc.). Pi's thinking levels (`--thinking`): `off`, `minimal`, `low`, `medium`, `high`, `xhigh`. Exposed as `/effort` in Telegram mode and `thinking` in API/OAI requests.

## REST API

The API listens at `PIBOX_URL`. The models it accepts are the ones the operator configured; list them with `GET /openai/v1/models`.

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/healthz` | liveness, `{ok, adapter}`, unauthenticated |
| `GET` | `/status` | in-flight runs + busy workspaces |
| `POST` | `/run` | run the agent, sync by default; body `async` or `fireAndForget` makes it fire-and-poll |
| `GET` | `/run/result?runId=<id>` | poll a run started with `async`/`fireAndForget` |
| `DELETE` | `/run/{id}` | cancel an in-flight run (kills the subprocess) |
| `GET` | `/files` | list the workspace root, `{entries: [{name, type, size?}, ...]}` |
| `GET` | `/files/{path}` | list a sub-directory, or stream a file's bytes |
| `PUT` | `/files/{path}` | upload: raw request body becomes the file contents; parent dirs auto-created |
| `DELETE` | `/files/{path}` | delete a file (refuses directories with 400) |
| `POST` | `/openai/v1/chat/completions` | OpenAI-compatible chat (see below) |
| `GET` | `/openai/v1/models` | model list the server advertises |
| `POST` | `/mcp/` | MCP server (streamable HTTP), when the operator enabled it. Slashless `/mcp` reaches the same handler |

All `/files/*` paths resolve against the workspace root with traversal checking: `..` segments that escape the root return 400. Every route except `/healthz` expects `Authorization: Bearer <PIBOX_API_MODE_TOKEN>` when the server has a token set.

```bash
# sync run
curl -s "$PIBOX_URL/run" \
  -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "say HELLO", "workspace": "myproject"}'

# async run, then poll
RUN_ID=$(curl -s "$PIBOX_URL/run" \
  -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" -H "Content-Type: application/json" \
  -d '{"prompt": "long task", "async": true}' | jq -r .runId)
curl -s "$PIBOX_URL/run/result?runId=$RUN_ID" \
  -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN"

# cancel it
curl -s -X DELETE "$PIBOX_URL/run/$RUN_ID" \
  -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN"

# upload / download / list / delete a workspace file
curl -sS -X PUT -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  --data-binary @local.txt "$PIBOX_URL/files/notes/hello.txt"
curl -sS -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  "$PIBOX_URL/files/notes/hello.txt"
curl -sS -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  "$PIBOX_URL/files/notes" | jq
curl -sS -X DELETE -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  "$PIBOX_URL/files/notes/hello.txt"
```

**`POST /run`** body fields: `prompt` (required), `workspace`, `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `noContinue`, `resume`, `timeoutSeconds`, `thinking`, `noTools`, `toolsAllowlist`, `extraArgs`, `async`, `fireAndForget`, `includeRaw`. With `jsonSchema` set the response is verbose: `text`, `json` (schema-validated), `events`, `sessionId`, `usage`, `attempts` (per-retry breakdown, up to 3 self-correction retries on parse/validation failure). Without `jsonSchema` the response is lean: `{runId, workspace, exitCode, text}`.

## OpenAI-compatible endpoint

`POST /openai/v1/chat/completions` and `GET /openai/v1/models`, same URL and token as the API. Drop-in for any OpenAI-SDK client: point the base URL at `$PIBOX_URL/openai/v1` and set the model to one listed by `/openai/v1/models`.

```bash
curl -s "$PIBOX_URL/openai/v1/chat/completions" \
  -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "your-model-id",
    "messages": [{"role": "user", "content": "say HELLO"}]
  }'
```

**Streaming** (`"stream": true`): plain chat streams incrementally, one SSE chunk per token delta. Requests carrying `tools` or a JSON-schema constraint can't stream token-by-token (the answer only exists once fully computed), so they're **buffered**: the whole response is computed, then replayed as a single-shot SSE stream (role chunk → one content/tool_calls delta → finish chunk → `[DONE]`). The client's streaming parser is satisfied either way.

**Tools / `tool_choice`** (OpenAI client-executed tool calling): send `tools` (OpenAI function-schema array) and optionally `tool_choice` (`auto`/`none`/`required`/`{"type":"function","function":{"name":...}}`). pibox's own internal tools (bash, file edits) default OFF while in tool mode so the model behaves as a pure function-calling LLM. Override with header `x-aicodebox-no-tools: 0` to re-enable the hybrid. The response comes back as `tool_calls` + `finish_reason: "tool_calls"`, exactly like OpenAI; you execute the tool client-side and send the result back in the next message round.

**`response_format` / JSON-schema**: standard OpenAI `response_format` body field: `{"type": "text"}` (default), `{"type": "json_object"}` (force parseable JSON, no shape constraint), or `{"type": "json_schema", "json_schema": {"name": ..., "schema": {...}}}` (schema-validated, with up to 3 self-correction retries on failure → 422 if still invalid). `tools` and `response_format` **compose** in one request: a tool-call turn returns `tool_calls` (not schema-checked); the model's final answer (no more tool calls) is what gets schema-validated.

Upstream provider errors (auth failure, rate limit, content-safety rejection) surface as HTTP 400, not a silent empty response.

Non-standard `x-aicodebox-*` request headers extend the endpoint beyond stock OpenAI fields (legacy `x-claude-*` aliases also work for `workspace`/`continue`/`append-system-prompt`):

| Header | Purpose |
|---|---|
| `x-aicodebox-workspace` | Pin the run to a workspace subpath instead of the ephemeral/default one |
| `x-aicodebox-continue` | `1`/`true`/`yes` to continue the most recent session in that workspace instead of starting fresh |
| `x-aicodebox-append-system-prompt` | Append text to the system prompt |
| `x-aicodebox-json-schema` | JSON-encoded schema, a fallback for clients that can't set the standard `response_format` body field (body field wins if both are set) |
| `x-aicodebox-resume` | Resume a specific session id |
| `x-aicodebox-extra-args` | Extra pi CLI args, as a JSON array or comma-separated string |
| `x-aicodebox-timeout-seconds` | Per-request run timeout |
| `x-aicodebox-tools-allowlist` | Restrict pi's own internal tools, as a JSON array or comma-separated string |
| `x-aicodebox-no-tools` | `1`/`true`/`yes` to disable pi's internal tools; in OpenAI-tools mode this is the override to re-enable them (send `0`) |

## MCP server

The MCP surface (streamable HTTP) has 5 tools: `run_prompt`, `list_files`, `read_file`, `write_file`, `delete_file`. It is at `$PIBOX_URL/mcp/` when the API server serves it, or at the root of its own port (default `8081`) when it runs standalone. Use the URL the user gives you.

```bash
claude mcp add --transport http pibox "$PIBOX_URL/mcp/" \
  --header "Authorization: Bearer $PIBOX_MCP_MODE_TOKEN"
```

Raw JSON-RPC (debugging, non-MCP-aware callers):

```bash
curl -s "$PIBOX_URL/mcp/" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Authorization: Bearer $PIBOX_MCP_MODE_TOKEN" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

`run_prompt(prompt, workspace?, model?, system_prompt?, append_system_prompt?, no_continue=true, resume?, thinking?, json_schema?)` invokes the agent and returns its text. `list_files`/`read_file`/`write_file`/`delete_file` operate on workspace-relative paths with the same traversal guard as the REST `/files` endpoints.

Auth: `PIBOX_MCP_MODE_TOKEN` as `Authorization: Bearer ...`, or the `?apiToken=...` query param for clients that can't set headers. There is no fallback to the API token. An MCP server behind a reverse proxy may reject requests whose `Host` or `Origin` it was not configured to accept; if that happens, tell the user.

## Telegram bot

When the user's instance runs the Telegram bot:

- Text in → pi runs → Markdown→HTML rendered response back.
- File uploads land in the chat's workspace. `[SEND_FILE: path]` in pi's output delivers workspace files as Telegram attachments.
- Per-chat overrides: `/model`, `/effort` (maps to pi's `--thinking` levels), `/system_prompt`, `/append_system_prompt`. Persisted across restarts.
- `/cancel` kills the in-flight run. `/reload` re-reads config. `/config` dumps merged settings. `/status` shows in-flight state. `/fetch <path>` downloads a file. `/start`, `/help` for basics.
- Replies to cron messages inject the job's instruction + result so pi has full context for follow-ups.

## Cron scheduler

When the user's instance runs the cron scheduler, YAML-defined jobs fire pi on 6-field cron schedules and can post results to Telegram. Each run records `meta.json`, `stdout.log`, `stderr.log` and `result.txt` in the instance's cron history. Job definitions are the operator's to manage; see the docs at https://psyb0t.github.io/docker-pibox/.

## Typical Workflows

**Long-running server, drive it with curl:**

```bash
curl -s "$PIBOX_URL/run" -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  -H "Content-Type: application/json" -d '{"prompt": "run the tests and report failures"}'
```

**Structured extraction via JSON schema:**

```bash
curl -s "$PIBOX_URL/run" -H "Authorization: Bearer $PIBOX_API_MODE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "extract TODOs from /workspace", "jsonSchema": {"type":"object","properties":{"todos":{"type":"array","items":{"type":"string"}}},"required":["todos"]}}'
```

**Wire an MCP-aware agent (Claude Code, OpenClaw) to a running pibox:**

```bash
claude mcp add --transport http pibox "$PIBOX_URL/mcp/" \
  --header "Authorization: Bearer $PIBOX_MCP_MODE_TOKEN"
```
