#!/bin/bash
# Phase-4 cron+telegram e2e test. Container runs both modes; cron posts a job
# result to a real chat, test (telethon) replies, bot injects cron context and
# pi replies referencing the cron content.

_ct_check_env() {
    local missing=()
    for v in AICODEBOX_TELEGRAM_MODE_TOKEN TELEGRAM_CHAT_ID \
             TELETHON_API_ID TELETHON_API_HASH TELETHON_SESSION TELETHON_AUTH_KEY; do
        if [ -z "${!v:-}" ]; then
            missing+=("$v")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log "  SKIP: missing env vars: ${missing[*]}"
        return 1
    fi
    return 0
}

# Helpers defined inline to avoid sourcing-order dependence on test_telegram.sh.

_ct_pick_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

_ct_setup_dirs() {
    local case_="$1"
    CT_TMP="$WORKDIR/tests/logs/ct-${case_}"
    rm -rf "$CT_TMP"
    mkdir -p "$CT_TMP/home/.aicodebox" "$CT_TMP/workspace"
    chmod -R 777 "$CT_TMP"
}

_ct_start_telethon() {
    CT_TELETHON_PORT=$(_ct_pick_port)
    CT_TELETHON_NAME="${CONTAINER_PREFIX}-ct-telethon-$$-$RANDOM"
    CT_TELETHON_URL="http://127.0.0.1:$CT_TELETHON_PORT"

    docker pull psyb0t/telethon-plus >/dev/null 2>&1 || true
    docker run -d --name "$CT_TELETHON_NAME" \
        -p "127.0.0.1:$CT_TELETHON_PORT:8080" \
        -e "TELETHON_API_ID=$TELETHON_API_ID" \
        -e "TELETHON_API_HASH=$TELETHON_API_HASH" \
        -e "TELETHON_SESSION=$TELETHON_SESSION" \
        -e "TELETHON_AUTH_KEY=$TELETHON_AUTH_KEY" \
        psyb0t/telethon-plus >/dev/null 2>&1
    EXTRA_CONTAINERS+=("$CT_TELETHON_NAME")

    for _ in $(seq 1 30); do
        if curl -sf "$CT_TELETHON_URL/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log "  FAIL: telethon-plus not healthy on $CT_TELETHON_URL"
    docker logs "$CT_TELETHON_NAME" 2>&1 | tail -30 | sed 's/^/    /'
    return 1
}

CT_BOT_REF=""
_ct_resolve_bot() {
    [ -n "$CT_BOT_REF" ] && return 0
    local resp username
    resp=$(curl -sf "https://api.telegram.org/bot${AICODEBOX_TELEGRAM_MODE_TOKEN}/getMe")
    username=$(echo "$resp" | python3 -c 'import json,sys
print((json.load(sys.stdin).get("result") or {}).get("username", ""))')
    if [ -z "$username" ]; then
        log "  FAIL: could not resolve bot username: $resp"
        return 1
    fi
    CT_BOT_REF="@$username"
    log "  OK: bot resolved as $CT_BOT_REF"
}

_ct_bot_user_id() { echo "${AICODEBOX_TELEGRAM_MODE_TOKEN%%:*}"; }

_ct_curl() {
    curl -sS -H "Authorization: Bearer $TELETHON_AUTH_KEY" "$@"
}

_ct_json_payload() {
    CHAT="$CT_BOT_REF" TEXT="$1" REPLY_TO="${2:-}" python3 -c '
import json, os
p = {"chat": os.environ["CHAT"], "text": os.environ["TEXT"]}
rt = os.environ.get("REPLY_TO") or ""
if rt:
    p["reply_to"] = int(rt)
print(json.dumps(p))'
}

_ct_send_text() {
    local payload
    payload=$(_ct_json_payload "$1" "")
    _ct_curl -X POST "$CT_TELETHON_URL/api/messages" \
        -H "Content-Type: application/json" -d "$payload" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["id"])'
}

_ct_reply() {
    local payload
    payload=$(_ct_json_payload "$1" "$2")
    _ct_curl -X POST "$CT_TELETHON_URL/api/messages" \
        -H "Content-Type: application/json" -d "$payload" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["id"])'
}

_ct_latest_msg_id() {
    _ct_curl "$CT_TELETHON_URL/api/messages?chat=$CT_BOT_REF&limit=1" \
        | python3 -c 'import json,sys
d = json.load(sys.stdin).get("result", [])
print(d[0]["id"] if d else 0)'
}

# Args: <baseline> <substr> [timeout]
_ct_wait_for_bot_message() {
    local baseline="$1" substr="$2" timeout="${3:-120}"
    local bot_id i resp
    bot_id=$(_ct_bot_user_id)
    for i in $(seq 1 "$timeout"); do
        resp=$(_ct_curl "$CT_TELETHON_URL/api/messages?chat=$CT_BOT_REF&limit=30" 2>/dev/null) || { sleep 1; continue; }
        local hit
        hit=$(BASELINE="$baseline" BOT_ID="$bot_id" SUBSTR="$substr" RESP="$resp" python3 - <<'PY'
import json, os, sys
data = json.loads(os.environ["RESP"]).get("result", [])
baseline = int(os.environ["BASELINE"])
bot_id = int(os.environ["BOT_ID"])
substr = os.environ["SUBSTR"]
for m in reversed(data):
    mid = int(m.get("id") or 0)
    if mid <= baseline:
        continue
    if int(m.get("sender_id") or 0) != bot_id:
        continue
    text = m.get("text") or ""
    if substr and substr not in text:
        continue
    print(mid)
    print(text)
    sys.exit(0)
sys.exit(1)
PY
)
        if [ -n "$hit" ]; then
            echo "$hit"
            return 0
        fi
        sleep 1
    done
    return 1
}

_ct_start_container() {
    local case_="$1" cron_yaml="$2"
    CT_CNAME="${CONTAINER_PREFIX}-ct-${case_}-$$"
    local hostdir="$CT_TMP"
    printf '%s' "$cron_yaml" > "$hostdir/cron.yaml"
    docker rm -f "$CT_CNAME" >/dev/null 2>&1 || true
    docker run -d --name "$CT_CNAME" \
        --network host \
        -v "$hostdir/workspace:/workspace" \
        -v "$hostdir/home/.aicodebox:/home/aicode/.aicodebox" \
        -v "$hostdir/cron.yaml:/cron.yaml:ro" \
        -e "AICODEBOX_CRON_MODE=1" \
        -e "AICODEBOX_TELEGRAM_MODE=1" \
        -e "AICODEBOX_CRON_MODE_FILE=/cron.yaml" \
        -e "AICODEBOX_WORKSPACE=/workspace" \
        -e "AICODEBOX_TELEGRAM_MODE_TOKEN=$AICODEBOX_TELEGRAM_MODE_TOKEN" \
        -e "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID" \
        -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
        -e "ANTHROPIC_MODEL=$TEST_MODEL" \
        -e "AICODEBOX_CONTAINER_NAME=$CT_CNAME" \
        "$IMAGE" >/dev/null
    EXTRA_CONTAINERS+=("$CT_CNAME")
    for _ in $(seq 1 30); do
        if docker logs "$CT_CNAME" 2>&1 | grep -q "telegram bot starting"; then
            sleep 2
            return 0
        fi
        sleep 1
    done
    log "  WARN: bot did not start within 30s"
    docker logs "$CT_CNAME" 2>&1 | tail -40 | sed 's/^/    /'
    return 0
}

_ct_stop_container() {
    if [ -n "${CT_CNAME:-}" ]; then
        docker logs "$CT_CNAME" >"${TEST_LOG_DIR:-/tmp}/${CT_CNAME}.log" 2>&1 || true
        docker rm -f "$CT_CNAME" >/dev/null 2>&1 || true
        CT_CNAME=""
    fi
    if [ -n "${CT_TELETHON_NAME:-}" ]; then
        docker rm -f "$CT_TELETHON_NAME" >/dev/null 2>&1 || true
        CT_TELETHON_NAME=""
    fi
    sleep 2
}

# ── test ────────────────────────────────────────────────────────────────────

test_ct_reply_to_cron() {
    _ct_check_env || return 0
    _ct_resolve_bot || return 1
    _ct_setup_dirs replyctx
    _ct_start_telethon || { _ct_stop_container; return 1; }

    local marker="CTMARK$RANDOM$$"
    local yaml
    yaml=$(cat <<EOF
jobs:
  - name: marker
    schedule: "*/10 * * * * *"
    telegram_chat_id: $TELEGRAM_CHAT_ID
    no_continue: true
    instruction: |
      Reply with exactly one token: $marker. Nothing else.
EOF
)
    _ct_start_container replyctx "$yaml" || { _ct_stop_container; return 1; }

    local baseline
    baseline=$(_ct_latest_msg_id)

    local result cron_msg_id
    if ! result=$(_ct_wait_for_bot_message "$baseline" "$marker" 120); then
        log "  FAIL: cron did not post $marker within 120s"
        docker logs "$CT_CNAME" 2>&1 | tail -50 | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    cron_msg_id=$(echo "$result" | head -1)
    log "  OK: cron posted $marker to telegram (msg id=$cron_msg_id)"

    local echo_token="REPLYECHO$RANDOM$$"
    local reply_baseline
    reply_baseline=$(_ct_latest_msg_id)
    _ct_reply "What was the single token in your previous message? Reply with exactly two tokens separated by a space: that token, then $echo_token." "$cron_msg_id" >/dev/null
    log "  OK: replied to cron message $cron_msg_id (echo_token=$echo_token)"

    local resp resp_text
    if ! resp=$(_ct_wait_for_bot_message "$reply_baseline" "$echo_token" 180); then
        log "  FAIL: bot did not echo $echo_token (reply path) within 180s"
        docker logs "$CT_CNAME" 2>&1 | tail -60 | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    resp_text=$(echo "$resp" | tail -n +2)
    assert_contains "$resp_text" "$echo_token" "bot reply echoed reply-path token"
    local rc1=$?
    assert_contains "$resp_text" "$marker" "bot reply contains cron marker (context injection)"
    local rc2=$?
    local rc=0
    [ "$rc1" = 0 ] || rc=1
    [ "$rc2" = 0 ] || rc=1

    local tg_msgs="$CT_TMP/home/.aicodebox/cron/telegram_messages.json"
    if [ -f "$tg_msgs" ]; then
        log "  OK: telegram_messages.json written at $tg_msgs"
    else
        log "  FAIL: telegram_messages.json not found at $tg_msgs"
        rc=1
    fi

    _ct_stop_container
    return $rc
}

ALL_TESTS+=(test_ct_reply_to_cron)
