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
    MODE_API
    MODE_API_PORT
    MODE_API_TOKEN
    MODE_TELEGRAM
    MODE_CRON
    MODE_CRON_FILE
    TELEGRAM_BOT_TOKEN
    TELEGRAM_CONFIG
    TELEGRAM_OVERRIDES
    WORKSPACE
    AVAILABLE_MODELS
    AVAILABLE_EFFORTS
    CRON_HISTORY_DIR
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

exec /usr/local/bin/aicodebox-entrypoint "$@"
