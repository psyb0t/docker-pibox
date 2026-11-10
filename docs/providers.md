---
title: "LLM providers"
description: "Point Pi at an OpenAI-compatible, Anthropic Messages or Google endpoint with PIBOX_PROVIDER_*, or keep the ANTHROPIC_* compatibility path."
nav_order: 4
---

# LLM providers

pibox configures Pi's upstream model through environment variables. This is separate from pibox's OpenAI-compatible endpoint at `/openai/v1`.

Pi supports these custom HTTP APIs:

| `PIBOX_PROVIDER_API` | Endpoint type |
|---|---|
| `openai-completions` | OpenAI Chat Completions compatible endpoints, including LiteLLM |
| `openai-responses` | OpenAI Responses compatible endpoints |
| `anthropic-messages` | Anthropic Messages compatible endpoints, including Z.AI |
| `google-generative-ai` | Google Generative AI compatible endpoints |

Set the provider URL, protocol, token, and default model when starting the container:

| Variable | Default | Purpose |
|---|---|---|
| `PIBOX_PROVIDER_NAME` | `pibox` | Pi provider identifier. Lowercase letters, numbers, and `-`, starting with a letter, at most 64 characters. |
| `PIBOX_PROVIDER_API` | `openai-completions` | One API from the table above. |
| `PIBOX_PROVIDER_BASE_URL` | required | Upstream HTTP base URL. |
| `PIBOX_PROVIDER_API_KEY` | required | Upstream API key or token. |
| `PIBOX_PROVIDER_MODEL` | required | Default upstream model ID. |

Setting any one of them turns on the generic provider, and then the URL, key and model are all required. With the wrapper, set them on the host as in the [quick start](index.md#quick-start). The examples below use plain `docker run`.

LiteLLM uses its OpenAI-compatible `/v1` URL:

```bash
docker run --rm --network host \
  -e PIBOX_PROVIDER_BASE_URL=http://127.0.0.1:4000/v1 \
  -e PIBOX_PROVIDER_API=openai-completions \
  -e PIBOX_PROVIDER_API_KEY=your-litellm-virtual-key \
  -e PIBOX_PROVIDER_MODEL=your-model-id \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"
```

An Anthropic-compatible endpoint, including a Z.AI endpoint, uses the same variables with another protocol and base URL:

```bash
docker run --rm \
  -e PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/anthropic \
  -e PIBOX_PROVIDER_API=anthropic-messages \
  -e PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
  -e PIBOX_PROVIDER_MODEL=your-model-id \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"
```

Z.AI Coding Plan also exposes an OpenAI-compatible coding endpoint. Use a Coding Plan model that the account can call. The endpoint lists models at `GET /models`. The Anthropic endpoint lists models at `GET /v1/models`.

```bash
docker run --rm \
  -e PIBOX_PROVIDER_BASE_URL=https://api.z.ai/api/coding/paas/v4 \
  -e PIBOX_PROVIDER_API=openai-completions \
  -e PIBOX_PROVIDER_API_KEY=your-z-ai-api-key \
  -e PIBOX_PROVIDER_MODEL=glm-5.3-flash \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest \
  -p "list the files in /workspace"
```

For API mode, list the upstream models in `PIBOX_AVAILABLE_MODELS` so pibox can advertise and validate them. pibox registers every listed model with the provider under `PIBOX_PROVIDER_API`, so callers can request any of them, not only `PIBOX_PROVIDER_MODEL`. A model that Pi has no registration for falls back to Pi's default API shape, which disagrees with an Anthropic Messages base URL and fails with `Stream ended without finish_reason`:

```bash
docker run -d --name pibox --network host \
  -e PIBOX_API_MODE=1 \
  -e PIBOX_AVAILABLE_MODELS=your-model-id \
  -e PIBOX_PROVIDER_BASE_URL=http://127.0.0.1:4000/v1 \
  -e PIBOX_PROVIDER_API=openai-completions \
  -e PIBOX_PROVIDER_API_KEY=your-litellm-virtual-key \
  -e PIBOX_PROVIDER_MODEL=your-model-id \
  -v "$PWD/workspace:/workspace" \
  psyb0t/pibox:latest
```

## What startup writes

At every container start, [`setup-provider-env.sh`](https://github.com/psyb0t/docker-pibox/blob/main/pibox/scripts/setup-provider-env.sh) writes Pi's provider entry to `/home/aicode/.pi/agent/models.json` and records the selected provider and model in `/home/aicode/.pi/agent/pibox-provider.json`. Other providers in `models.json` are kept. The entrypoint passes `PIBOX_PROVIDER_API_KEY` to the unprivileged Pi process as `OPENAI_API_KEY`, and `models.json` stores the `$OPENAI_API_KEY` reference, not the key value. Restart the container after changing configuration.

Every model is registered with a 128,000-token context window and a 16,384-token output limit. The script logs to stderr and to `/tmp/pibox-provider-setup.log` inside the container. Invalid settings stop the container before any mode starts. [Troubleshooting](troubleshooting.md#provider-settings-stop-the-container) lists the messages.

When the base URL contains `/anthropic` but `PIBOX_PROVIDER_API` is not `anthropic-messages`, or the reverse with a `/v<number>` path, startup logs a `provider_api_base_url_mismatch` warning and continues. A mismatched protocol otherwise shows up later as a truncated stream.

## Anthropic compatibility

Existing `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, and `ANTHROPIC_MODEL` deployments keep working. They are a compatibility shortcut for Anthropic Messages endpoints. Do not set `PIBOX_PROVIDER_*` with `ANTHROPIC_BASE_URL`. pibox exits instead of selecting an ambiguous provider.

| Variable | Purpose |
| --- | --- |
| `ANTHROPIC_AUTH_TOKEN` | Bearer token for Z.AI, Anthropic or another Anthropic Messages endpoint |
| `ANTHROPIC_API_KEY` | Used when `ANTHROPIC_AUTH_TOKEN` is empty |
| `ANTHROPIC_BASE_URL` | Endpoint. Setting it turns on the managed `anthropic` provider entry |
| `ANTHROPIC_MODEL` | Default model when the caller does not name one |

The wrapper forwards only `PIBOX_*` names, so send these through it with the `PIBOX_ENV_` prefix:

```bash
PIBOX_ENV_ANTHROPIC_AUTH_TOKEN=your-z-ai-api-key \
PIBOX_ENV_ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
PIBOX_ENV_ANTHROPIC_MODEL=your-model-id \
pibox -p "explain this project"
```

With `ANTHROPIC_BASE_URL` set, startup writes an `anthropic` provider into `models.json` with the token itself as the key, not an environment reference, and registers `ANTHROPIC_MODEL` plus every model in `PIBOX_AVAILABLE_MODELS`. See [Security](security.md#secrets-on-disk).

Pi also reads its usual provider keys, such as `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY` and `ZAI_API_KEY`, for its built-in providers. The base entrypoint passes those through to Pi unchanged. Through the wrapper they also need the `PIBOX_ENV_` prefix.

The generic provider variables cover Pi's documented custom HTTP APIs. They do not configure every cloud-specific Pi provider through a base URL.
