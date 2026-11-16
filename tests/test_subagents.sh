#!/bin/bash
# Model limits and the bundled subagent extension.
#
# The limit tests only read the files startup writes. The subagent test makes
# a live Z.AI Coding Plan call through the generic provider.

readonly SUBAGENT_TEST_MODEL="${ZAI_CODING_MODEL:-glm-5.3-flash}"
readonly SUBAGENT_TEST_BASE_URL="${ZAI_CODING_OPENAI_BASE_URL:-https://api.z.ai/api/coding/paas/v4}"
readonly SUBAGENT_TEST_TOKEN="${ZAI_CODING_AUTH_TOKEN:-$ANTHROPIC_AUTH_TOKEN}"
readonly UNKNOWN_MODEL_ID="example-model"

# Run the startup scripts the entrypoint and the base run, as aicode, then
# print one file from the aicode Pi directory. Extra docker args come first.
# The entrypoint itself would hand any argument to Pi as a prompt.
_startup_file() {
    local file="$1"
    shift
    local cname="${CONTAINER_PREFIX}-startup-$RANDOM"

    EXTRA_CONTAINERS+=("$cname")
    docker run --name "$cname" --rm \
        -e "PIBOX_PROVIDER_NAME=$TEST_PROVIDER_NAME" \
        -e "PIBOX_PROVIDER_BASE_URL=$SUBAGENT_TEST_BASE_URL" \
        -e "PIBOX_PROVIDER_API_KEY=EXAMPLE-DO-NOT-USE" \
        -e "PIBOX_PROVIDER_MODEL=$SUBAGENT_TEST_MODEL" \
        -e "PIBOX_AVAILABLE_MODELS=$SUBAGENT_TEST_MODEL,$UNKNOWN_MODEL_ID" \
        "$@" \
        --entrypoint bash "$IMAGE" -c \
        'run() { sudo -E -u aicode -H bash "$@" >/dev/null 2>&1; }
        run /opt/pibox/scripts/setup-provider-env.sh || exit 1
        run /opt/pibox/scripts/setup-subagents.sh || exit 1
        run /aicodebox-init.d/10-pi-extensions.sh || exit 1
        cat "/home/aicode/.pi/agent/$1"' \
        _ "$file"
}

_model_field() {
    local models_json="$1"
    local model_id="$2"
    local field="$3"

    echo "$models_json" | jq -r --arg p "$TEST_PROVIDER_NAME" --arg id "$model_id" --arg f "$field" \
        '.providers[$p].models[] | select(.id == $id) | .[$f]'
}

test_model_limits_from_catalog() {
    local models_json

    models_json=$(_startup_file models.json)
    assert_not_empty "$models_json" "models.json written" || return 1

    assert_eq "$(_model_field "$models_json" "$SUBAGENT_TEST_MODEL" reasoning)" "true" \
        "catalog model is registered as reasoning" || return 1
    assert_eq "$(_model_field "$models_json" "$SUBAGENT_TEST_MODEL" maxTokens)" "131072" \
        "catalog model takes the catalog output limit" || return 1
    assert_eq "$(_model_field "$models_json" "$SUBAGENT_TEST_MODEL" contextWindow)" "1000000" \
        "catalog model takes the catalog context window" || return 1

    assert_eq "$(_model_field "$models_json" "$UNKNOWN_MODEL_ID" maxTokens)" "16384" \
        "unknown model keeps the default output limit" || return 1
    assert_eq "$(_model_field "$models_json" "$UNKNOWN_MODEL_ID" reasoning)" "false" \
        "unknown model keeps reasoning off"
}

test_model_limits_env_override() {
    local models_json model_id

    models_json=$(_startup_file models.json \
        -e PIBOX_MODEL_MAX_TOKENS=32000 \
        -e PIBOX_MODEL_CONTEXT_WINDOW=200000 \
        -e PIBOX_MODEL_REASONING=false)
    assert_not_empty "$models_json" "models.json written" || return 1

    for model_id in "$SUBAGENT_TEST_MODEL" "$UNKNOWN_MODEL_ID"; do
        assert_eq "$(_model_field "$models_json" "$model_id" maxTokens)" "32000" \
            "$model_id output limit from PIBOX_MODEL_MAX_TOKENS" || return 1
        assert_eq "$(_model_field "$models_json" "$model_id" contextWindow)" "200000" \
            "$model_id context window from PIBOX_MODEL_CONTEXT_WINDOW" || return 1
        assert_eq "$(_model_field "$models_json" "$model_id" reasoning)" "false" \
            "$model_id reasoning from PIBOX_MODEL_REASONING" || return 1
    done
}

test_model_limits_reject_invalid() {
    local output

    output=$(_startup_file models.json -e PIBOX_MODEL_MAX_TOKENS=lots)
    assert_eq "$?" "1" "invalid PIBOX_MODEL_MAX_TOKENS stops startup" || return 1
    assert_eq "$output" "" "no models.json printed after invalid limits"
}

test_subagents_disabled_by_default() {
    local settings

    settings=$(_startup_file settings.json)
    assert_not_empty "$settings" "settings.json written" || return 1
    assert_eq "$(echo "$settings" | jq -r '.extensions | map(select(endswith("/subagent/index.ts"))) | length')" "0" \
        "subagent extension is not registered by default"
}

test_subagents_config_written() {
    local settings limits output

    settings=$(_startup_file settings.json -e PIBOX_SUBAGENTS=true)
    assert_eq "$(echo "$settings" | jq -r '.extensions | map(select(endswith("/subagent/index.ts"))) | length')" "1" \
        "PIBOX_SUBAGENTS=true registers the subagent extension" || return 1
    assert_eq "$(echo "$settings" | jq -r '.extensions | map(select(endswith("/mcp-bridge/index.ts"))) | length')" "1" \
        "the MCP bridge stays registered" || return 1

    limits=$(_startup_file pibox-subagent.json -e PIBOX_SUBAGENTS=true \
        -e PIBOX_SUBAGENT_MAX_TASKS=12 -e PIBOX_SUBAGENT_MAX_CONCURRENCY=6 -e PIBOX_SUBAGENT_THINKING=high)
    assert_eq "$(echo "$limits" | jq -c .)" '{"maxTasks":12,"maxConcurrency":6,"thinking":"high"}' \
        "subagent limits written from PIBOX_SUBAGENT_*" || return 1

    output=$(_startup_file pibox-subagent.json -e PIBOX_SUBAGENTS=true -e PIBOX_SUBAGENT_THINKING=extreme)
    assert_eq "$?" "1" "invalid PIBOX_SUBAGENT_THINKING stops startup"
}

# A model-pinned agent from PIBOX_AGENTS_DIR runs through the subagent tool,
# and its child process gets PIBOX_SUBAGENT_THINKING although the parent runs
# with thinking off.
test_subagents_live_pinned_model() {
    local agents_dir="$WORKDIR/.testing/e2e-agents-$$"
    local cname="${CONTAINER_PREFIX}-subagent"
    local output reply child_thinking

    mkdir -p "$agents_dir"
    cat >"$agents_dir/echoer.md" <<EOF
---
name: echoer
description: Replies with the word it is given, in uppercase
tools: read
model: $TEST_PROVIDER_NAME/$SUBAGENT_TEST_MODEL
---
Reply with exactly the word given in the task, in uppercase, nothing else.
EOF

    EXTRA_CONTAINERS+=("$cname")
    output=$(docker run --name "$cname" --rm --network host \
        -e "PIBOX_PROVIDER_NAME=$TEST_PROVIDER_NAME" \
        -e "PIBOX_PROVIDER_BASE_URL=$SUBAGENT_TEST_BASE_URL" \
        -e "PIBOX_PROVIDER_API_KEY=$SUBAGENT_TEST_TOKEN" \
        -e "PIBOX_PROVIDER_MODEL=$SUBAGENT_TEST_MODEL" \
        -e PIBOX_SUBAGENTS=true \
        -e PIBOX_SUBAGENT_THINKING=low \
        -e PIBOX_AGENTS_DIR=/agents \
        -v "$agents_dir:/agents:ro" \
        "$IMAGE" -p --mode json --thinking off \
        "Use the subagent tool to run agent echoer with task: banana. Then reply with exactly what it returned." \
        2>/dev/null)
    rm -rf "$agents_dir"

    reply=$(echo "$output" | jq -r 'select(.type == "tool_execution_end" and .toolName == "subagent") | .result.content[0].text // empty' 2>/dev/null)
    assert_contains "$reply" "BANANA" "subagent tool ran the linked agent" || return 1

    child_thinking=$(echo "$output" | jq -r 'select(.type == "tool_execution_end" and .toolName == "subagent")
        | .result.details.results[0].messages[] | select(.role == "assistant") | .thinkingLevel' 2>/dev/null | head -1)
    assert_eq "$child_thinking" "low" "model-pinned subagent runs at PIBOX_SUBAGENT_THINKING"
}

ALL_TESTS+=(
    test_model_limits_from_catalog
    test_model_limits_env_override
    test_model_limits_reject_invalid
    test_subagents_disabled_by_default
    test_subagents_config_written
    test_subagents_live_pinned_model
)
