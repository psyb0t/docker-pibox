---
title: "Troubleshooting"
description: "Fixes for pibox startup refusals, provider errors such as Stream ended without finish_reason, busy workspaces, MCP 421 and 403, and wrapper errors."
nav_order: 9
---

# Troubleshooting

Start with the container log: `docker logs <container>` for a detached container, or the terminal for a foreground one. Provider setup also writes to `/tmp/pibox-provider-setup.log` inside the container.

## Provider settings stop the container

[`setup-provider-env.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/scripts/setup-provider-env.sh) runs at every start and exits on invalid settings, before any mode starts. The log line carries one of these messages:

| Message | Fix |
| --- | --- |
| `PIBOX_PROVIDER_* cannot be combined with ANTHROPIC_BASE_URL` | Use one provider path. Unset `ANTHROPIC_BASE_URL` or every `PIBOX_PROVIDER_*` variable |
| `PIBOX_PROVIDER_BASE_URL is required` | Setting any `PIBOX_PROVIDER_*` variable turns the generic provider on. Set the URL, key and model too |
| `PIBOX_PROVIDER_API_KEY is required` | Same as above |
| `PIBOX_PROVIDER_MODEL is required` | Same as above |
| `PIBOX_PROVIDER_NAME must match ^[a-z][a-z0-9-]*$` | Use lowercase letters, digits and `-`, starting with a letter |
| `PIBOX_PROVIDER_BASE_URL must be an http or https URL without whitespace` | Fix the URL |
| `PIBOX_PROVIDER_API must be openai-completions, openai-responses, anthropic-messages, or google-generative-ai` | Pick one of those |
| `... must be a single line` or `... exceeds N characters` | Remove line breaks, or shorten the value |
| `ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY is required when ANTHROPIC_BASE_URL is set` | Set one of the two |
| `refusing symlinked models.json` | Replace `~/.pi/agent/models.json` with a regular file |
| `models.json is not valid provider configuration` | Fix or remove the JSON in `~/.pi/agent/models.json` |

## Stream ended without finish_reason

The request reached the endpoint with the wrong protocol. Two causes:

- `PIBOX_PROVIDER_API` does not match the base URL, for example `openai-completions` against an Anthropic Messages URL. Startup logs a `provider_api_base_url_mismatch` warning when the URL makes the mismatch obvious.
- A caller asked for a model that is not registered with the provider. Add it to `PIBOX_AVAILABLE_MODELS` and restart, so startup registers it under `PIBOX_PROVIDER_API`.

## API mode exits at startup

A log line starting with `api: no models configured` means `PIBOX_AVAILABLE_MODELS` is empty. Set it to the comma-separated model IDs your provider serves.

## HTTP errors from the API

| Status | Cause |
| --- | --- |
| `401` | Missing or wrong bearer token |
| `400 invalid workspace subpath` | `workspace` was absolute or contained `..`. Send a path relative to the workspace root |
| `409` | Another run is using that workspace. Wait, or use another workspace |
| `422` on `/openai/v1/chat/completions` | The reply still failed the JSON schema after three retries |
| `400` with a provider message on `/openai/v1/chat/completions` | The upstream provider refused the request: wrong key, rate limit or content filter |

## MCP returns 421 or 403

DNS rebinding protection rejected the `Host` (421) or the browser `Origin` (403). Add the exact values your proxy or client sends to `PIBOX_MCP_MODE_ALLOWED_HOSTS` or `PIBOX_MCP_MODE_ALLOWED_ORIGINS`, keeping the loopback entries. See [MCP mode](modes/mcp.md#reverse-proxies-and-public-hosts).

## The wrapper refuses to start

| Message | Fix |
| --- | --- |
| `PIBOX_FULL must be 0 or 1` | Use `0` or `1` |
| `PIBOX_DETACH must be 0 or 1` | Use `0` or `1` |
| `unsupported AICODEBOX_LAUNCH_CONTEXT_VERSION` | The parent box passed a launch context this wrapper does not know. Update both wrappers |
| Docker reports the container name is already in use | A detached container from the same directory is still there. Remove it with `docker rm -f <name>`, or set `PIBOX_CONTAINER_NAME` |

## The installer fails

| Message | Fix |
| --- | --- |
| `Docker is not installed` | Install Docker first |
| `local image not found image=...` | `PIBOX_SRC_LOCAL=true` needs the image built locally. Run `make build`, or drop the variable |
| `PIBOX_SRC_LOCAL must be true or false` | Use `true` or `false` |

## ANTHROPIC_* settings have no effect through the wrapper

The wrapper forwards only `PIBOX_*` variables. Send other variables with the `PIBOX_ENV_` prefix, such as `PIBOX_ENV_ANTHROPIC_AUTH_TOKEN`, or switch to `PIBOX_PROVIDER_*`.
