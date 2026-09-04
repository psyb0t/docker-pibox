# API Mode

`PIBOX_API_MODE=1`. Runs pibox as a long-lived FastAPI server on `:8080` (override with `PIBOX_API_MODE_PORT`), exposing agent runs, workspace file operations, and an OpenAI-compatible chat endpoint.

> **Required:** `PIBOX_AVAILABLE_MODELS=<csv>` (e.g. `glm-4.6,claude-sonnet-4-6`). API mode refuses to boot without it — `/openai/v1/models` needs a real list and there's no sensible default (pi can drive any provider's models). Pick the ones your configured `ANTHROPIC_BASE_URL` / provider actually serves.

## Setup

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

## Endpoints

| Method | Path | What it does |
|--------|------|--------------|
| `GET` | `/healthz` | liveness |
| `GET` | `/status` | in-flight runs |
| `POST` | `/run` | agent run → `{runId, workspace, exitCode, text, ...}`; body `async`/`fireAndForget` starts a background run and returns its job id |
| `GET` | `/run/result?runId=<id>` | poll async job |
| `DELETE` | `/run/{id}` | kill in-flight run |
| `GET` | `/files` | list the workspace root (`{entries: [{name, type, size?}, ...]}`) |
| `GET` | `/files/{path}` | list a sub-directory, or stream a file's bytes |
| `PUT` | `/files/{path}` | upload — raw request body becomes the file contents; parent dirs auto-created |
| `DELETE` | `/files/{path}` | delete a file (refuses directories — 400) |
| `POST` | `/openai/v1/chat/completions` | OpenAI-compatible (streaming + non-streaming; supports `tools` / `tool_choice` client-executed tool calling, composable with `response_format`) |
| `GET` | `/openai/v1/models` | model list |
| `POST` | `/mcp` | MCP server (streamable HTTP) — mounted only when `PIBOX_MCP_MODE=1`. See [mcp.md](mcp.md) |

All `/files/*` paths are resolved against the workspace root with traversal checking — `..` segments that escape the root return 400. Same `Authorization: Bearer ...` token gates them as the rest of the API.

```bash
# upload a file
curl -sS -X PUT \
  -H "Authorization: Bearer your-secret" \
  --data-binary @local.txt \
  http://localhost:8080/files/notes/hello.txt

# download it back
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt

# list the dir
curl -sS -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes | jq

# delete it
curl -sS -X DELETE -H "Authorization: Bearer your-secret" \
  http://localhost:8080/files/notes/hello.txt
```

## Running a prompt

**`POST /run`** body: `prompt` (required), `workspace`, `model`, `systemPrompt`, `appendSystemPrompt`, `jsonSchema`, `eventMode`, `outputFormat`, `noContinue`, `resume`, `timeoutSeconds`, `thinking`, `noTools`, `toolsAllowlist`, `includeRaw`, `async`, `fireAndForget`.

Set `"eventMode": "full"` to include complete Pi JSONL records in the response. Every event is wrapped as `{sequence, attempt, backend, eventType, event}` and the nested `event` stays native, so thinking deltas, tool starts, tool updates, tool results, retries, compaction, and provider metadata remain available to callers. `"eventMode": "none"` returns only the final result. The default `"auto"` keeps legacy schema behavior by enabling events for `jsonSchema` requests; `"outputFormat": "json-verbose"` is the compatibility alias for that automatic full-event mode.

`"outputFormat": "text"` and `"outputFormat": "json"` remain accepted legacy inputs but do not change the `/run` response serialization. New callers should use `eventMode`; only `json-verbose` has a compatibility effect while `eventMode` is `auto`.

`jsonSchema` controls only the validated final `json` result. It can be combined with either event mode.

```bash
curl -s http://localhost:8080/run \
  -H "Authorization: Bearer your-secret" \
  -H "Content-Type: application/json" \
  -d '{"prompt": "say HELLO", "workspace": "/workspace"}'
```

## API mode environment variables

| Var | Default | What it does |
|-----|---------|--------------|
| `PIBOX_API_MODE` | `0` | Boot the HTTP API server (foreground) |
| `PIBOX_API_MODE_PORT` | `8080` | Port the API server binds to |
| `PIBOX_API_MODE_TOKEN` | empty | Bearer token for the API surface. Empty = no auth |
| `PIBOX_AVAILABLE_MODELS` | — | **Required for API mode.** CSV list returned by `/openai/v1/models`. API mode refuses to boot without it |

> Every `PIBOX_*` variable is an alias for the `AICODEBOX_*` equivalent read by the base image. If both are set, `AICODEBOX_*` wins.

## Combined with MCP mode

API mode is the one foreground mode where MCP costs nothing extra — it mounts at `/mcp` on this same port instead of spawning a sidecar. See [mcp.md](mcp.md).
