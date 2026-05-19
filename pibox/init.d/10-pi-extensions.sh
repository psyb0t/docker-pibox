#!/bin/bash
# Wire the pibox extensions into the aicode user's pi config on first run.
#
# pi auto-discovers extensions listed in ~/.pi/agent/settings.json under
# `extensions`. We point it at the in-image mcp-bridge so MCP servers
# declared in workspace .mcp.json files become tools available to pi.
set -e

PI_DIR="$HOME/.pi/agent"
mkdir -p "$PI_DIR"

SETTINGS_FILE="$PI_DIR/settings.json"
MCP_BRIDGE="/opt/pibox/extensions/mcp-bridge/index.ts"

# Seed settings.json if missing, otherwise patch in the extension path.
if [ ! -f "$SETTINGS_FILE" ]; then
    cat > "$SETTINGS_FILE" <<EOF
{
  "extensions": ["$MCP_BRIDGE"],
  "quietStartup": true
}
EOF
else
    # Idempotent patch using jq.
    tmp="$(mktemp)"
    jq --arg p "$MCP_BRIDGE" '
        .extensions = ((.extensions // []) + [$p] | unique)
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
fi

chmod 600 "$SETTINGS_FILE"
