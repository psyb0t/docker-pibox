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

    local payload='{
        "prompt": "Produce a JSON object where the word field is exactly the string HELLO.",
        "model": "'"$TEST_MODEL"'",
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

    local content
    content=$(echo "$resp" | jq -r '.text // .raw_stdout // empty' 2>/dev/null)
    if [ -z "$content" ]; then
        log "  FAIL: pi produced no content"
        log "  body: ${resp:0:500}"
        return 1
    fi

    # Strip accidental ```json fences before parsing.
    content=$(echo "$content" | sed -E 's/^[[:space:]]*```(json)?[[:space:]]*//; s/```[[:space:]]*$//' | tr -d '\r')

    if ! echo "$content" | jq -e '.word' >/dev/null 2>&1; then
        log "  FAIL: pi output is not valid JSON with .word"
        log "  content: ${content:0:300}"
        return 1
    fi

    local word
    word=$(echo "$content" | jq -r '.word')
    if [[ "${word^^}" != *"HELLO"* ]]; then
        log "  FAIL: pi .word=$word (expected HELLO)"
        return 1
    fi

    log "  OK: pi produced schema-valid JSON with word=$word"
    return 0
}
