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
| `PIBOX_PROVIDER_NAME` | `pibox` | Pi provider identifier. Lowercase letters, numbers, and `-` only. |
| `PIBOX_PROVIDER_API` | `openai-completions` | One API from the table above. |
| `PIBOX_PROVIDER_BASE_URL` | required | Upstream HTTP base URL. |
| `PIBOX_PROVIDER_API_KEY` | required | Upstream API key or token. |
| `PIBOX_PROVIDER_MODEL` | required | Default upstream model ID. |

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

For API mode, list the upstream models in `PIBOX_AVAILABLE_MODELS` so pibox can advertise and validate them:

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

The entrypoint writes Pi's provider metadata to `/home/aicode/.pi/agent/models.json` and records the selected provider and model in a separate state file. It passes `PIBOX_PROVIDER_API_KEY` to the unprivileged Pi process as `OPENAI_API_KEY`. Pi stores the `$OPENAI_API_KEY` reference, not the key value. Restart the container after changing configuration.

## Anthropic compatibility

Existing `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, and `ANTHROPIC_MODEL` deployments keep working. They are a compatibility shortcut for Anthropic Messages endpoints. Do not set `PIBOX_PROVIDER_*` with `ANTHROPIC_BASE_URL`. pibox exits instead of selecting an ambiguous provider.

The generic provider variables cover Pi's documented custom HTTP APIs. They do not configure every cloud-specific Pi provider through a base URL.
