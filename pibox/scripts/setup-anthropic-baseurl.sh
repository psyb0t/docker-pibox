#!/bin/bash
# Bridge ANTHROPIC_BASE_URL / ANTHROPIC_MODEL into pi's models.json.
#
# pi does not honour ANTHROPIC_BASE_URL natively (per its docs: "use
# models.json"). When the user provides Anthropic-compatible credentials
# pointing at a non-anthropic.com endpoint (Z.AI, OpenRouter Anthropic proxy,
# self-hosted proxies, etc.), seed an `anthropic` provider override that
# redirects the built-in provider to that base URL and reuses the same auth
# env var.
#
# Idempotent: the anthropic provider entry is rewritten on every boot
# (jq-merged into any existing models.json), so changes to
# ANTHROPIC_BASE_URL / ANTHROPIC_MODEL pick up on container restart even
# when ~/.pi is a persisted volume.
#
# Invoked from /usr/local/bin/pibox-entrypoint via `sudo -E -u aicode -H`,
# so it always runs as the aicode user with HOME=/home/aicode.
set -e

if [ -z "$ANTHROPIC_BASE_URL" ]; then
    exit 0
fi

PI_DIR="$HOME/.pi/agent"
mkdir -p "$PI_DIR"

MODELS_FILE="$PI_DIR/models.json"

# Pick the auth env var name pi should resolve at request time.
# Prefer ANTHROPIC_AUTH_TOKEN (the canonical claude-code-compatible name);
# fall back to ANTHROPIC_API_KEY.
if [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
    KEY_VAR="ANTHROPIC_AUTH_TOKEN"
elif [ -n "$ANTHROPIC_API_KEY" ]; then
    KEY_VAR="ANTHROPIC_API_KEY"
else
    # No key set — nothing to wire up.
    exit 0
fi

# Build the models array. If ANTHROPIC_MODEL is set, include it so /model and
# --model patterns find it without needing extra config.
MODELS_JSON='[]'
if [ -n "$ANTHROPIC_MODEL" ]; then
    MODELS_JSON=$(jq -n --arg id "$ANTHROPIC_MODEL" '
      [{
        id: $id,
        name: $id,
        api: "anthropic-messages",
        input: ["text"],
        contextWindow: 128000,
        maxTokens: 16384
      }]
    ')
fi

NEW=$(jq -n \
    --arg base "$ANTHROPIC_BASE_URL" \
    --arg key "$KEY_VAR" \
    --argjson models "$MODELS_JSON" '
    {
      providers: {
        anthropic: {
          baseUrl: $base,
          api: "anthropic-messages",
          apiKey: $key,
          models: $models
        }
      }
    }
')

if [ -f "$MODELS_FILE" ]; then
    # Merge into existing models.json without clobbering unrelated providers.
    tmp="$(mktemp)"
    jq -s '.[0] * .[1]' "$MODELS_FILE" <(echo "$NEW") > "$tmp" && mv "$tmp" "$MODELS_FILE"
else
    echo "$NEW" > "$MODELS_FILE"
fi

chmod 600 "$MODELS_FILE"
