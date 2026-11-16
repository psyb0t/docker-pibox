#!/bin/bash
# Configure the bundled subagent extension and user agent definitions.
#
# Runs as aicode at every container start, before the base entrypoint.
# PIBOX_SUBAGENTS adds or removes the extension in ~/.pi/agent/settings.json
# and writes its limits to ~/.pi/agent/pibox-subagent.json. PIBOX_AGENTS_DIR
# links agent definitions into ~/.pi/agent/agents, so nothing has to be
# bind-mounted inside ~/.pi, where Docker would create root-owned parents.
# Logs go to stderr only.
set -euo pipefail

readonly PI_DIR="$HOME/.pi/agent"
readonly SETTINGS_FILE="$PI_DIR/settings.json"
readonly SUBAGENT_SETTINGS_FILE="$PI_DIR/pibox-subagent.json"
readonly AGENTS_DIR="$PI_DIR/agents"
readonly AGENTS_STATE_FILE="$PI_DIR/pibox-agents.json"
readonly SUBAGENT_EXTENSION="/opt/pibox/extensions/subagent/index.ts"
readonly DEFAULT_MAX_TASKS=8
readonly DEFAULT_MAX_CONCURRENCY=4
readonly MAX_LIMIT_DIGITS=4
readonly VALID_THINKING_LEVELS=(off minimal low medium high xhigh max)

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

fail() {
    log ERROR "$1"
    exit 1
}

refuse_symlink() {
    local file="$1"

    [[ ! -L "$file" ]] || fail "refusing symlinked $file"
    [[ ! -e "$file" || -f "$file" ]] || fail "$file must be a regular file"
}

# Write stdin to a file atomically with mode 600.
write_file() {
    local file="$1"
    local temporary_file

    refuse_symlink "$file"
    temporary_file="$(mktemp "$file.XXXXXX")"
    cat >"$temporary_file"
    chmod 600 "$temporary_file"
    mv -- "$temporary_file" "$file"
}

subagents_enabled() {
    case "${PIBOX_SUBAGENTS:-}" in
    true | 1) return 0 ;;
    false | 0 | "") return 1 ;;
    *) fail "PIBOX_SUBAGENTS must be true, false, 1 or 0" ;;
    esac
}

limit_value() {
    local name="$1"
    local default_value="$2"
    local value="${!name:-$default_value}"

    [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$name must be a positive integer"
    [[ "${#value}" -le "$MAX_LIMIT_DIGITS" ]] || fail "$name exceeds $MAX_LIMIT_DIGITS digits"
    printf '%s' "$value"
}

thinking_value() {
    local value="${PIBOX_SUBAGENT_THINKING:-}"
    local level

    [[ -n "$value" ]] || return 0
    for level in "${VALID_THINKING_LEVELS[@]}"; do
        [[ "$value" != "$level" ]] || {
            printf '%s' "$value"
            return 0
        }
    done
    fail "PIBOX_SUBAGENT_THINKING must be one of: ${VALID_THINKING_LEVELS[*]}"
}

set_extension() {
    local enabled="$1"

    refuse_symlink "$SETTINGS_FILE"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        [[ "$enabled" == true ]] || return 0
        # Same seed as init.d/10-pi-extensions.sh, which adds the MCP bridge
        # to this file later in startup.
        jq -n --arg p "$SUBAGENT_EXTENSION" '{extensions: [$p], quietStartup: true}' |
            write_file "$SETTINGS_FILE"
        return 0
    fi

    local updated
    updated="$(jq --arg p "$SUBAGENT_EXTENSION" --argjson enabled "$enabled" '
        .extensions = ((.extensions // []) - [$p] + (if $enabled then [$p] else [] end))
    ' "$SETTINGS_FILE")" || fail "settings.json is not valid JSON"
    printf '%s\n' "$updated" | write_file "$SETTINGS_FILE"
}

configure_subagents() {
    local max_tasks
    local max_concurrency
    local thinking

    if ! subagents_enabled; then
        set_extension false
        refuse_symlink "$SUBAGENT_SETTINGS_FILE"
        rm -f -- "$SUBAGENT_SETTINGS_FILE"
        return 0
    fi

    [[ -f "$SUBAGENT_EXTENSION" ]] || fail "subagent extension is missing from the image: $SUBAGENT_EXTENSION"

    max_tasks="$(limit_value PIBOX_SUBAGENT_MAX_TASKS "$DEFAULT_MAX_TASKS")"
    max_concurrency="$(limit_value PIBOX_SUBAGENT_MAX_CONCURRENCY "$DEFAULT_MAX_CONCURRENCY")"
    thinking="$(thinking_value)"

    jq -n \
        --argjson max_tasks "$max_tasks" \
        --argjson max_concurrency "$max_concurrency" \
        --arg thinking "$thinking" \
        '{maxTasks: $max_tasks, maxConcurrency: $max_concurrency}
        + (if $thinking == "" then {} else {thinking: $thinking} end)' |
        write_file "$SUBAGENT_SETTINGS_FILE"

    set_extension true
    log INFO "subagents enabled maxTasks=$max_tasks maxConcurrency=$max_concurrency thinking=${thinking:-unset}"
}

# Remove the links an earlier start created, but only links: a file the user
# put in their place is left alone.
remove_previous_agent_links() {
    local name

    [[ -e "$AGENTS_STATE_FILE" ]] || return 0
    refuse_symlink "$AGENTS_STATE_FILE"

    while IFS= read -r name; do
        [[ "$name" =~ ^[^/]+\.md$ ]] || continue
        if [[ -L "$AGENTS_DIR/$name" ]]; then
            rm -f -- "$AGENTS_DIR/$name"
        fi
    done < <(jq -r '.links[]? // empty' "$AGENTS_STATE_FILE" 2>/dev/null || true)

    rm -f -- "$AGENTS_STATE_FILE"
}

link_agents() {
    local source_dir="${PIBOX_AGENTS_DIR:-}"
    local source_file
    local name
    local -a linked=()

    remove_previous_agent_links
    [[ -n "$source_dir" ]] || return 0

    [[ "$source_dir" == /* ]] || fail "PIBOX_AGENTS_DIR must be an absolute path inside the container"
    [[ -d "$source_dir" ]] || fail "PIBOX_AGENTS_DIR is not a directory: $source_dir"
    [[ ! -L "$AGENTS_DIR" ]] || fail "refusing symlinked $AGENTS_DIR"
    mkdir -p "$AGENTS_DIR"

    shopt -s nullglob
    for source_file in "$source_dir"/*.md; do
        [[ -f "$source_file" ]] || continue
        name="${source_file##*/}"
        if [[ -e "$AGENTS_DIR/$name" || -L "$AGENTS_DIR/$name" ]]; then
            log WARN "keeping existing $AGENTS_DIR/$name instead of linking $source_file reason=agent_name_taken"
            continue
        fi
        ln -s -- "$source_file" "$AGENTS_DIR/$name"
        linked+=("$name")
    done
    shopt -u nullglob

    jq -n '{managedBy: "pibox", links: $ARGS.positional}' --args ${linked[@]+"${linked[@]}"} |
        write_file "$AGENTS_STATE_FILE"
    log INFO "linked ${#linked[@]} agent definition(s) from $source_dir"
}

mkdir -p "$PI_DIR"
configure_subagents
link_agents
