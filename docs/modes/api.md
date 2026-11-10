---
title: "API mode"
description: "pibox API mode: run Pi over HTTP, poll background runs, move workspace files, and use the OpenAI-compatible chat endpoint with tools."
parent: "Modes"
nav_order: 1
---

# API mode

`PIBOX_API_MODE=1`. Runs pibox as a long-lived FastAPI server on `:8080` (override with `PIBOX_API_MODE_PORT`), exposing agent runs, workspace file operations, and an OpenAI-compatible chat endpoint.

> **Required:** `PIBOX_AVAILABLE_MODELS=<csv>`, for example `your-model-id,your-other-model-id`. API mode refuses to boot without it because `/openai/v1/models` needs a real list. Pick models served by your configured upstream provider.

Configure the upstream model first. [LLM providers](../providers.md) covers OpenAI-compatible, Anthropic Messages, and Google Generative AI endpoints.

## Setup

Through the wrapper, from the directory the API should work in:

```bash
PIBOX_DETACH=1 \
PIBOX_API_MODE=1 \
PIBOX_API_MODE_TOKEN=your-secret \
PIBOX_AVAILABLE_MODELS=your-model-id \
PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic \
PIBOX_PROVIDER_API=anthropic-messages \
PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
PIBOX_PROVIDER_MODEL=your-model-id \
pibox
```

Or with plain Docker:

```bash
docker run -d --network host \
  -e PIBOX_API_MODE=1 \
  -e PIBOX_API_MODE_TOKEN=your-secret \
  -e PIBOX_AVAILABLE_MODELS=your-model-id \
  -e PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic \
  -e PIBOX_PROVIDER_API=anthropic-messages \
  -e PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
  -e PIBOX_PROVIDER_MODEL=your-model-id \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

`curl http://localhost:8080/healthz` answers `{"ok": true, "adapter": "pi"}` once the server is up.

## Endpoints

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/healthz` | Liveness, `{ok, adapter}`. The only route without the bearer token |
| `GET` | `/status` | In-flight runs and busy workspaces |
| `POST` | `/run` | Agent run, returns `{runId, workspace, exitCode, text, ...}`. Body `async` or `fireAndForget` starts a background run and returns its `runId` |
| `GET` | `/run/result?runId=<id>` | Poll a background run |
| `DELETE` | `/run/{id}` | Kill an in-flight run |
| `GET` | `/files` | List the workspace root, `{entries: [{name, type, size?}, ...]}` |
| `GET` | `/files/{path}` | List a subdirectory, or stream a file's bytes |
| `PUT` | `/files/{path}` | Upload. The raw request body becomes the file contents, and parent directories are created |
| `DELETE` | `/files/{path}` | Delete a file. Directories are refused with 400 |
| `POST` | `/openai/v1/chat/completions` | OpenAI-compatible chat, streaming and non-streaming. Supports `tools` and `tool_choice` for client-executed tool calls, combined with `response_format` if you like |
| `GET` | `/openai/v1/models` | The model list from `PIBOX_AVAILABLE_MODELS` |
| `POST` | `/mcp/` | MCP server over streamable HTTP, mounted only when `PIBOX_MCP_MODE=1`. Slashless `/mcp` reaches the same handler. See [MCP mode](mcp.md) |

All `/files/*` paths are resolved against the workspace root with traversal checking: `..` segments that escape the root return 400. The same `Authorization: Bearer ...` token gates them as the rest of the API.

```bash
# upload a file
curl -sS -X PUT \
  -H "Authorization: Bearer your-secret" \
  --data-binary @local.txt \
  http://localhost:8080/files/notes/hello.txt

# download it back
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt

# list the directory
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes | jq

# delete it
curl -sS -X DELETE -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt
```

## Running a prompt

**`POST /run`** body: `prompt` (required), `workspace`, `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `eventMode`, `outputFormat`, `noContinue`, `resume`, `timeoutSeconds`, `thinking`, `noTools`, `toolsAllowlist`, `extraArgs`, `includeRaw`, `async`, `fireAndForget`.

`workspace` is a path relative to the workspace root, such as `myproject`. The directory is created if missing. An absolute path or a `..` segment returns 400. Leave it out to run in the root. A second run in a workspace that is already busy returns 409.

By default a run continues the most recent Pi session in its workspace. `noContinue` starts a fresh, unsaved session, and `resume` picks a session by ID. `extraArgs` appends raw Pi CLI flags. `includeRaw` adds Pi's `stdout` and `stderr` to the response. `stderr` is always included when Pi exits nonzero.

Set `"eventMode": "full"` to include complete Pi JSONL records in the response. Every event is wrapped as `{sequence, attempt, backend, eventType, event}` and the nested `event` stays native, so thinking deltas, tool starts, tool updates, tool results, retries, compaction, and provider metadata remain available to callers. `"eventMode": "none"` returns only the final result. The default `"auto"` keeps legacy schema behavior by enabling events for `jsonSchema` requests; `"outputFormat": "json-verbose"` is the compatibility alias for that automatic full-event mode.

`"outputFormat": "text"` and `"outputFormat": "json"` remain accepted legacy inputs but do not change the `/run` response serialization. New callers should use `eventMode`; only `json-verbose` has a compatibility effect while `eventMode` is `auto`.

`jsonSchema` controls only the validated final `json` result. It can be combined with either event mode. Pi has no native schema enforcement, so the adapter appends the schema to the system prompt, and the base re-prompts up to three times when the reply does not parse or validate. The response then carries `json`, or `parseError` when every attempt failed, plus `attempts`, `sessionId` and `usage`.

```bash
curl -s http://localhost:8080/run \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "say HELLO", "workspace": "myproject"}'
```

A background run, polled until it finishes:

```bash
RUN_ID=$(
  curl -s http://localhost:8080/run \
    -H "Authorization: Bearer your-secret" \
    -H "Content-Type: application/json" \
    -d '{"prompt": "run the tests and report failures", "async": true}' |
    jq -r .runId
)

curl -s "http://localhost:8080/run/result?runId=$RUN_ID" \
  -H "Authorization: Bearer your-secret"
```

## OpenAI-compatible endpoint

Point any OpenAI SDK at `http://<host>:8080/openai/v1`, use the API token as the API key, and set the model to one of `PIBOX_AVAILABLE_MODELS`.

```bash
curl -s http://localhost:8080/openai/v1/chat/completions \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "your-model-id",
    "messages": [
      {
        "role": "user",
        "content": "say HELLO"
      }
    ]
  }'
```

- **Streaming.** With `"stream": true`, plain chat streams one SSE chunk per text delta. A request with `tools` or a JSON schema is computed in full first, then replayed as a single-chunk SSE stream, so streaming clients still work.
- **Tools.** Send `tools` and optionally `tool_choice` (`auto`, `none`, `required`, or a named function). The reply comes back as `tool_calls` with `finish_reason: "tool_calls"`. You run the tool and send the result in the next request. Pi's own tools (shell, file edits) are off in this mode, so the model acts as a plain function-calling model. Send the header `x-aicodebox-no-tools: 0` to turn them back on.
- **Structured output.** `response_format` accepts `{"type": "text"}`, `{"type": "json_object"}`, or `{"type": "json_schema", "json_schema": {"name": ..., "schema": {...}}}`. A schema reply that is still invalid after three retries returns 422. With `tools` in the same request, only the final answer is checked against the schema.
- **Thinking.** The body field `reasoning_effort` sets Pi's thinking level, one of `off`, `minimal`, `low`, `medium`, `high` or `xhigh`.
- **Errors.** Upstream provider errors, such as a failed login, a rate limit or a content filter, return HTTP 400 with the provider's message instead of an empty reply.

These request headers extend the endpoint beyond stock OpenAI fields:

| Header | Purpose |
| --- | --- |
| `x-aicodebox-workspace` | Run in this workspace subpath. Without it, a schema request runs in a temporary directory that is removed afterwards, and any other request runs in the workspace root |
| `x-aicodebox-continue` | `1`, `true` or `yes` continues the most recent session in that workspace |
| `x-aicodebox-append-system-prompt` | Append text to the system prompt |
| `x-aicodebox-json-schema` | JSON-encoded schema, for clients that cannot send `response_format`. The body field wins when both are set |
| `x-aicodebox-resume` | Resume a session by ID |
| `x-aicodebox-extra-args` | Extra Pi CLI flags, as a JSON array or a comma-separated list |
| `x-aicodebox-timeout-seconds` | Run timeout for this request |
| `x-aicodebox-tools-allowlist` | Restrict Pi's own tools, as a JSON array or a comma-separated list |
| `x-aicodebox-no-tools` | `1`, `true` or `yes` turns Pi's own tools off. `0` turns them back on in tools mode |

`x-claude-workspace`, `x-claude-continue` and `x-claude-append-system-prompt` are accepted as older spellings.

## API mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_API_MODE` | `0` | Boot the HTTP API server (foreground) |
| `PIBOX_API_MODE_PORT` | `8080` | Port the API server binds to |
| `PIBOX_API_MODE_TOKEN` | empty | Bearer token for the API surface. Empty means no auth |
| `PIBOX_AVAILABLE_MODELS` | none | **Required for API mode.** CSV list returned by `/openai/v1/models`. pibox registers every listed model with the upstream provider under `PIBOX_PROVIDER_API`. API mode refuses to boot without it |

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

Read [Security](../security.md) before you expose the port. An empty token leaves Pi, and through it the container, open to anyone who can reach it.

## Combined with MCP mode

API mode is the one foreground mode where MCP costs nothing extra: it mounts at `/mcp/` on this same port instead of starting a sidecar. See [MCP mode](mcp.md).
