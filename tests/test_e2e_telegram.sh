#!/bin/bash
# End-to-end telegram tests ported from claudebox's test_e2e_telegram.sh.
# Drives the user side of the chat with psyb0t/telethon-plus (HTTP wrapper
# around a real Telegram MTProto userbot) while a real pibox container runs
# cron+telegram mode against the same chat.
#
# Tests in this file (other claudebox tests are covered elsewhere):
#   - test_e2e_cron_message_renders_without_placeholder_leak
#       cron output → bot message → markdown rendered correctly (no PUA leak,
#       no bare CB\d sentinel leak), and telegram.json gets written into the
#       per-run history dir with chat_id + message_id.
#   - test_e2e_reply_to_non_cron_bot_message_acknowledged
#       user reply to a non-cron bot text → bot acknowledges and logs
#       "reply to message <id> kind=text".
#
# Reuses the _ct_* helpers from tests/test_cron_telegram.sh (telethon HTTP
# wrapper, container lifecycle). Required env (loaded by common.sh from
# .env.test, which is gitignored):
#
#   AICODEBOX_TELEGRAM_BOT_TOKEN
#   TELEGRAM_CHAT_ID
#   TELETHON_API_ID, TELETHON_API_HASH, TELETHON_SESSION, TELETHON_AUTH_KEY
#
# Use the SAME telethon user + auth key as the rest of the suite — the test
# infrastructure is shared.

# ── test 1: cron message renders cleanly + telegram.json written ─────────────

test_e2e_cron_message_renders_without_placeholder_leak() {
    _ct_check_env || return 0
    _ct_resolve_bot || return 1
    _ct_setup_dirs leakcheck
    _ct_start_telethon || { _ct_stop_container; return 1; }

    local yaml
    yaml=$(cat <<EOF
jobs:
  - name: leakcheck
    schedule: "*/10 * * * * *"
    telegram_chat_id: $TELEGRAM_CHAT_ID
    model: $TEST_MODEL
    no_continue: true
    instruction: |
      Respond with exactly this markdown text and nothing else, no preamble:

      ## **Logs**
      Mostly boring-ass cron jobs.

      ## **Docker Health**
      \`mt5-httpapi-mt5-1\` is **unhealthy**.
EOF
)
    _ct_start_container leakcheck "$yaml" || { _ct_stop_container; return 1; }

    local baseline
    baseline=$(_ct_latest_msg_id)

    local result bot_msg_id bot_msg_text
    if ! result=$(_ct_wait_for_bot_message "$baseline" "Logs" 120); then
        log "  FAIL: no bot message containing 'Logs' arrived within 120s"
        docker logs "$CT_CNAME" 2>&1 | tail -50 | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    bot_msg_id=$(echo "$result" | head -1)
    bot_msg_text=$(echo "$result" | tail -n +2)
    log "  OK: bot delivered cron message id=$bot_msg_id"

    local leak
    leak=$(TEXT="$bot_msg_text" python3 - <<'PY'
import os, re
text = os.environ["TEXT"]
for ch in ("", "", "\x00"):
    if ch in text:
        print(f"PUA/NUL leak: {ch!r}"); break
else:
    m = re.search(r"\bCB\d+\b", text)
    if m:
        print(f"sentinel leak: {m.group()!r}")
PY
)
    if [ -n "$leak" ]; then
        log "  FAIL: $leak"
        log "  raw bot message:"
        echo "$bot_msg_text" | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    log "  OK: rendered text has no PUA/NUL/sentinel leak"

    local rc=0
    assert_contains "$bot_msg_text" "Logs"          "heading 'Logs' present"          || rc=1
    assert_contains "$bot_msg_text" "Docker Health" "heading 'Docker Health' present" || rc=1

    local history_root="$CT_TMP/home/.aicodebox/cron/history"
    local tg_json
    tg_json=$(find "$history_root" -name 'telegram.json' 2>/dev/null | head -1)
    if [ -z "$tg_json" ]; then
        log "  FAIL: telegram.json was not written into history dir"
        find "$history_root" -type f 2>&1 | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    log "  OK: telegram.json written at $tg_json"

    local saved_chat_id saved_msg_id
    saved_chat_id=$(python3 -c "import json; print(json.load(open('$tg_json'))['chat_id'])")
    saved_msg_id=$(python3 -c  "import json; print(json.load(open('$tg_json'))['message_id'])")
    assert_eq "$saved_chat_id" "$TELEGRAM_CHAT_ID" "telegram.json chat_id matches" || rc=1
    # Bot API (what the bot writes) and telethon's MTProto report different
    # ids for the same logical message — just sanity-check positive int.
    if ! [[ "$saved_msg_id" =~ ^[0-9]+$ ]] || [ "$saved_msg_id" -le 0 ]; then
        log "  FAIL: telegram.json message_id is not a positive int: $saved_msg_id"
        rc=1
    else
        log "  OK: telegram.json message_id is a positive int ($saved_msg_id, Bot API view)"
    fi

    _ct_stop_container
    return $rc
}

# ── test 4: reply to a non-cron bot text → claude responds + kind=text logged ─

test_e2e_reply_to_non_cron_bot_message_acknowledged() {
    _ct_check_env || return 0
    _ct_resolve_bot || return 1
    _ct_setup_dirs nonecron_reply
    _ct_start_telethon || { _ct_stop_container; return 1; }

    # cron yaml that never fires — we only want the telegram side alive.
    local yaml
    yaml=$(cat <<'EOF'
jobs:
  - name: never_fires
    schedule: "0 0 1 1 *"
    instruction: never fires
EOF
)
    _ct_start_container nonecron_reply "$yaml" || { _ct_stop_container; return 1; }
    sleep 4  # let the bot register its long-poll

    local seed_marker="SEED$RANDOM$$"
    local b1 seed_resp seed_resp_id
    b1=$(_ct_latest_msg_id)
    _ct_send_text "Reply with exactly the token $seed_marker and nothing else." >/dev/null
    if ! seed_resp=$(_ct_wait_for_bot_message "$b1" "$seed_marker" 180); then
        log "  FAIL: bot did not produce seed response with $seed_marker"
        docker logs "$CT_CNAME" 2>&1 | tail -50 | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    seed_resp_id=$(echo "$seed_resp" | head -1)
    log "  OK: seed bot message id=$seed_resp_id ready to be replied to"

    local reply_marker="REPL$RANDOM$$"
    local b2
    b2=$(_ct_latest_msg_id)
    _ct_reply "Reply with exactly the token $reply_marker and nothing else." "$seed_resp_id" >/dev/null

    local resp2 resp2_text
    if ! resp2=$(_ct_wait_for_bot_message "$b2" "$reply_marker" 180); then
        log "  FAIL: bot did not respond to non-cron reply with $reply_marker"
        docker logs "$CT_CNAME" 2>&1 | tail -50 | sed 's/^/    /'
        _ct_stop_container
        return 1
    fi
    resp2_text=$(echo "$resp2" | tail -n +2)
    local rc=0
    assert_contains "$resp2_text" "$reply_marker" "bot responded to non-cron reply" || rc=1

    # The bot logs the Bot API message id; telethon's seed_resp_id is the
    # MTProto view of the same logical message — we can't trivially translate
    # so just assert *some* "reply to message <int> kind=text" line was logged.
    local logs
    logs=$(docker logs "$CT_CNAME" 2>&1)
    if echo "$logs" | grep -Eq "reply to message [0-9]+ kind=text"; then
        log "  OK: bot logged non-cron reply with kind=text"
    else
        log "  FAIL: bot did not log a 'reply to message <id> kind=text' line"
        echo "$logs" | tail -40 | sed 's/^/    /'
        rc=1
    fi

    _ct_stop_container
    return $rc
}

ALL_TESTS+=(
    test_e2e_cron_message_renders_without_placeholder_leak
    test_e2e_reply_to_non_cron_bot_message_acknowledged
)
