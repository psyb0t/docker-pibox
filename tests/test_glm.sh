#!/bin/bash
# GLM / Anthropic-provider auth regression tests.
#
# Guards the bug where scripts/setup-anthropic-baseurl.sh wrote the env-var NAME
# ("ANTHROPIC_AUTH_TOKEN") into pi's models.json instead of the resolved token
# VALUE. pi >= 0.84.0 sends the provider apiKey literally, so the name 401s
# upstream and no real completion comes back — which is how the v0.15.10 pi bump
# (0.75.3 -> 0.84.0) silently broke GLM. Two guards:
#   1. the on-disk apiKey is the resolved token, not the bare variable name
#   2. a real GLM completion comes back end-to-end (proves the token auth'd)
#
# Reuses _api_start / _curl_auth from test_api.sh (test.sh sources every
# tests/test_*.sh into one shell before running, so they are available here).

# The provider apiKey pi writes must be the resolved token VALUE, not the name.
# Deterministic and offline — asserts the fix without depending on z.ai.
test_glm_provider_apikey_is_the_resolved_value() {
    _api_start "glm-regression-$$" || return 1

    local models_json apikey
    models_json=$(docker exec "$API_CONTAINER" \
        cat /home/aicode/.pi/agent/models.json 2>/dev/null)
    assert_not_empty "$models_json" "models.json exists in the container" || return 1

    apikey=$(echo "$models_json" | jq -r '.providers.anthropic.apiKey')

    # The exact regression: the bare env-var NAME leaked in instead of the value.
    # Compared to a NAME/not-name token so the real secret is never logged.
    assert_eq \
        "$([ "$apikey" = "ANTHROPIC_AUTH_TOKEN" ] && echo is-the-name || echo not-the-name)" \
        "not-the-name" \
        "models.json apiKey is NOT the bare env-var name" || return 1

    # And it IS the resolved token — compared directly, but the value is never
    # printed (only a redacted pass/fail).
    if [ "$apikey" = "$ANTHROPIC_AUTH_TOKEN" ]; then
        log "  OK: models.json apiKey is the resolved token value (redacted)"
        return 0
    fi
    log "  FAIL: models.json apiKey does not match the provided token (redacted)"
    return 1
}

# A real completion must come back from GLM — proves the token actually
# authenticated upstream (a 401 from the name-bug yields no PONG).
test_glm_completion_reaches_real_glm() {
    _api_start "glm-regression-$$" || return 1

    local body
    body=$(_curl_auth -m 120 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with exactly one word: PONG. Nothing else."}')
    assert_contains "$body" "PONG" \
        "GLM /run returned a real completion (token auth'd upstream)"
}

ALL_TESTS+=(
    test_glm_provider_apikey_is_the_resolved_value
    test_glm_completion_reaches_real_glm
)
