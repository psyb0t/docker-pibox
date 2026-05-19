#!/bin/bash
# Phase-3 telegram mode tests. One detached container per case driving pi
# via the real Telegram bot. User side is psyb0t/telethon-plus.

TELETHON_IMAGE="psyb0t/telethon-plus"

_tg_check_env() {
    local missing=()
    for v in AICODEBOX_TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID \
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

_tg_pick_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

_tg_setup_dirs() {
    local case_="$1"
    TG_TMP="$WORKDIR/tests/logs/tg-${case_}"
    rm -rf "$TG_TMP"
    mkdir -p "$TG_TMP/home/.aicodebox" "$TG_TMP/workspace"
    chmod 777 "$TG_TMP" "$TG_TMP/home" "$TG_TMP/home/.aicodebox" "$TG_TMP/workspace"
}

_tg_start_telethon() {
    TG_TELETHON_PORT=$(_tg_pick_port)
    TG_TELETHON_NAME="${CONTAINER_PREFIX}-telethon-$$-$RANDOM"
    TG_TELETHON_URL="http://127.0.0.1:$TG_TELETHON_PORT"

    docker pull "$TELETHON_IMAGE" >/dev/null 2>&1 || true

    docker run -d --name "$TG_TELETHON_NAME" \
        -p "127.0.0.1:$TG_TELETHON_PORT:8080" \
        -e "TELETHON_API_ID=$TELETHON_API_ID" \
        -e "TELETHON_API_HASH=$TELETHON_API_HASH" \
        -e "TELETHON_SESSION=$TELETHON_SESSION" \
        -e "TELETHON_AUTH_KEY=$TELETHON_AUTH_KEY" \
        "$TELETHON_IMAGE" >/dev/null 2>&1
    EXTRA_CONTAINERS+=("$TG_TELETHON_NAME")

    for _ in $(seq 1 30); do
        if curl -sf "$TG_TELETHON_URL/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log "  FAIL: telethon-plus not healthy on $TG_TELETHON_URL"
    docker logs "$TG_TELETHON_NAME" 2>&1 | tail -30 | sed 's/^/    /'
    return 1
}

TG_BOT_REF=""

_tg_resolve_bot() {
    [ -n "$TG_BOT_REF" ] && return 0
    local resp username
    resp=$(curl -sf "https://api.telegram.org/bot${AICODEBOX_TELEGRAM_BOT_TOKEN}/getMe")
    username=$(echo "$resp" | python3 -c 'import json,sys
print((json.load(sys.stdin).get("result") or {}).get("username", ""))')
    if [ -z "$username" ]; then
        log "  FAIL: could not resolve bot username: $resp"
        return 1
    fi
    TG_BOT_REF="@$username"
    log "  OK: bot resolved as $TG_BOT_REF"
}

_tg_bot_user_id() { echo "${AICODEBOX_TELEGRAM_BOT_TOKEN%%:*}"; }

_tg_curl() {
    curl -sS -H "Authorization: Bearer $TELETHON_AUTH_KEY" "$@"
}

_tg_send_json_payload() {
    python3 - <<'PY'
import json, os
payload = {"chat": os.environ["CHAT"], "text": os.environ["TEXT"]}
if os.environ.get("REPLY_TO"):
    payload["reply_to"] = int(os.environ["REPLY_TO"])
print(json.dumps(payload))
PY
}

_tg_send_text() {
    local payload
    payload=$(CHAT="$TG_BOT_REF" TEXT="$1" REPLY_TO="" _tg_send_json_payload)
    _tg_curl -X POST "$TG_TELETHON_URL/api/messages" \
        -H "Content-Type: application/json" -d "$payload" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["id"])'
}

_tg_latest_msg_id() {
    _tg_curl "$TG_TELETHON_URL/api/messages?chat=$TG_BOT_REF&limit=1" \
        | python3 -c 'import json,sys
d = json.load(sys.stdin).get("result", [])
print(d[0]["id"] if d else 0)'
}

# Args: <baseline_id> <substr> [timeout]. Prints id\ntext on success.
_tg_wait_for_bot_message() {
    local baseline="$1" substr="$2" timeout="${3:-120}"
    local bot_id i resp
    bot_id=$(_tg_bot_user_id)
    for i in $(seq 1 "$timeout"); do
        resp=$(_tg_curl "$TG_TELETHON_URL/api/messages?chat=$TG_BOT_REF&limit=30" 2>/dev/null) || { sleep 1; continue; }
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

# Start the pibox container in telegram mode. Sets TG_BOT_CNAME.
# Args: <case> [extra-docker-args...]
_tg_start_bot() {
    local case_="$1"
    shift
    TG_BOT_CNAME="${CONTAINER_PREFIX}-tg-${case_}-$$"
    docker rm -f "$TG_BOT_CNAME" >/dev/null 2>&1 || true
    docker run -d --name "$TG_BOT_CNAME" \
        --network host \
        -v "$TG_TMP/workspace:/workspace" \
        -v "$TG_TMP/home/.aicodebox:/home/aicode/.aicodebox" \
        -e "AICODEBOX_MODE_TELEGRAM=1" \
        -e "AICODEBOX_WORKSPACE=/workspace" \
        -e "AICODEBOX_TELEGRAM_BOT_TOKEN=$AICODEBOX_TELEGRAM_BOT_TOKEN" \
        -e "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID" \
        -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
        -e "ANTHROPIC_MODEL=$TEST_MODEL" \
        -e "AICODEBOX_CONTAINER_NAME=$TG_BOT_CNAME" \
        "$@" \
        "$IMAGE" >/dev/null
    EXTRA_CONTAINERS+=("$TG_BOT_CNAME")
    for _ in $(seq 1 20); do
        if docker logs "$TG_BOT_CNAME" 2>&1 | grep -q "telegram bot starting"; then
            sleep 2
            return 0
        fi
        sleep 1
    done
    log "  WARN: did not see 'telegram bot starting' in logs"
    docker logs "$TG_BOT_CNAME" 2>&1 | tail -30 | sed 's/^/    /'
    return 0
}

_tg_stop_bot() {
    if [ -n "${TG_BOT_CNAME:-}" ]; then
        docker logs "$TG_BOT_CNAME" >"${TEST_LOG_DIR:-/tmp}/${TG_BOT_CNAME}.log" 2>&1 || true
        docker rm -f "$TG_BOT_CNAME" >/dev/null 2>&1 || true
        TG_BOT_CNAME=""
    fi
    if [ -n "${TG_TELETHON_NAME:-}" ]; then
        docker rm -f "$TG_TELETHON_NAME" >/dev/null 2>&1 || true
        TG_TELETHON_NAME=""
    fi
    sleep 2
}

# ── tests ────────────────────────────────────────────────────────────────────

test_tg_unit_md_to_html() {
    local cname="${CONTAINER_PREFIX}-tg-unit-$$"
    local rc out
    out=$(docker run --rm --name "$cname" \
        -e "AICODEBOX_TELEGRAM_BOT_TOKEN=dummy:dummy" \
        --entrypoint python3 \
        "$IMAGE" -c '
from aicodebox.modes.telegram.utils import md_to_tg_html
cases = [
    ("**bold**", "<b>bold</b>"),
    ("*italic*", "<i>italic</i>"),
    ("~~strike~~", "<s>strike</s>"),
    ("`code`", "<code>code</code>"),
    ("# heading", "<b>heading</b>"),
    ("- item", "• item"),
    ("[label](https://x.y)", "<a href=\"https://x.y\">label</a>"),
    ("plain & < >", "plain &amp; &lt; &gt;"),
]
fails = []
for src, want in cases:
    got = md_to_tg_html(src)
    if want not in got:
        fails.append(f"src={src!r} expected to contain {want!r} got {got!r}")
import sys
if fails:
    print("FAIL: " + "\n".join(fails))
    sys.exit(1)
print("OK: md_to_tg_html unit cases passed")
') 2>&1
    rc=$?
    echo "$out" | sed 's/^/    /'
    if [ "$rc" != "0" ]; then
        log "  FAIL: md_to_tg_html unit (rc=$rc)"
        return 1
    fi
    log "  OK: md_to_tg_html unit"
}

test_tg_echo() {
    _tg_check_env || return 0
    _tg_resolve_bot || return 1
    _tg_setup_dirs echo
    _tg_start_telethon || { _tg_stop_bot; return 1; }
    _tg_start_bot echo || { _tg_stop_bot; return 1; }

    local marker="HELLO$RANDOM$$"
    local baseline
    baseline=$(_tg_latest_msg_id)
    _tg_send_text "Reply with exactly one word: $marker. Nothing else." >/dev/null
    log "  OK: sent $marker prompt"

    local resp resp_text
    if ! resp=$(_tg_wait_for_bot_message "$baseline" "$marker" 180); then
        log "  FAIL: bot did not reply with $marker within 180s"
        docker logs "$TG_BOT_CNAME" 2>&1 | tail -40 | sed 's/^/    /'
        _tg_stop_bot
        return 1
    fi
    resp_text=$(echo "$resp" | tail -n +2)
    assert_contains "$resp_text" "$marker" "echo reply contains $marker"
    local rc=$?
    _tg_stop_bot
    return $rc
}

test_tg_unauthorized_chat() {
    _tg_check_env || return 0
    _tg_resolve_bot || return 1
    _tg_setup_dirs unauth

    cat > "$TG_TMP/home/.aicodebox/telegram.yml" <<EOF
allowed_chats:
  - 1
default:
  workspace: .
EOF
    chmod 644 "$TG_TMP/home/.aicodebox/telegram.yml"

    _tg_start_telethon || { _tg_stop_bot; return 1; }
    _tg_start_bot unauth || { _tg_stop_bot; return 1; }

    local marker="UNAUTH$RANDOM$$"
    local baseline
    baseline=$(_tg_latest_msg_id)
    _tg_send_text "Reply with exactly $marker." >/dev/null
    log "  OK: sent $marker from unauthorized chat"

    if _tg_wait_for_bot_message "$baseline" "$marker" 15 >/dev/null; then
        log "  FAIL: bot replied to unauthorized chat"
        _tg_stop_bot
        return 1
    fi
    log "  OK: silent for unauthorized chat (no reply within 15s)"
    _tg_stop_bot
}

test_tg_long_response() {
    local cname="${CONTAINER_PREFIX}-tg-long-$$"
    local rc out
    out=$(docker run --rm --name "$cname" \
        -e "AICODEBOX_TELEGRAM_BOT_TOKEN=dummy:dummy" \
        --entrypoint python3 \
        "$IMAGE" -c '
import asyncio
from telegram.constants import MessageLimit
from aicodebox.modes.telegram.utils import send_long

class FakeMsg:
    def __init__(self, mid):
        self.message_id = mid

class FakeBot:
    def __init__(self):
        self.sent = []
        self.next_id = 0
    async def send_message(self, chat_id, text, parse_mode=None):
        self.sent.append(text)
        self.next_id += 1
        return FakeMsg(self.next_id)

async def main():
    bot = FakeBot()
    text = ("line " * 1000 + "\n") * 10
    await send_long(bot, 123, text, parse_mode="HTML")
    assert len(bot.sent) > 1, f"expected multiple chunks, got {len(bot.sent)}"
    for c in bot.sent:
        assert len(c) <= MessageLimit.MAX_TEXT_LENGTH, f"chunk len {len(c)} > limit"
    print(f"OK: send_long produced {len(bot.sent)} chunks all within limit")

asyncio.run(main())
') 2>&1
    rc=$?
    echo "$out" | sed 's/^/    /'
    if [ "$rc" != "0" ]; then
        log "  FAIL: send_long chunking (rc=$rc)"
        return 1
    fi
    log "  OK: send_long chunking"
}

ALL_TESTS+=(
    test_tg_unit_md_to_html
    test_tg_echo
    test_tg_unauthorized_chat
    test_tg_long_response
)
