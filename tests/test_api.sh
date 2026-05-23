#!/bin/bash
# Phase-1 API mode tests. One detached container, then a series of curl
# assertions against its HTTP API. Container + curl all in docker.

# Pick a random high-numbered port; verify it's free against /proc/net/tcp*.
_api_pick_port() {
    local p hex i
    for i in $(seq 1 30); do
        p=$(( 18000 + RANDOM % 30000 ))
        hex=$(printf ':%04X' "$p")
        if ! grep -qiE "$hex " /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
            echo "$p"
            return 0
        fi
    done
    echo "$p"
}

# ── helpers ───────────────────────────────────────────────────────────────────

_api_container_name() {
    echo "${CONTAINER_PREFIX}-api-$$-$RANDOM"
}

# Start an API container. Sets $API_URL, $API_TOKEN, $API_CONTAINER.
# Args: [token]
_api_start() {
    local token="${1:-}"
    local cname
    cname=$(_api_container_name)
    local port
    port=$(_api_pick_port)

    local extra=()
    if [ -n "$token" ]; then
        extra+=(-e "AICODEBOX_API_MODE_TOKEN=$token")
        # Share the same bearer with MCP for these tests — keeps curl one-token.
        extra+=(-e "AICODEBOX_MCP_MODE_TOKEN=$token")
    fi

    docker rm -f "$cname" >/dev/null 2>&1 || true
    docker run -d --name "$cname" \
        --network host \
        -e "AICODEBOX_API_MODE=1" \
        -e "AICODEBOX_API_MODE_PORT=$port" \
        -e "AICODEBOX_MCP_MODE=1" \
        -e "AICODEBOX_AVAILABLE_MODELS=$TEST_MODEL" \
        -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
        -e "ANTHROPIC_MODEL=$TEST_MODEL" \
        -e "AICODEBOX_CONTAINER_NAME=$cname" \
        "${extra[@]}" \
        "$IMAGE" >/dev/null
    EXTRA_CONTAINERS+=("$cname")

    API_CONTAINER="$cname"
    API_URL="http://127.0.0.1:$port"
    API_TOKEN="$token"

    local i
    for i in $(seq 1 30); do
        if curl -sf -m 2 "$API_URL/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log "  FAIL: api container $cname did not become ready within 30s"
    docker logs "$cname" 2>&1 | tail -50 | sed 's/^/    /'
    return 1
}

_curl_auth() {
    if [ -n "$API_TOKEN" ]; then
        curl -sS -H "Authorization: Bearer $API_TOKEN" "$@"
    else
        curl -sS "$@"
    fi
}

# ── individual tests ──────────────────────────────────────────────────────────

test_api_healthz() {
    _api_start "" || return 1
    local body
    body=$(_curl_auth -m 5 "$API_URL/healthz")
    assert_contains "$body" "\"ok\":true" "/healthz ok=true" || return 1
    assert_contains "$body" "\"adapter\":\"pi\"" "/healthz reports adapter=pi"
}

test_api_run_sync() {
    _api_start "" || return 1
    local body
    body=$(_curl_auth -m 120 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with exactly one word: HELLO. Nothing else."}')
    assert_contains "$body" "HELLO" "sync /run produced HELLO"
}

test_api_run_async() {
    _api_start "" || return 1
    local body run_id
    body=$(_curl_auth -m 10 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with exactly one word: HELLO. Nothing else.","async":true}')
    assert_contains "$body" "\"status\":\"running\"" "async /run returned running" || return 1
    run_id=$(echo "$body" | grep -oE '"runId":"[^"]+"' | head -1 | cut -d'"' -f4)
    if [ -z "$run_id" ]; then
        log "  FAIL: no runId in async response: $body"
        return 1
    fi

    local i poll
    for i in $(seq 1 120); do
        poll=$(_curl_auth -m 5 "$API_URL/run/result?runId=$run_id")
        if echo "$poll" | grep -q '"status":"completed"'; then
            assert_contains "$poll" "HELLO" "async run completed with HELLO"
            return $?
        fi
        if echo "$poll" | grep -q '"status":"failed"'; then
            log "  FAIL: async run failed: $poll"
            return 1
        fi
        sleep 1
    done
    log "  FAIL: async run never completed in 120s (last: $poll)"
    return 1
}

test_api_run_verbose() {
    _api_start "" || return 1
    # v0.5.0 contract: ``verbose=true`` swaps the lean default response
    # ({runId, workspace, exitCode, text}) for the full one — adds the
    # adapter's structured event log, sessionId, and usage alongside text.
    # No more outputFormat enum; ``verbose`` is the only switch for the
    # wire-shape decision.
    local body
    body=$(_curl_auth -m 120 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with exactly one word: HELLO. Nothing else.","verbose":true,"noContinue":true,"noTools":true}')

    # The events array is whatever the adapter decoded from raw stdout via
    # parse_events(); for pi that's the full NDJSON event stream.
    local events_len
    events_len=$(echo "$body" | jq -r '.events | length' 2>/dev/null)
    if ! [[ "$events_len" =~ ^[0-9]+$ ]] || [ "$events_len" -lt 5 ]; then
        log "  FAIL: events array missing or too short (len=$events_len)"
        log "  body: ${body:0:500}"
        return 1
    fi
    log "  OK: .events array has $events_len entries"

    # Unlike v0.4.0's json-verbose, verbose responses carry .text alongside
    # the events — verbose is wire-format richness, not LLM output style.
    local text_val has_json
    text_val=$(echo "$body" | jq -r '.text // ""')
    assert_contains "$text_val" "HELLO" "verbose response has .text with HELLO" || return 1

    # No schema means no .json field — that only appears when jsonSchema
    # is also set.
    has_json=$(echo "$body" | jq 'has("json")')
    assert_eq "$has_json" "false" "verbose-without-schema has no .json field" || return 1

    # pi's event stream MUST surface a session event with an id and at least
    # one assistant message_end carrying the marker — that's the structural
    # proof parse_events is decoding the NDJSON correctly.
    local has_session
    has_session=$(echo "$body" | jq -r '
        any(.events[]; .type=="session" and (.id | type=="string") and .id != "")
    ')
    assert_eq "$has_session" "true" "events contain a session event with id" || return 1

    local asst_text
    asst_text=$(echo "$body" | jq -r '
        [.events[]
            | select(.type=="message_end" and .message.role=="assistant")
            | .message.content
            | if type=="string" then .
              elif type=="array" then
                  [.[] | select(.type=="text") | .text] | join(" ")
              else "" end
        ] | join(" ")
    ')
    assert_contains "$asst_text" "HELLO" "assistant message_end content contains HELLO" || return 1

    # Top-level .sessionId / .usage are surfaced only when verbose=true
    # (the lean default drops them to keep the wire minimal).
    local has_session_id
    has_session_id=$(echo "$body" | jq -r '.sessionId | type=="string" and . != ""')
    assert_eq "$has_session_id" "true" "verbose response surfaces .sessionId"
}

test_api_run_json_mode() {
    _api_start "" || return 1
    # v0.5.0 contract: setting ``jsonSchema`` (no verbose) yields a clean
    # response with the decoded object under .json and no .text. Schema
    # validation + up-to-3 self-correction retries happen at the base
    # layer; the adapter just bolts the schema onto the system prompt.
    local body
    body=$(_curl_auth -m 180 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Produce a JSON object where the word field is exactly the string HELLO.","jsonSchema":{"type":"object","properties":{"word":{"type":"string"}},"required":["word"]},"noContinue":true,"noTools":true}')

    local exit_code
    exit_code=$(echo "$body" | jq -r '.exitCode')
    if [ "$exit_code" != "0" ]; then
        log "  FAIL: json mode exit_code=$exit_code"
        log "  body: ${body:0:500}"
        return 1
    fi

    # On success, .json is the decoded object and .text is absent.
    local has_json has_text
    has_json=$(echo "$body" | jq 'has("json")')
    has_text=$(echo "$body" | jq 'has("text")')
    assert_eq "$has_json" "true" "json-mode success populates .json" || return 1
    # If the model needed retries, .text comes back alongside .parseError —
    # but on a clean parse, .text must NOT be in the response.
    local parse_error
    parse_error=$(echo "$body" | jq -r '.parseError // ""')
    if [ -z "$parse_error" ] && [ "$has_text" = "true" ]; then
        log "  FAIL: json-mode success leaked .text into response (should be omitted)"
        log "  body: ${body:0:500}"
        return 1
    fi

    local word
    word=$(echo "$body" | jq -r '.json.word')
    if [[ "${word^^}" != *"HELLO"* ]]; then
        log "  FAIL: json.word=$word (expected HELLO)"
        return 1
    fi
    log "  OK: json mode returned .json.word=$word"
}

test_api_run_json_with_verbose() {
    _api_start "" || return 1
    # v0.5.0 contract: ``jsonSchema`` + ``verbose=true`` compose freely —
    # the response carries BOTH the schema-validated object under .json AND
    # the adapter's event log under .events. v0.4.0 forbade this combination
    # at the base; v0.5.0 lets callers debug schema failures by reading the
    # turn-level event stream alongside the parsed object.
    local body
    body=$(_curl_auth -m 180 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Produce a JSON object where the word field is exactly the string HELLO.","jsonSchema":{"type":"object","properties":{"word":{"type":"string"}},"required":["word"]},"verbose":true,"noContinue":true,"noTools":true}')

    local exit_code
    exit_code=$(echo "$body" | jq -r '.exitCode')
    if [ "$exit_code" != "0" ]; then
        log "  FAIL: combo mode exit_code=$exit_code"
        log "  body: ${body:0:500}"
        return 1
    fi

    # Both .json (decoded object) and .events (event log) must be present.
    local has_json has_events events_len
    has_json=$(echo "$body" | jq 'has("json")')
    assert_eq "$has_json" "true" "combo response has .json" || return 1
    has_events=$(echo "$body" | jq 'has("events")')
    assert_eq "$has_events" "true" "combo response has .events" || return 1
    events_len=$(echo "$body" | jq -r '.events | length')
    if ! [[ "$events_len" =~ ^[0-9]+$ ]] || [ "$events_len" -lt 3 ]; then
        log "  FAIL: combo events too short (len=$events_len)"
        return 1
    fi

    local word
    word=$(echo "$body" | jq -r '.json.word')
    if [[ "${word^^}" != *"HELLO"* ]]; then
        log "  FAIL: combo .json.word=$word (expected HELLO)"
        return 1
    fi
    log "  OK: combo returned .json.word=$word with $events_len events"
}

test_api_run_include_raw() {
    _api_start "" || return 1
    # includeRaw is opt-in (v0.4.0+). Default responses do NOT carry raw
    # stdout/stderr — the adapter's NDJSON stream can balloon to megabytes
    # in verbose mode and most callers don't need it. Confirm both
    # directions: default omits them, includeRaw=true surfaces them.
    local body_default body_raw
    body_default=$(_curl_auth -m 120 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with exactly one word: HELLO. Nothing else.","noContinue":true,"noTools":true}')
    local has_stdout_default
    has_stdout_default=$(echo "$body_default" | jq 'has("stdout")')
    assert_eq "$has_stdout_default" "false" "default response omits .stdout" || return 1

    body_raw=$(_curl_auth -m 120 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with exactly one word: HELLO. Nothing else.","includeRaw":true,"noContinue":true,"noTools":true}')
    local has_stdout_raw has_stderr_raw
    has_stdout_raw=$(echo "$body_raw" | jq 'has("stdout")')
    has_stderr_raw=$(echo "$body_raw" | jq 'has("stderr")')
    assert_eq "$has_stdout_raw" "true" "includeRaw=true surfaces .stdout" || return 1
    assert_eq "$has_stderr_raw" "true" "includeRaw=true surfaces .stderr" || return 1

    # The raw stdout for pi is the NDJSON event stream — contains at least
    # one parseable session event.
    local stdout_has_session
    stdout_has_session=$(echo "$body_raw" | jq -r '.stdout' | grep -c '"type":"session"' || true)
    if [ "${stdout_has_session:-0}" -lt 1 ]; then
        log "  FAIL: raw stdout missing pi session events"
        return 1
    fi
    log "  OK: raw stdout carries pi NDJSON event stream"
}

test_api_auth() {
    local token="s3cret-$$"
    _api_start "$token" || return 1
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 "$API_URL/run/result?runId=bogus")
    assert_eq "$code" "401" "without token → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 \
        -H "Authorization: Bearer wrong" "$API_URL/run/result?runId=bogus")
    assert_eq "$code" "401" "wrong token → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 \
        -H "Authorization: Bearer $token" "$API_URL/run/result?runId=bogus")
    assert_eq "$code" "404" "right token → 404 for unknown runId"
}

test_api_unknown_run() {
    _api_start "" || return 1
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 \
        "$API_URL/run/result?runId=bogus-id-does-not-exist")
    assert_eq "$code" "404" "unknown runId → 404"
}

test_api_busy() {
    _api_start "" || return 1
    _curl_auth -m 10 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with one word: WAIT.","async":true}' >/dev/null
    sleep 0.5
    local code
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with one word: WAIT."}')
    assert_eq "$code" "409" "second concurrent run → 409"
}

test_api_cancel() {
    _api_start "" || return 1
    local body run_id
    body=$(_curl_auth -m 10 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Count slowly from 1 to 50 with a short sentence about each number.","async":true}')
    run_id=$(echo "$body" | grep -oE '"runId":"[^"]+"' | head -1 | cut -d'"' -f4)
    if [ -z "$run_id" ]; then
        log "  FAIL: no runId in async response: $body"
        return 1
    fi
    sleep 1
    local code
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X DELETE "$API_URL/run/$run_id")
    assert_eq "$code" "200" "DELETE /run/$run_id → 200" || return 1
    local poll
    poll=$(_curl_auth -m 5 "$API_URL/run/result?runId=$run_id")
    if echo "$poll" | grep -q '"status":"cancelled"'; then
        assert_contains "$poll" "\"status\":\"cancelled\"" "cancelled run reports cancelled"
    elif echo "$poll" | grep -q '"detail":"run not found"'; then
        log "  OK: run purged after cancel"
    else
        log "  FAIL: unexpected poll after cancel: $poll"
        return 1
    fi
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X DELETE "$API_URL/run/bogus-id")
    assert_eq "$code" "404" "DELETE unknown runId → 404"
}

test_api_fire_and_forget() {
    _api_start "" || return 1
    local body run_id
    body=$(_curl_auth -m 10 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with one word: FFOK_MARKER.","fireAndForget":true}')
    assert_contains "$body" "\"status\":\"running\"" "fireAndForget → status=running" || return 1
    assert_contains "$body" "\"fireAndForget\":true" "fireAndForget echoed back" || return 1
    assert_contains "$body" "\"runId\":\"" "fireAndForget returned runId" || return 1
    run_id=$(echo "$body" | grep -oE '"runId":"[^"]+"' | head -1 | cut -d'"' -f4)

    # Fire-and-forget runs detach but must still eventually clear the busy
    # workspace. Poll /status — the workspace must drop out of busyWorkspaces
    # within the timeout, proving the background run actually ran to completion.
    local i status busy
    for i in $(seq 1 120); do
        status=$(_curl_auth -m 5 "$API_URL/status")
        busy=$(echo "$status" | grep -oE '"busyWorkspaces":\[[^]]*\]')
        if [ "$busy" = '"busyWorkspaces":[]' ]; then
            log "  OK: fireAndForget run completed (workspace no longer busy after ${i}s)"
            return 0
        fi
        sleep 1
    done
    log "  FAIL: fireAndForget workspace still busy after 120s ($busy)"
    return 1
}

test_api_files() {
    _api_start "" || return 1
    local code body
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: text/plain" --data-binary "hello-from-test" \
        "$API_URL/files/subdir/hello.txt")
    assert_eq "$code" "200" "PUT /files/subdir/hello.txt → 200" || return 1
    body=$(_curl_auth -m 5 "$API_URL/files/subdir/hello.txt")
    assert_eq "$body" "hello-from-test" "GET /files/subdir/hello.txt round-trip" || return 1
    body=$(_curl_auth -m 5 "$API_URL/files/subdir")
    assert_contains "$body" "\"hello.txt\"" "list /files/subdir contains hello.txt" || return 1
    assert_contains "$body" "\"type\":\"file\"" "list reports file type"
    body=$(_curl_auth -m 5 "$API_URL/files")
    assert_contains "$body" "\"entries\":" "list /files returns entries" || return 1
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" "$API_URL/files/../etc/passwd")
    if [ "$code" = "400" ] || [ "$code" = "404" ]; then
        log "  OK: traversal blocked ($code)"
    else
        log "  FAIL: traversal allowed (code=$code)"
        return 1
    fi
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X DELETE "$API_URL/files/subdir/hello.txt")
    assert_eq "$code" "200" "DELETE /files/subdir/hello.txt → 200" || return 1
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" "$API_URL/files/subdir/hello.txt")
    assert_eq "$code" "404" "GET deleted file → 404" || return 1
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X DELETE "$API_URL/files/subdir")
    assert_eq "$code" "400" "DELETE /files/subdir (dir) → 400"
}

test_api_files_binary() {
    _api_start "" || return 1
    # Tiny but non-trivial binary blob — random 1 KiB. urandom is in every
    # Linux container; no fixture file needed. We PUT it, GET it back, and
    # require the bytes to match exactly (no text-mode mangling of nulls /
    # high-bit characters by curl or FastAPI).
    local src dst
    src=$(mktemp)
    dst=$(mktemp)
    head -c 1024 /dev/urandom > "$src"
    local code
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$src" \
        "$API_URL/files/blobs/random.bin")
    assert_eq "$code" "200" "PUT binary /files/blobs/random.bin → 200" || \
        { rm -f "$src" "$dst"; return 1; }
    _curl_auth -m 5 -o "$dst" "$API_URL/files/blobs/random.bin"
    if cmp -s "$src" "$dst"; then
        log "  OK: binary round-trip byte-for-byte identical"
    else
        log "  FAIL: binary round-trip differs ($(stat -c%s "$src") vs $(stat -c%s "$dst") bytes)"
        rm -f "$src" "$dst"
        return 1
    fi
    rm -f "$src" "$dst"
}

test_api_files_auto_mkdir() {
    _api_start "" || return 1
    # PUT into a path whose parents don't exist yet — the server must
    # create the intermediate directories rather than 404 / 500.
    local code body
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: text/plain" --data-binary "deep-write" \
        "$API_URL/files/deep/nested/path/file.txt")
    assert_eq "$code" "200" "PUT into non-existent parent dirs → 200" || return 1
    body=$(_curl_auth -m 5 "$API_URL/files/deep/nested/path/file.txt")
    assert_eq "$body" "deep-write" "auto-created path round-trips" || return 1
    body=$(_curl_auth -m 5 "$API_URL/files/deep")
    assert_contains "$body" "\"nested\"" "intermediate dirs listable"
}

test_api_files_overwrite() {
    _api_start "" || return 1
    # PUT twice to the same path — second must replace, not append/error.
    local code body
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: text/plain" --data-binary "first-version" \
        "$API_URL/files/overwrite.txt")
    assert_eq "$code" "200" "first PUT → 200" || return 1
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: text/plain" --data-binary "second-version" \
        "$API_URL/files/overwrite.txt")
    assert_eq "$code" "200" "overwrite PUT → 200" || return 1
    body=$(_curl_auth -m 5 "$API_URL/files/overwrite.txt")
    assert_eq "$body" "second-version" "GET returns overwritten content (not concatenated)"
}

test_api_files_delete_nonexistent() {
    _api_start "" || return 1
    local code
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X DELETE \
        "$API_URL/files/this-path-does-not-exist.txt")
    assert_eq "$code" "404" "DELETE nonexistent → 404"
}

test_api_files_auth() {
    # Bearer enforcement on /files/* specifically (test_api_auth only covers
    # /run/result; need to confirm files routes are also gated).
    local token="files-auth-$$"
    _api_start "$token" || return 1
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 "$API_URL/files")
    assert_eq "$code" "401" "GET /files without token → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 -X PUT \
        -H "Content-Type: text/plain" --data-binary "x" \
        "$API_URL/files/nope.txt")
    assert_eq "$code" "401" "PUT /files/* without token → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 -X DELETE \
        "$API_URL/files/nope.txt")
    assert_eq "$code" "401" "DELETE /files/* without token → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 \
        -H "Authorization: Bearer wrong" "$API_URL/files")
    assert_eq "$code" "401" "GET /files with wrong token → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 \
        -H "Authorization: Bearer $token" "$API_URL/files")
    assert_eq "$code" "200" "GET /files with right token → 200"
}

test_api_oai_models() {
    _api_start "" || return 1
    local body
    body=$(_curl_auth -m 5 "$API_URL/openai/v1/models")
    assert_contains "$body" "\"object\":\"list\"" "/openai/v1/models is a list" || return 1
    # /openai/v1/models reflects AICODEBOX_AVAILABLE_MODELS (set to
    # $TEST_MODEL by _api_start). The base no longer falls back to the
    # adapter name — "pi" is the adapter, not a model id.
    assert_contains "$body" "\"id\":\"$TEST_MODEL\"" "model list contains id=$TEST_MODEL"
}

test_api_oai_chat() {
    _api_start "" || return 1
    local body
    body=$(_curl_auth -m 120 -X POST "$API_URL/openai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"pi","messages":[{"role":"user","content":"Reply with exactly one word: HELLO. Nothing else."}]}')
    assert_contains "$body" "\"object\":\"chat.completion\"" "oai chat response shape" || return 1
    assert_contains "$body" "HELLO" "oai chat content has HELLO" || return 1
    assert_contains "$body" "\"finish_reason\":\"stop\"" "oai chat finish_reason"
}

test_api_oai_reject_tools() {
    _api_start "" || return 1
    local code
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X POST "$API_URL/openai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"x","messages":[{"role":"user","content":"hi"}],"tools":[{"type":"function","function":{"name":"x"}}]}')
    assert_eq "$code" "400" "oai tools → 400" || return 1
    code=$(_curl_auth -m 5 -o /dev/null -w "%{http_code}" -X POST "$API_URL/openai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"x","messages":[{"role":"user","content":"hi"}],"response_format":{"type":"json_object"}}')
    assert_eq "$code" "400" "oai response_format=json_object → 400"
}

test_api_status() {
    _api_start "" || return 1
    local body
    body=$(_curl_auth -m 5 "$API_URL/status")
    assert_contains "$body" "\"busyWorkspaces\"" "/status has busyWorkspaces" || return 1
    assert_contains "$body" "\"runs\"" "/status has runs" || return 1

    # /status must actually reflect activity: kick off an async run and verify
    # busyWorkspaces becomes non-empty + runs[] has an entry while it's live.
    local async_body run_id
    async_body=$(_curl_auth -m 10 -X POST "$API_URL/run" \
        -H "Content-Type: application/json" \
        -d '{"prompt":"Reply with the single word STATUSCHECK.","async":true}')
    run_id=$(echo "$async_body" | grep -oE '"runId":"[^"]+"' | head -1 | cut -d'"' -f4)
    if [ -z "$run_id" ]; then
        log "  FAIL: could not start async run for /status check: $async_body"
        return 1
    fi

    local i saw_busy=0 saw_run=0
    for i in $(seq 1 30); do
        body=$(_curl_auth -m 5 "$API_URL/status")
        if echo "$body" | grep -qE '"busyWorkspaces":\[[^]]'; then
            saw_busy=1
        fi
        if echo "$body" | grep -qE "\"runId\":\"$run_id\""; then
            saw_run=1
        fi
        if [ "$saw_busy" = 1 ] && [ "$saw_run" = 1 ]; then
            break
        fi
        sleep 1
    done

    # Wait for run to drain so we don't leak state into next test.
    for i in $(seq 1 120); do
        local poll
        poll=$(_curl_auth -m 5 "$API_URL/run/result?runId=$run_id")
        if echo "$poll" | grep -qE '"status":"(completed|failed|cancelled)"'; then
            break
        fi
        sleep 1
    done

    if [ "$saw_busy" != 1 ]; then
        log "  FAIL: /status never showed busyWorkspaces non-empty during run"
        return 1
    fi
    if [ "$saw_run" != 1 ]; then
        log "  FAIL: /status runs[] never contained the active runId"
        return 1
    fi
    log "  OK: /status reflected live run (busyWorkspaces + runs[] entry visible)"
}

test_api_oai_stream() {
    _api_start "" || return 1
    local body
    body=$(_curl_auth -m 180 -N -X POST "$API_URL/openai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"pi","messages":[{"role":"user","content":"Count from 1 to 5 in words, one per line. Nothing else."}],"stream":true}')
    assert_contains "$body" "chat.completion.chunk" "oai stream emits chunks" || return 1
    assert_contains "$body" "[DONE]" "oai stream terminates with [DONE]" || return 1

    # Real per-delta streaming MUST produce multiple `chat.completion.chunk`
    # frames carrying non-empty `content`. The previous fake-single-chunk
    # implementation emitted exactly one content-bearing chunk; anything ≥2
    # is structural proof that pi's `text_delta` events reached the wire.
    local content_chunks
    content_chunks=$(echo "$body" | grep -cE '"content": "[^"]+"')
    if [ "$content_chunks" -lt 2 ]; then
        log "  FAIL: streaming emitted only $content_chunks content chunks (need ≥2 for real streaming)"
        log "  body: ${body:0:800}"
        return 1
    fi
    log "  OK: streaming emitted $content_chunks content chunks (multi-delta)"

    # Concatenate the delta payloads to reconstruct the full response —
    # tokens like "Three" may be split across frames, so a contiguous
    # match on the raw SSE body would be flaky.
    local joined
    joined=$(echo "$body" | jq -rR '
        select(startswith("data: ") and (. | endswith("[DONE]") | not)) |
        .[6:] | fromjson? | .choices[0].delta.content // empty
    ' 2>/dev/null | tr -d '\n')
    # Case-insensitive match — different providers (anthropic / z.ai / etc.)
    # don't agree on capitalization of number words.
    local lower
    lower=$(echo "$joined" | tr '[:upper:]' '[:lower:]')
    assert_contains "$lower" "one" "stream content includes 'one'" || return 1
    assert_contains "$lower" "five" "stream content includes 'five'"
}

# 1x1 transparent PNG, base64-encoded — small enough to inline as a data: URL.
_TEST_PNG_DATA_URI='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkAAIAAAoAAv/lxKUAAAAASUVORK5CYII='

test_api_oai_image() {
    _api_start "" || return 1
    local body code
    code=$(_curl_auth -m 180 -o /tmp/_oai_img_resp -w "%{http_code}" -X POST "$API_URL/openai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"pi\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Reply with the single word OK. Nothing else.\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"$_TEST_PNG_DATA_URI\"}}]}]}")
    body=$(cat /tmp/_oai_img_resp 2>/dev/null || echo "")
    rm -f /tmp/_oai_img_resp
    assert_eq "$code" "200" "oai multimodal request accepted" || {
        echo "    body: $(echo "$body" | head -c 300)"
        return 1
    }
    assert_contains "$body" "\"object\":\"chat.completion\"" "oai multimodal response shape" || return 1
    docker exec "$API_CONTAINER" ls /workspace/_oai_uploads/ 2>/dev/null | grep -qE '^upload_[0-9a-f]+\.png$' \
        && log "  OK: oai image saved to /workspace/_oai_uploads/" \
        || { log "  FAIL: oai image not saved"; docker exec "$API_CONTAINER" ls /workspace/_oai_uploads/ 2>/dev/null | sed 's/^/    /'; return 1; }
}

test_api_mcp_handshake() {
    _api_start "" || return 1
    local resp status
    resp=$(_curl_auth -m 10 -i -X POST "$API_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"pibox-test","version":"1"}}}')
    status=$(echo "$resp" | head -1 | awk '{print $2}')
    if [ "$status" = "200" ] || [ "$status" = "202" ]; then
        log "  OK: /mcp/ initialize returned $status"
    else
        log "  FAIL: /mcp/ initialize status=$status"
        echo "$resp" | head -20 | sed 's/^/    /'
        return 1
    fi
    assert_contains "$resp" "mcp-session-id" "/mcp/ returned session id header"
}

test_api_mcp_auth() {
    local token="mcp-s3cret-$$"
    _api_start "$token" || return 1
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 -X POST "$API_URL/mcp/" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"x","version":"1"}}}')
    assert_eq "$code" "401" "/mcp/ without bearer → 401" || return 1
    code=$(curl -sS -o /dev/null -w "%{http_code}" -m 5 -X POST "$API_URL/mcp/" \
        -H "Authorization: Bearer wrong" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"x","version":"1"}}}')
    assert_eq "$code" "401" "/mcp/ wrong bearer → 401"
}

ALL_TESTS+=(
    test_api_healthz
    test_api_run_sync
    test_api_run_async
    test_api_run_verbose
    test_api_run_json_mode
    test_api_run_json_with_verbose
    test_api_run_include_raw
    test_api_auth
    test_api_unknown_run
    test_api_busy
    test_api_cancel
    test_api_fire_and_forget
    test_api_files
    test_api_files_binary
    test_api_files_auto_mkdir
    test_api_files_overwrite
    test_api_files_delete_nonexistent
    test_api_files_auth
    test_api_oai_models
    test_api_oai_chat
    test_api_oai_reject_tools
    test_api_mcp_handshake
    test_api_mcp_auth
    test_api_status
    test_api_oai_stream
    test_api_oai_image
)
