#!/bin/bash
# Live generic-provider regressions for Z.AI Coding Plan endpoints.
#
# The token is sourced from the ignored .env.test file. A coding-specific
# token, model, and endpoint can override the documented defaults there.

readonly ZAI_CODING_ANTHROPIC_API="anthropic-messages"
readonly ZAI_CODING_OPENAI_API="openai-completions"
readonly PROVIDER_API_KEY_ENV_REFERENCE="\$OPENAI_API_KEY"
readonly ZAI_CODING_AUTH_TOKEN="${ZAI_CODING_AUTH_TOKEN:-$ANTHROPIC_AUTH_TOKEN}"
readonly ZAI_CODING_ANTHROPIC_BASE_URL="${ZAI_CODING_ANTHROPIC_BASE_URL:-https://api.z.ai/api/anthropic}"
readonly ZAI_CODING_OPENAI_BASE_URL="${ZAI_CODING_OPENAI_BASE_URL:-https://api.z.ai/api/coding/paas/v4}"
readonly ZAI_CODING_MODEL="${ZAI_CODING_MODEL:-glm-5.3-flash}"

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
)
