#!/bin/bash
# Install Pi's subagent example extension with pibox settings.
#
# Runs at image build time. Copies the example shipped with the installed Pi
# into the destination and patches three spots so the limits and the child
# thinking level come from ~/.pi/agent/pibox-subagent.json, which
# setup-subagents.sh writes at every start. Every patch must match exactly
# once, so a Pi update that moves the code fails the build instead of
# shipping an unpatched extension.
set -euo pipefail

usage() {
    printf 'usage: %s <pi-subagent-example-dir> <destination-dir>\n' "${0##*/}" >&2
    exit 2
}

[[ "$#" -eq 2 ]] || usage

readonly SOURCE_DIR="$1"
readonly DESTINATION_DIR="$2"
readonly INDEX_FILE="$DESTINATION_DIR/index.ts"

log() {
    local level="$1"
    shift

    jq -cn \
        --arg time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg level "$level" \
        --arg file "${BASH_SOURCE[1]##*/}" \
        --argjson line "${BASH_LINENO[0]}" \
        --arg func "${FUNCNAME[1]:-main}" \
        --arg msg "$*" \
        '$ARGS.named' >&2
}

# Replace one literal block in INDEX_FILE, failing unless it occurs once.
replace_once() {
    local description="$1"
    local old="$2"
    local new="$3"

    OLD="$old" NEW="$new" perl -0777 -pi -e '
        my $count = () = /\Q$ENV{OLD}\E/g;
        die "expected exactly one match, found $count\n" unless $count == 1;
        s/\Q$ENV{OLD}\E/$ENV{NEW}/;
    ' "$INDEX_FILE" || {
        log ERROR "subagent patch did not apply: $description"
        exit 1
    }
}

[[ -f "$SOURCE_DIR/index.ts" && -f "$SOURCE_DIR/agents.ts" ]] || {
    log ERROR "subagent example not found in $SOURCE_DIR"
    exit 1
}

mkdir -p "$DESTINATION_DIR"
cp -R -- "$SOURCE_DIR"/. "$DESTINATION_DIR"/

replace_once "parallel limits" \
    'const MAX_PARALLEL_TASKS = 8;
const MAX_CONCURRENCY = 4;' \
    '// pibox: limits and the thinking level for subagents that name their own
// model come from pibox-subagent.json, written from PIBOX_SUBAGENT_* at start.
interface PiboxSubagentSettings {
	maxTasks?: number;
	maxConcurrency?: number;
	thinking?: ThinkingLevel;
}

function loadPiboxSubagentSettings(): PiboxSubagentSettings {
	try {
		return JSON.parse(fs.readFileSync(path.join(getAgentDir(), "pibox-subagent.json"), "utf-8"));
	} catch {
		return {};
	}
}

const PIBOX_SUBAGENT_SETTINGS = loadPiboxSubagentSettings();
const MAX_PARALLEL_TASKS = PIBOX_SUBAGENT_SETTINGS.maxTasks ?? 8;
const MAX_CONCURRENCY = PIBOX_SUBAGENT_SETTINGS.maxConcurrency ?? 4;'

replace_once "thinking level for agents with their own model" \
    '	if (inheritsDispatchConfig && dispatchDefaults.thinkingLevel) {
		args.push("--thinking", dispatchDefaults.thinkingLevel);
	}' \
    '	if (inheritsDispatchConfig && dispatchDefaults.thinkingLevel) {
		args.push("--thinking", dispatchDefaults.thinkingLevel);
	} else if (!inheritsDispatchConfig && PIBOX_SUBAGENT_SETTINGS.thinking) {
		args.push("--thinking", PIBOX_SUBAGENT_SETTINGS.thinking);
	}'

log INFO "installed patched subagent extension in $DESTINATION_DIR"
