#!/bin/bash
# Live generic-provider regressions for Z.AI Coding Plan endpoints.
#
# The token is sourced from the ignored .env.test file. A coding-specific
# token, model, and endpoint can override the documented defaults there.

readonly ANTHROPIC_MESSAGES_API="anthropic-messages"
readonly OPENAI_COMPLETIONS_API="openai-completions"
readonly ZAI_CODING_ANTHROPIC_API="$ANTHROPIC_MESSAGES_API"
readonly ZAI_CODING_OPENAI_API="$OPENAI_COMPLETIONS_API"
readonly PROVIDER_API_KEY_ENV_REFERENCE="\$OPENAI_API_KEY"
readonly ZAI_CODING_AUTH_TOKEN="${ZAI_CODING_AUTH_TOKEN:-$ANTHROPIC_AUTH_TOKEN}"
readonly ZAI_CODING_ANTHROPIC_BASE_URL="${ZAI_CODING_ANTHROPIC_BASE_URL:-https://api.z.ai/api/anthropic}"
readonly ZAI_CODING_OPENAI_BASE_URL="${ZAI_CODING_OPENAI_BASE_URL:-https://api.z.ai/api/coding/paas/v4}"
readonly ZAI_CODING_MODEL="${ZAI_CODING_MODEL:-glm-5.3-flash}"
readonly ZAI_CODING_SECONDARY_MODEL="${ZAI_CODING_SECONDARY_MODEL:-glm-5.3}"
readonly LITELLM_MODEL="${LITELLM_MODEL:-groq-qwen3.8-27b}"
readonly LITELLM_SECONDARY_MODEL="${LITELLM_SECONDARY_MODEL:-groq-gpt-oss-20b}"

_assert_generic_provider() {
	local expected_api="$1"
	local models_json provider_api provider_key provider_model state_model advertised_models

	models_json=$(docker exec "$API_CONTAINER" cat /home/aicode/.pi/agent/models.json 2>/dev/null)
	assert_not_empty "$models_json" "generic provider models.json exists" || return 1

	provider_api=$(echo "$models_json" | jq -r --arg provider "$TEST_PROVIDER_NAME" '.providers[$provider].api')
	assert_eq "$provider_api" "$expected_api" "generic provider API is $expected_api" || return 1

	provider_key=$(echo "$models_json" | jq -r --arg provider "$TEST_PROVIDER_NAME" '.providers[$provider].apiKey')
	assert_eq "$provider_key" "$PROVIDER_API_KEY_ENV_REFERENCE" "generic provider key stays an environment reference" || return 1

	provider_model=$(echo "$models_json" | jq -r --arg provider "$TEST_PROVIDER_NAME" '.providers[$provider].models[0].id')
	assert_eq "$provider_model" "$ZAI_CODING_MODEL" "generic provider model is configured" || return 1

	state_model=$(docker exec "$API_CONTAINER" jq -r '.model' /home/aicode/.pi/agent/pibox-provider.json 2>/dev/null)
	assert_eq "$state_model" "$ZAI_CODING_MODEL" "generic provider state selects the model" || return 1

	advertised_models=$(_curl_auth -m 5 "$API_URL/openai/v1/models")
	assert_contains "$advertised_models" "\"id\":\"$ZAI_CODING_MODEL\"" "API advertises the generic provider model"
}

_assert_generic_provider_completion() {
	local body

	body=$(_curl_auth -m 120 -X POST "$API_URL/run" \
		-H "Content-Type: application/json" \
		-d '{"prompt":"Reply with exactly one word: PONG. Nothing else."}')
	assert_contains "$body" "PONG" "generic provider returned a live completion"
}

# Every advertised model must be registered against the provider's own API.
# A model that reached Pi without a registration fell back to Pi's default
# API shape, disagreed with the provider baseUrl, and failed every request
# with "Stream ended without finish_reason".
_assert_registered_models() {
	local expected_api="$1"
	shift
	local models_json registered_api model_id

	models_json=$(docker exec "$API_CONTAINER" cat /home/aicode/.pi/agent/models.json 2>/dev/null)
	assert_not_empty "$models_json" "generic provider models.json exists" || return 1

	for model_id in "$@"; do
		registered_api=$(echo "$models_json" | jq -r \
			--arg provider "$TEST_PROVIDER_NAME" --arg id "$model_id" \
			'.providers[$provider].models[] | select(.id == $id) | .api')
		assert_eq "$registered_api" "$expected_api" "model $model_id registered with api $expected_api" || return 1
	done
}

# Assert the whole OpenAI Chat Completions contract, not just that some text
# came back. A provider misconfiguration can still return 200 with an empty
# choice, so the model echo, finish reason, content, and usage all matter.
_assert_model_completion() {
	local model_id="$1"
	local body object echoed_model finish_reason role content total_tokens

	body=$(_curl_auth -m 180 -X POST "$API_URL/openai/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d "{\"model\":\"$model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly one word: PONG. Nothing else.\"}]}")
	assert_not_empty "$body" "$model_id returned a response body" || return 1

	object=$(echo "$body" | jq -r '.object // empty')
	assert_eq "$object" "chat.completion" "$model_id response object is chat.completion" || return 1

	echoed_model=$(echo "$body" | jq -r '.model // empty')
	assert_eq "$echoed_model" "$model_id" "$model_id response echoes the requested model" || return 1

	role=$(echo "$body" | jq -r '.choices[0].message.role // empty')
	assert_eq "$role" "assistant" "$model_id response message role is assistant" || return 1

	finish_reason=$(echo "$body" | jq -r '.choices[0].finish_reason // empty')
	assert_eq "$finish_reason" "stop" "$model_id response finish_reason is stop" || return 1

	content=$(echo "$body" | jq -r '.choices[0].message.content // empty')
	assert_contains "$content" "PONG" "$model_id returned a live completion" || return 1

	total_tokens=$(echo "$body" | jq -r '.usage.total_tokens // 0')
	assert_eq "$([ "$total_tokens" -gt 0 ] && echo yes || echo no)" "yes" \
		"$model_id response reports token usage"
}

_assert_advertised_secondary_model() {
	local provider_api="$1"
	local base_url="$2"

	_api_start "" "$provider_api" "$base_url" "$ZAI_CODING_AUTH_TOKEN" \
		"$ZAI_CODING_MODEL" "$ZAI_CODING_MODEL,$ZAI_CODING_SECONDARY_MODEL" || return 1
	_assert_registered_models "$provider_api" "$ZAI_CODING_MODEL" "$ZAI_CODING_SECONDARY_MODEL" || return 1
	_assert_model_completion "$ZAI_CODING_SECONDARY_MODEL"
}

test_provider_env_secondary_model_anthropic_messages() {
	_assert_advertised_secondary_model "$ZAI_CODING_ANTHROPIC_API" "$ZAI_CODING_ANTHROPIC_BASE_URL"
}

test_provider_env_secondary_model_openai_completions() {
	_assert_advertised_secondary_model "$ZAI_CODING_OPENAI_API" "$ZAI_CODING_OPENAI_BASE_URL"
}

# A LiteLLM gateway is an OpenAI Chat Completions upstream that fronts many
# vendors, so one provider entry serves model ids that belong to different
# backends. Every advertised id must still resolve.
test_provider_env_litellm_openai_completions() {
	if [ -z "${LITELLM_BASE_URL:-}" ] || [ -z "${LITELLM_API_KEY:-}" ]; then
		log "  SKIP: LITELLM_BASE_URL and LITELLM_API_KEY are unset in .env.test"
		return 0
	fi

	_api_start "" "$OPENAI_COMPLETIONS_API" "$LITELLM_BASE_URL/v1" "$LITELLM_API_KEY" \
		"$LITELLM_MODEL" "$LITELLM_MODEL,$LITELLM_SECONDARY_MODEL" || return 1
	_assert_registered_models "$OPENAI_COMPLETIONS_API" "$LITELLM_MODEL" "$LITELLM_SECONDARY_MODEL" || return 1
	_assert_model_completion "$LITELLM_MODEL" || return 1
	_assert_model_completion "$LITELLM_SECONDARY_MODEL"
}

test_provider_env_zai_coding_anthropic_messages() {
	_api_start "" "$ZAI_CODING_ANTHROPIC_API" "$ZAI_CODING_ANTHROPIC_BASE_URL" "$ZAI_CODING_AUTH_TOKEN" "$ZAI_CODING_MODEL" || return 1
	_assert_generic_provider "$ZAI_CODING_ANTHROPIC_API" || return 1
	_assert_generic_provider_completion
}

test_provider_env_zai_coding_openai_completions() {
	_api_start "" "$ZAI_CODING_OPENAI_API" "$ZAI_CODING_OPENAI_BASE_URL" "$ZAI_CODING_AUTH_TOKEN" "$ZAI_CODING_MODEL" || return 1
	_assert_generic_provider "$ZAI_CODING_OPENAI_API" || return 1
	_assert_generic_provider_completion
}

ALL_TESTS+=(
	test_provider_env_zai_coding_anthropic_messages
	test_provider_env_zai_coding_openai_completions
	test_provider_env_secondary_model_anthropic_messages
	test_provider_env_secondary_model_openai_completions
	test_provider_env_litellm_openai_completions
)
