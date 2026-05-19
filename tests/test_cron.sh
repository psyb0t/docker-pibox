#!/bin/bash
# Phase-2 cron mode tests. One detached container per case with a yaml file
# mounted; observe behavior via docker exec / file checks.

_cron_container_name() {
    echo "${CONTAINER_PREFIX}-cron-${1}-$$"
}

# _cron_start <case> <yaml-content>
# Writes yaml into a temp dir on the host, mounts it into the container at
# /workspace/cron.yaml, starts detached. Sets CRON_CONTAINER + CRON_DIR.
_cron_start() {
    local case_="$1"
    local yaml="$2"

    local cname
    cname=$(_cron_container_name "$case_")
    local hostdir="$WORKDIR/tests/logs/cron-${case_}"
    rm -rf "$hostdir"
    mkdir -p "$hostdir"
    printf '%s' "$yaml" > "$hostdir/cron.yaml"

    docker rm -f "$cname" >/dev/null 2>&1 || true
    docker run -d --name "$cname" \
        --network host \
        -v "$hostdir:/workspace" \
        -e "AICODEBOX_MODE_CRON=1" \
        -e "AICODEBOX_MODE_CRON_FILE=/workspace/cron.yaml" \
        -e "AICODEBOX_WORKSPACE=/workspace" \
        -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
        -e "ANTHROPIC_MODEL=$TEST_MODEL" \
        -e "AICODEBOX_CONTAINER_NAME=$cname" \
        "$IMAGE" >/dev/null
    EXTRA_CONTAINERS+=("$cname")

    CRON_CONTAINER="$cname"
    CRON_DIR="$hostdir"
}

# ── tests ────────────────────────────────────────────────────────────────────

test_cron_yaml_parse() {
    local cname
    cname=$(_cron_container_name "parse")
    local hostdir="$WORKDIR/tests/logs/cron-parse"
    rm -rf "$hostdir"
    mkdir -p "$hostdir"
    printf '%s' "this is: not [valid yaml :::" > "$hostdir/cron.yaml"

    docker rm -f "$cname" >/dev/null 2>&1 || true
    local rc
    rc=$(docker run --rm \
        -v "$hostdir:/workspace" \
        -e "AICODEBOX_MODE_CRON=1" \
        -e "AICODEBOX_MODE_CRON_FILE=/workspace/cron.yaml" \
        -e "AICODEBOX_WORKSPACE=/workspace" \
        "$IMAGE" >/dev/null 2>&1; echo $?)
    if [ "$rc" = "0" ]; then
        log "  FAIL: cron with broken yaml should fail; got rc=0"
        return 1
    fi
    log "  OK: broken yaml → exit rc=$rc"
}

test_cron_fires() {
    local yaml
    yaml=$(cat <<EOF
jobs:
  - name: ping
    schedule: "*/3 * * * * *"
    thinking: low
    instruction: "Reply with exactly one word: PONG. Nothing else."
EOF
)
    _cron_start "fires" "$yaml"
    local i
    for i in $(seq 1 60); do
        if docker exec "$CRON_CONTAINER" test -f /home/aicode/.aicodebox/cron/ping.jsonl 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if ! docker exec "$CRON_CONTAINER" test -f /home/aicode/.aicodebox/cron/ping.jsonl 2>/dev/null; then
        log "  FAIL: ping.jsonl never created within 60s"
        docker logs "$CRON_CONTAINER" 2>&1 | tail -30 | sed 's/^/    /'
        return 1
    fi
    local count
    count=$(docker exec "$CRON_CONTAINER" sh -c 'wc -l < /home/aicode/.aicodebox/cron/ping.jsonl')
    if [ "${count:-0}" -lt 1 ]; then
        log "  FAIL: ping.jsonl empty"
        return 1
    fi
    log "  OK: ping.jsonl has $count entry"
    local last
    last=$(docker exec "$CRON_CONTAINER" sh -c 'tail -1 /home/aicode/.aicodebox/cron/ping.jsonl')
    assert_contains "$last" "PONG" "cron entry contains PONG output"
}

test_cron_writes_file() {
    local yaml
    yaml=$(cat <<EOF
jobs:
  - name: mark
    schedule: "*/3 * * * * *"
    instruction: |
      Write a file named marker.txt in the current directory with the exact contents:
      MARKER_OK_pi
      Just create the file and exit. Do not ask any questions.
EOF
)
    _cron_start "writes" "$yaml"
    local i
    for i in $(seq 1 90); do
        if docker exec "$CRON_CONTAINER" test -f /workspace/marker.txt 2>/dev/null; then
            break
        fi
        sleep 1
    done
    if ! docker exec "$CRON_CONTAINER" test -f /workspace/marker.txt 2>/dev/null; then
        log "  FAIL: marker.txt never created within 90s"
        docker logs "$CRON_CONTAINER" 2>&1 | tail -30 | sed 's/^/    /'
        return 1
    fi
    local content
    content=$(docker exec "$CRON_CONTAINER" cat /workspace/marker.txt 2>/dev/null)
    assert_contains "$content" "MARKER_OK_pi" "marker.txt content matches"
}

test_cron_multi_job() {
    local yaml
    yaml=$(cat <<EOF
jobs:
  - name: a
    schedule: "*/3 * * * * *"
    instruction: "Reply with the single word A."
  - name: b
    schedule: "*/3 * * * * *"
    instruction: "Reply with the single word B."
EOF
)
    _cron_start "multi" "$yaml"
    local i ok_a=0 ok_b=0
    for i in $(seq 1 90); do
        docker exec "$CRON_CONTAINER" test -f /home/aicode/.aicodebox/cron/a.jsonl 2>/dev/null && ok_a=1
        docker exec "$CRON_CONTAINER" test -f /home/aicode/.aicodebox/cron/b.jsonl 2>/dev/null && ok_b=1
        if [ "$ok_a" = 1 ] && [ "$ok_b" = 1 ]; then
            break
        fi
        sleep 1
    done
    if [ "$ok_a" != 1 ] || [ "$ok_b" != 1 ]; then
        log "  FAIL: jobs missing — a=$ok_a b=$ok_b"
        docker logs "$CRON_CONTAINER" 2>&1 | tail -30 | sed 's/^/    /'
        return 1
    fi
    # Wait for each jsonl to actually contain its expected output, not just exist.
    local last_a last_b got_a=0 got_b=0
    for i in $(seq 1 90); do
        last_a=$(docker exec "$CRON_CONTAINER" sh -c 'tail -1 /home/aicode/.aicodebox/cron/a.jsonl 2>/dev/null' || true)
        last_b=$(docker exec "$CRON_CONTAINER" sh -c 'tail -1 /home/aicode/.aicodebox/cron/b.jsonl 2>/dev/null' || true)
        [[ "$last_a" == *"\"A\""* ]] && got_a=1
        [[ "$last_b" == *"\"B\""* ]] && got_b=1
        if [ "$got_a" = 1 ] && [ "$got_b" = 1 ]; then
            break
        fi
        sleep 1
    done
    if [ "$got_a" != 1 ] || [ "$got_b" != 1 ]; then
        log "  FAIL: jsonl content missing A/B markers (got_a=$got_a got_b=$got_b)"
        log "  a: ${last_a:0:300}"
        log "  b: ${last_b:0:300}"
        return 1
    fi
    log "  OK: both jobs fired AND produced expected output (A in a.jsonl, B in b.jsonl)"
}

ALL_TESTS+=(
    test_cron_yaml_parse
    test_cron_fires
    test_cron_writes_file
    test_cron_multi_job
)
