#!/bin/bash
# Configure Pi custom HTTP providers from pibox environment variables.
#
# PIBOX_PROVIDER_* supports Pi's documented custom HTTP APIs. ANTHROPIC_*
# remains a compatibility shortcut for existing Anthropic-compatible setups.
set -euo pipefail

readonly PI_DIR="$HOME/.pi/agent"
readonly MODELS_FILE="$PI_DIR/models.json"
readonly PROVIDER_STATE_FILE="$PI_DIR/pibox-provider.json"
readonly LOG_FILE="${LOG_FILE:-/tmp/pibox-provider-setup.log}"
readonly DEFAULT_PROVIDER_NAME="pibox"
readonly DEFAULT_PROVIDER_API="openai-completions"
readonly ANTHROPIC_PROVIDER_API="anthropic-messages"
readonly PROVIDER_KEY_REFERENCE="\$OPENAI_API_KEY"
readonly MAX_PROVIDER_NAME_LENGTH=64
readonly MAX_MODEL_ID_LENGTH=256
readonly MAX_URL_LENGTH=2048
readonly MAX_API_KEY_LENGTH=4096
readonly DEFAULT_CONTEXT_WINDOW=128000
readonly DEFAULT_MAX_TOKENS=16384
readonly MODEL_ID_SEPARATOR=","

log() {
	local level="$1"
	shift
	local timestamp
	local source_file
	local source_line
	local source_function

	timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
	source_file="${BASH_SOURCE[1]##*/}"
	source_line="${BASH_LINENO[0]}"
	source_function="${FUNCNAME[1]:-main}"
	jq -cn \
		--arg time "$timestamp" \
		--arg level "$level" \
		--arg file "$source_file" \
		--argjson line "$source_line" \
		--arg func "$source_function" \
		--arg msg "$*" \
		'$ARGS.named' >&2
}

on_error() {
	local exit_code="$?"

	log ERROR "provider setup failed"
	exit "$exit_code"
}

trap on_error ERR
exec > >(tee -a "$LOG_FILE") 2>&1

fail() {
	log ERROR "$1"
	exit 1
}

has_custom_provider_config() {
	[[ -v PIBOX_PROVIDER_NAME || -v PIBOX_PROVIDER_API || -v PIBOX_PROVIDER_BASE_URL || -v PIBOX_PROVIDER_API_KEY || -v PIBOX_PROVIDER_MODEL ]]
}

validate_single_line() {
	local value="$1"
	local label="$2"
	local max_length="$3"

	[[ -n "$value" ]] || fail "$label is required"
	[[ "${#value}" -le "$max_length" ]] || fail "$label exceeds $max_length characters"
	[[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "$label must be a single line"
}

validate_provider_name() {
	local provider_name="$1"

	validate_single_line "$provider_name" "PIBOX_PROVIDER_NAME" "$MAX_PROVIDER_NAME_LENGTH"
	[[ "$provider_name" =~ ^[a-z][a-z0-9-]*$ ]] || fail "PIBOX_PROVIDER_NAME must match ^[a-z][a-z0-9-]*$"
}

validate_base_url() {
	local base_url="$1"

	validate_single_line "$base_url" "PIBOX_PROVIDER_BASE_URL" "$MAX_URL_LENGTH"
	[[ "$base_url" =~ ^https?://[^[:space:]]+$ ]] || fail "PIBOX_PROVIDER_BASE_URL must be an http or https URL without whitespace"
}

validate_provider_api() {
	local provider_api="$1"

	case "$provider_api" in
	openai-completions | openai-responses | anthropic-messages | google-generative-ai) ;;
	*)
		fail "PIBOX_PROVIDER_API must be openai-completions, openai-responses, anthropic-messages, or google-generative-ai"
		;;
	esac
}

advertised_model_ids() {
	printf '%s' "${AICODEBOX_AVAILABLE_MODELS:-${PIBOX_AVAILABLE_MODELS:-}}"
}

trim_whitespace() {
	local value="$1"

	value="${value#"${value%%[![:space:]]*}"}"
	printf '%s' "${value%"${value##*[![:space:]]}"}"
}

# Pi resolves a model against the provider's own model list. A model that is
# advertised to callers but missing from that list falls back to Pi's default
# API shape, which then disagrees with the provider's baseUrl and surfaces at
# request time as "Stream ended without finish_reason" rather than as a
# configuration error. Collect the primary model plus everything in
# AVAILABLE_MODELS so every reachable model id is declared.
collect_model_ids() {
	local primary_model_id="$1"
	local -a candidate_ids=()
	local -a model_ids=()
	local candidate
	local registered

	IFS="$MODEL_ID_SEPARATOR" read -r -a candidate_ids <<<"$(advertised_model_ids)"

	for candidate in "$primary_model_id" ${candidate_ids[@]+"${candidate_ids[@]}"}; do
		candidate="$(trim_whitespace "$candidate")"
		[[ -n "$candidate" ]] || continue
		validate_single_line "$candidate" "model id '$candidate'" "$MAX_MODEL_ID_LENGTH"

		for registered in ${model_ids[@]+"${model_ids[@]}"}; do
			[[ "$registered" != "$candidate" ]] || continue 2
		done

		model_ids+=("$candidate")
	done

	# printf with no arguments would still emit one empty line, which the
	# caller would read back as a model with an empty id.
	[[ "${#model_ids[@]}" -gt 0 ]] || return 0
	printf '%s\n' "${model_ids[@]}"
}

build_models_json() {
	local provider_api="$1"
	shift

	[[ "$#" -gt 0 ]] || {
		printf '[]'
		return 0
	}

	jq -n \
		--arg api "$provider_api" \
		--argjson context_window "$DEFAULT_CONTEXT_WINDOW" \
		--argjson max_tokens "$DEFAULT_MAX_TOKENS" \
		'$ARGS.positional | map({
            id: .,
            name: .,
            api: $api,
            input: ["text"],
            contextWindow: $context_window,
            maxTokens: $max_tokens
        })' \
		--args "$@"
}

# An OpenAI-shaped request sent to an Anthropic-shaped endpoint (or the
# reverse) fails as a truncated stream with no usable diagnostic. The path
# marker is a hint rather than a contract, so a contradiction is reported and
# startup continues.
warn_on_api_base_url_mismatch() {
	local provider_api="$1"
	local base_url="$2"

	if [[ "$base_url" == *"/anthropic"* && "$provider_api" != "$ANTHROPIC_PROVIDER_API" ]]; then
		log WARN "base URL looks Anthropic-shaped but provider API is $provider_api reason=provider_api_base_url_mismatch"
		return 0
	fi

	if [[ "$base_url" != *"/anthropic"* && "$provider_api" == "$ANTHROPIC_PROVIDER_API" && "$base_url" == *"/v"[0-9]* ]]; then
		log WARN "base URL looks OpenAI-shaped but provider API is $provider_api reason=provider_api_base_url_mismatch"
	fi
}

write_provider() {
	local provider_name="$1"
	local provider_config="$2"
	local temporary_models_file

	[[ ! -L "$MODELS_FILE" ]] || fail "refusing symlinked models.json"
	[[ ! -e "$MODELS_FILE" || -f "$MODELS_FILE" ]] || fail "models.json must be a regular file"

	temporary_models_file="$(mktemp "$PI_DIR/models.json.XXXXXX")"
	if [[ -f "$MODELS_FILE" ]]; then
		jq --arg provider "$provider_name" --argjson config "$provider_config" \
			'.providers = ((.providers // {}) | .[$provider] = $config)' \
			"$MODELS_FILE" >"$temporary_models_file" ||
			fail "models.json is not valid provider configuration"
	else
		jq -n --arg provider "$provider_name" --argjson config "$provider_config" \
			'{providers: {($provider): $config}}' >"$temporary_models_file" ||
			fail "could not build provider configuration"
	fi

	chmod 600 "$temporary_models_file"
	mv -- "$temporary_models_file" "$MODELS_FILE"
}

remove_previous_custom_provider() {
	local previous_name
	local temporary_models_file

	[[ -e "$PROVIDER_STATE_FILE" ]] || return 0
	[[ ! -L "$PROVIDER_STATE_FILE" ]] || fail "refusing symlinked pibox provider state"
	[[ -f "$PROVIDER_STATE_FILE" ]] || fail "pibox provider state must be a regular file"
	[[ -s "$PROVIDER_STATE_FILE" ]] || return

	previous_name="$(jq -r 'select(.managedBy == "pibox") | .provider // empty' "$PROVIDER_STATE_FILE")" ||
		fail "pibox provider state is invalid"
	[[ -n "$previous_name" ]] || return
	validate_provider_name "$previous_name"

	if [[ -f "$MODELS_FILE" ]]; then
		[[ ! -L "$MODELS_FILE" ]] || fail "refusing symlinked models.json"
		temporary_models_file="$(mktemp "$PI_DIR/models.json.XXXXXX")"
		jq --arg provider "$previous_name" 'del(.providers[$provider])' "$MODELS_FILE" \
			>"$temporary_models_file" ||
			fail "models.json is not valid provider configuration"
		chmod 600 "$temporary_models_file"
		mv -- "$temporary_models_file" "$MODELS_FILE"
	fi

	rm -- "$PROVIDER_STATE_FILE"
}

write_custom_provider_state() {
	local provider_name="$1"
	local model_id="$2"
	local temporary_state_file

	temporary_state_file="$(mktemp "$PI_DIR/pibox-provider.json.XXXXXX")"
	jq -n --arg provider "$provider_name" --arg model "$model_id" \
		'{managedBy: "pibox", provider: $provider, model: $model}' \
		>"$temporary_state_file"
	chmod 600 "$temporary_state_file"
	mv -- "$temporary_state_file" "$PROVIDER_STATE_FILE"
}

configure_custom_provider() {
	local provider_name="${PIBOX_PROVIDER_NAME:-$DEFAULT_PROVIDER_NAME}"
	local provider_api="${PIBOX_PROVIDER_API:-$DEFAULT_PROVIDER_API}"
	local base_url="${PIBOX_PROVIDER_BASE_URL:-}"
	local api_key="${PIBOX_PROVIDER_API_KEY:-}"
	local model_id="${PIBOX_PROVIDER_MODEL:-}"
	local -a model_ids=()
	local models_json
	local provider_config

	[[ -z "${ANTHROPIC_BASE_URL:-}" ]] || fail "PIBOX_PROVIDER_* cannot be combined with ANTHROPIC_BASE_URL"
	validate_provider_name "$provider_name"
	validate_provider_api "$provider_api"
	validate_base_url "$base_url"
	validate_single_line "$api_key" "PIBOX_PROVIDER_API_KEY" "$MAX_API_KEY_LENGTH"
	validate_single_line "$model_id" "PIBOX_PROVIDER_MODEL" "$MAX_MODEL_ID_LENGTH"
	warn_on_api_base_url_mismatch "$provider_api" "$base_url"

	readarray -t model_ids < <(collect_model_ids "$model_id")
	models_json="$(build_models_json "$provider_api" "${model_ids[@]}")"
	log INFO "registering ${#model_ids[@]} model(s) for provider $provider_name api=$provider_api"

	provider_config="$(jq -n \
		--arg base "$base_url" \
		--arg api "$provider_api" \
		--arg key "$PROVIDER_KEY_REFERENCE" \
		--argjson models "$models_json" '
        {
            baseUrl: $base,
            api: $api,
            apiKey: $key,
            models: $models
        }
    ')"

	remove_previous_custom_provider
	write_provider "$provider_name" "$provider_config"
	write_custom_provider_state "$provider_name" "$model_id"
	log INFO "configured generic upstream provider"
}

configure_anthropic_compatibility() {
	local api_key_value
	local model_id="${ANTHROPIC_MODEL:-}"
	local -a model_ids=()
	local models_json
	local provider_config

	[[ -n "${ANTHROPIC_BASE_URL:-}" ]] || return 0

	if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
		api_key_value="$ANTHROPIC_AUTH_TOKEN"
	elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
		api_key_value="$ANTHROPIC_API_KEY"
	else
		fail "ANTHROPIC_AUTH_TOKEN or ANTHROPIC_API_KEY is required when ANTHROPIC_BASE_URL is set"
	fi

	validate_base_url "$ANTHROPIC_BASE_URL"
	[[ -z "$model_id" ]] || validate_single_line "$model_id" "ANTHROPIC_MODEL" "$MAX_MODEL_ID_LENGTH"

	readarray -t model_ids < <(collect_model_ids "$model_id")
	models_json="$(build_models_json "$ANTHROPIC_PROVIDER_API" ${model_ids[@]+"${model_ids[@]}"})"
	log INFO "registering ${#model_ids[@]} model(s) for provider anthropic api=$ANTHROPIC_PROVIDER_API"

	provider_config="$(jq -n \
		--arg base "$ANTHROPIC_BASE_URL" \
		--arg api "$ANTHROPIC_PROVIDER_API" \
		--arg key "$api_key_value" \
		--argjson models "$models_json" '
        {
            baseUrl: $base,
            api: $api,
            apiKey: $key,
            models: $models
        }
    ')"
	write_provider "anthropic" "$provider_config"
	log INFO "configured Anthropic-compatible upstream provider"
}

mkdir -p "$PI_DIR"

if has_custom_provider_config; then
	configure_custom_provider
	exit 0
fi

remove_previous_custom_provider
configure_anthropic_compatibility
