#!/bin/bash
# pibox entrypoint — thin wrapper around the aicodebox base entrypoint.
#
# Translates PIBOX_* env vars to their AICODEBOX_* equivalents so the
# image presents a pibox-branded surface to users. AICODEBOX_* still works
# (and wins if both are set) for power users and backwards compatibility.
set -euo pipefail

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

# aicodebox forwards OPENAI_API_KEY to the unprivileged agent process but not
# the pibox-specific token. The generic variable remains at the pibox boundary.
_pibox_has_custom_provider=false
if [[ -v PIBOX_PROVIDER_NAME || -v PIBOX_PROVIDER_API || -v PIBOX_PROVIDER_BASE_URL || -v PIBOX_PROVIDER_API_KEY || -v PIBOX_PROVIDER_MODEL ]]; then
	export OPENAI_API_KEY="${PIBOX_PROVIDER_API_KEY:-}"
	_pibox_has_custom_provider=true
fi

# Pi loads custom provider endpoints from ~/.pi/agent/models.json. Rebuild the
# managed entry at every boot so environment changes take effect even with a
# persisted home volume. Invalid configuration stops startup.
if [[ -x /opt/pibox/scripts/setup-provider-env.sh ]]; then
	sudo -E -u aicode -H bash /opt/pibox/scripts/setup-provider-env.sh
fi

_pibox_has_option() {
	local option="$1"
	shift
	local value

	for value in "$@"; do
		[[ "$value" == "$option" || "$value" == "$option="* ]] && return 0
	done
	return 1
}

# API, Telegram, and cron launches select the managed provider in PiAdapter.
# Interactive and one-shot launches call Pi directly, so add the same defaults
# unless the caller supplied a provider or model flag.
if ! _pibox_has_option "--provider" "$@"; then
	if [[ "$_pibox_has_custom_provider" == true ]]; then
		set -- --provider "${PIBOX_PROVIDER_NAME:-pibox}" "$@"
		if ! _pibox_has_option "--model" "$@"; then
			set -- --model "${PIBOX_PROVIDER_MODEL:-}" "$@"
		fi
	elif [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
		set -- --provider anthropic "$@"
		if [[ -n "${ANTHROPIC_MODEL:-}" ]] && ! _pibox_has_option "--model" "$@"; then
			set -- --model "$ANTHROPIC_MODEL" "$@"
		fi
	fi
fi

unset _pibox_has_custom_provider

exec /usr/local/bin/aicodebox-entrypoint "$@"
