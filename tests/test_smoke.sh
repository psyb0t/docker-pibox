#!/bin/bash
# Smoke tests: build verification + "say HELLO" round-trip via pi.
# Every invocation runs inside a fresh `docker run` — there is no host-side
# execution.

ALL_TESTS+=(
    test_build
    test_smoke_pi
    test_jsonschema_pi
)

# Image build is exercised by setup() in common.sh; this test just verifies
# the image exists and `pi --version` works through the entrypoint passthrough.
test_build() {
    local rc=0

    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        log "  FAIL: image $IMAGE not found"
        return 1
    fi
    log "  OK: image $IMAGE present"

    # Entrypoint passthrough: `docker run pibox:local --version` should invoke
    # `pi --version` and print pi's version string with rc=0.
    local out
    out=$(docker run --rm "$IMAGE" --version 2>&1)
    local pi_rc=$?
    if [ "$pi_rc" != "0" ]; then
        log "  FAIL: pi --version via entrypoint exited $pi_rc"
        log "  output: ${out:0:500}"
        return 1
    fi
    assert_not_empty "$out" "pi --version produced output" || rc=1

    return $rc
}

# HELLO round-trip through pi.
test_smoke_pi() {
    local prompt="Reply with exactly one word: HELLO. Nothing else."
    local out
    out=$(run_pi "$prompt" 2>&1) || {
        log "  FAIL: pi exited non-zero"
        log "  output: ${out:0:1000}"
        return 1
    }
    assert_contains "$out" "HELLO" "pi produced HELLO"
}

# ── json_schema smoke test ────────────────────────────────────────────────────
# Verifies pi can produce structured JSON output via the wrapper's
# prompt-injection fallback. Goes through the API mode so the wrapper's full
# post-processing runs.

test_jsonschema_pi() {
    local cname="${CONTAINER_PREFIX}-jsonschema-pi-$$"
    EXTRA_CONTAINERS+=("$cname")

    local port="${API_PORT_BASE:-19500}"
    local token="smoke-$$-$RANDOM"

    docker run -d --name "$cname" "${DOCKER_RUN_BASE[@]}" \
        -e "AICODEBOX_CONTAINER_NAME=$cname" \
        -e "AICODEBOX_API_MODE=1" \
        -e "AICODEBOX_API_MODE_PORT=$port" \
        -e "AICODEBOX_API_MODE_TOKEN=$token" \
        -e "AICODEBOX_AVAILABLE_MODELS=$TEST_MODEL" \
        -p "127.0.0.1:$port:$port" \
        "$IMAGE" >/dev/null

    local up=0
    for _ in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
            up=1
            break
        fi
        sleep 1
    done
    if [ "$up" != "1" ]; then
        log "  FAIL: pi API did not come up on port $port"
        docker logs "$cname" 2>&1 | tail -30 >&2
        docker rm -f "$cname" >/dev/null 2>&1 || true
        return 1
    fi

    # outputFormat=json + jsonSchema means: base parses .text as JSON,
    # validates against the schema, and retries up to 3 times if the model
    # produces malformed output. Success surfaces the decoded object under
    # .parsed (no .text in the response). v0.4.0 contract.
    local payload='{
        "prompt": "Produce a JSON object where the word field is exactly the string HELLO.",
        "model": "'"$TEST_MODEL"'",
        "outputFormat": "json",
        "extra_args": ["--provider", "anthropic"],
        "jsonSchema": {
            "type": "object",
            "properties": {"word": {"type": "string"}},
            "required": ["word"]
        }
    }'

    local resp
    resp=$(curl -sf -X POST -H "Authorization: Bearer $token" \
             -H "Content-Type: application/json" \
             -d "$payload" "http://127.0.0.1:$port/run" 2>&1)
    local curl_rc=$?
    docker rm -f "$cname" >/dev/null 2>&1 || true

    if [ "$curl_rc" -ne 0 ]; then
        log "  FAIL: pi curl exited $curl_rc"
        log "  body: ${resp:0:500}"
        return 1
    fi

    if ! echo "$resp" | jq -e '.parsed.word' >/dev/null 2>&1; then
        log "  FAIL: pi response missing .parsed.word"
        log "  body: ${resp:0:500}"
        return 1
    fi

    local word
    word=$(echo "$resp" | jq -r '.parsed.word')
    if [[ "${word^^}" != *"HELLO"* ]]; then
        log "  FAIL: pi .word=$word (expected HELLO)"
        return 1
    fi

    log "  OK: pi produced schema-valid JSON with word=$word"
    return 0
}
