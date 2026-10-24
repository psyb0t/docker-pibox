#!/bin/bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
# shellcheck source=test-common.sh
source "$REPO/tests/test-common.sh"
trap 'log ERROR "GitHub Action test failed at line $LINENO"' ERR
readonly LOG_FILE="${LOG_FILE:-/tmp/pibox-action-tests.log}"
exec > >(tee -a "$LOG_FILE") 2>&1
scratch="$(mktemp -d)"
readonly scratch
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/context" "$scratch/runner"
cp "$REPO/tests/fixtures/action/docker" "$scratch/bin/docker"
chmod +x "$scratch/bin/docker"
export PATH="$scratch/bin:$PATH"
export GITHUB_ACTION_PATH="$REPO" GITHUB_WORKSPACE="$scratch/context"
export RUNNER_TEMP="$scratch/runner" GITHUB_OUTPUT="$scratch/github-output"
export PIBOX_ACTION_API_KEY=EXAMPLE-DO-NOT-USE
export PIBOX_ACTION_BASE_URL=https://example.invalid/v1
export PIBOX_ACTION_MODEL=example-model PIBOX_ACTION_PROMPT='Read context and write the requested file'
export PIBOX_ACTION_CONTEXT=. PIBOX_ACTION_STREAM=true PIBOX_ACTION_FORMAT=json

run_case() {
    local scenario="$1"
    printf '%s' "$scenario" >"$scratch/bin/scenario"
    : >"$scratch/bin/calls"
    : >"$GITHUB_OUTPUT"
    bash "$REPO/scripts/github-action.sh" >"$scratch/action-log" 2>&1
}
result_value() {
    sed '1,2d;$d' "$GITHUB_OUTPUT"
}

run_case success || {
    cat "$scratch/action-log"
    fail "default action failed"
}
[[ "$(result_value)" == $'final Ω\n::warning::untrusted' ]] || fail "final result differs"
grep -Fq '[tool] bash' "$scratch/action-log" || fail "missing live tool log"
grep -Fq '[result] tool result' "$scratch/action-log" || fail "missing live tool result"
grep -Fq '::stop-commands::PIBOX_' "$scratch/action-log" || fail "model logs can issue workflow commands"
grep -Fq ':/context:ro' "$scratch/bin/calls" || fail "context is not read-only"
grep -Fq -- '--no-session' "$scratch/bin/calls" || fail "action persists sessions"

PIBOX_ACTION_STREAM=false run_case success || fail "nonstreamed action failed"
[[ "$(result_value)" == $'final Ω\n::warning::untrusted' ]] || fail "stream changes result"
if grep -Fq '[tool]' "$scratch/action-log"; then fail "stream=false logged model activity"; fi
PIBOX_ACTION_FORMAT=text run_case text || fail "text action failed"
[[ "$(result_value)" == 'native text' ]] || fail "text output differs"
PIBOX_ACTION_FORMAT=stream-json run_case success || fail "native stream action failed"
result_value | jq -se 'any(.[]; .type == "agent_end")' >/dev/null || fail "raw native events missing"

printf '%s' 'file prompt' >"$scratch/prompt"
PIBOX_ACTION_PROMPT='' PIBOX_ACTION_PROMPT_FILE="$scratch/prompt" run_case success || fail "prompt-file action failed"

for scenario in pull-failure run-failure provider-error aborted no-assistant empty malformed missing-end; do
    if run_case "$scenario"; then fail "accepted $scenario"; fi
done
for setting in \
    'PIBOX_ACTION_API_KEY=' 'PIBOX_ACTION_BASE_URL=' 'PIBOX_ACTION_MODEL=' \
    'PIBOX_ACTION_API=invalid' 'PIBOX_ACTION_STREAM=maybe' 'PIBOX_ACTION_FORMAT=xml' \
    'PIBOX_ACTION_THINKING=invalid' 'PIBOX_ACTION_PROMPT=' \
    'PIBOX_ACTION_OUTPUT=.' 'PIBOX_ACTION_IMAGE=--help' \
    "PIBOX_ACTION_PROMPT_FILE=$scratch/prompt"; do
    if (
        export "${setting?}"
        run_case success
    ); then fail "accepted invalid input: ${setting%%=*}"; fi
    [[ ! -s "$scratch/bin/calls" ]] || fail "invalid input reached Docker"
done
if (
    export PIBOX_ACTION_API_KEY=$'invalid\nkey'
    run_case success
); then fail "accepted multiline secret"; fi
if (
    export PIBOX_ACTION_PROMPT
    PIBOX_ACTION_PROMPT="$(printf '%100001s' x)"
    run_case success
); then fail "accepted oversized prompt"; fi
log INFO "GitHub Action contract checks passed"
