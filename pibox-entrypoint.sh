#!/bin/bash
# pibox entrypoint — thin wrapper around the aicodebox base entrypoint.
#
# Translates PIBOX_* env vars to their AICODEBOX_* equivalents so the
# image presents a pibox-branded surface to users. AICODEBOX_* still works
# (and wins if both are set) for power users and backwards compatibility.
set -e

# var-name pairs: PIBOX_X → AICODEBOX_X. If AICODEBOX_X is unset/empty and
# PIBOX_X is set, copy the value across. Internal vars (ADAPTER, AGENT_BINARY)
# are NOT exposed — the pibox Dockerfile pins those.
_PIBOX_ALIASES=(
    API_MODE
    API_MODE_PORT
    API_MODE_TOKEN
    TELEGRAM_MODE
    TELEGRAM_MODE_TOKEN
    TELEGRAM_MODE_CONFIG
    TELEGRAM_MODE_OVERRIDES
    CRON_MODE
    CRON_MODE_FILE
    CRON_MODE_HISTORY_DIR
    MCP_MODE
    MCP_MODE_PORT
    MCP_MODE_TOKEN
    WORKSPACE
    AVAILABLE_MODELS
    AVAILABLE_EFFORTS
    CONTAINER_NAME
)

for _suffix in "${_PIBOX_ALIASES[@]}"; do
    _pibox_var="PIBOX_${_suffix}"
    _aicode_var="AICODEBOX_${_suffix}"
    _pibox_val="$(printenv "$_pibox_var" 2>/dev/null || true)"
    _aicode_val="$(printenv "$_aicode_var" 2>/dev/null || true)"
    if [ -n "$_pibox_val" ] && [ -z "$_aicode_val" ]; then
        export "$_aicode_var=$_pibox_val"
    fi
done

unset _PIBOX_ALIASES _suffix _pibox_var _aicode_var _pibox_val _aicode_val

# pi has no native ANTHROPIC_BASE_URL support — it reads the base URL from
# ~/.pi/agent/models.json. Regenerate the anthropic provider entry on every
# boot so changes to ANTHROPIC_BASE_URL / ANTHROPIC_MODEL pick up even when
# the home dir is a persisted volume. (Old layout ran this via init.d which
# only fires once per container lifetime — fine for ephemeral runs, broken
# the moment ~/.aicodebox or ~/.pi is bind-mounted.)
if [ -n "${ANTHROPIC_BASE_URL:-}" ] && [ -x /opt/pibox/scripts/setup-anthropic-baseurl.sh ]; then
    sudo -E -u aicode -H bash /opt/pibox/scripts/setup-anthropic-baseurl.sh \
        || echo "[pibox-entrypoint] setup-anthropic-baseurl.sh failed (non-fatal)" >&2
fi

exec /usr/local/bin/aicodebox-entrypoint "$@"
