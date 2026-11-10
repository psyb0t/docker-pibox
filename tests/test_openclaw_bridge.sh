#!/usr/bin/env bash
# Contract test for the OpenClaw stdio-to-HTTP MCP bridge
# (.agents/plugins/pibox/bin/cli.js). A stub mcp-remote prints the argv the
# bridge hands it, so the test checks the target URL and headers without a
# network or a pibox server. Node comes from the base image.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
# shellcheck source=test-common.sh
source "$REPO/tests/test-common.sh"
trap 'log ERROR "OpenClaw bridge contract failed at line $LINENO"' ERR
readonly BASE_IMAGE="${BASE_IMAGE:-psyb0t/aicodebox:v0.18.4@sha256:4962442c598356a0e570ea16d6ab22af83a5c4fb874165665010b83b256b00e9}"
readonly PLUGIN_DIR="$REPO/.agents/plugins/pibox"

# run_bridge [docker -e args...] prints the stub's argv as a JSON array.
run_bridge() {
    docker run --rm \
        --mount "type=bind,src=$PLUGIN_DIR/bin,dst=/plugin/bin,readonly" \
        --mount "type=bind,src=$PLUGIN_DIR/package.json,dst=/plugin/package.json,readonly" \
        "$@" --entrypoint bash "$BASE_IMAGE" -c '
            set -euo pipefail
            stub=/plugin/node_modules/mcp-remote
            mkdir -p "$stub/dist"
            printf "%s\n" "{\"name\":\"mcp-remote\",\"version\":\"0.0.0\"}" >"$stub/package.json"
            printf "%s\n" "console.log(JSON.stringify(process.argv.slice(2)));" >"$stub/dist/proxy.js"
            exec node /plugin/bin/cli.js
        '
}

target_url() {
    run_bridge "$@" | jq -r '.[0]'
}

actual="$(target_url -e PIBOX_URL=http://example.invalid:8080)"
[[ "$actual" == "http://example.invalid:8080/mcp/" ]] || fail "PIBOX_URL default: got $actual"

actual="$(target_url -e PIBOX_URL=http://example.invalid:8080/)"
[[ "$actual" == "http://example.invalid:8080/mcp/" ]] || fail "PIBOX_URL trailing slash: got $actual"

actual="$(target_url -e PIBOX_MCP_URL=http://example.invalid:8081/)"
[[ "$actual" == "http://example.invalid:8081/" ]] || fail "PIBOX_MCP_URL sidecar root: got $actual"

actual="$(target_url -e PIBOX_URL=http://example.invalid:8080 -e PIBOX_MCP_URL=http://example.invalid:8081/)"
[[ "$actual" == "http://example.invalid:8081/" ]] || fail "PIBOX_MCP_URL must win over PIBOX_URL: got $actual"

args="$(run_bridge -e PIBOX_URL=http://example.invalid:8080 -e PIBOX_MCP_MODE_TOKEN=EXAMPLE-DO-NOT-USE)"
jq -e 'index("--header") as $i | $i != null and .[$i + 1] == "Authorization: Bearer EXAMPLE-DO-NOT-USE"' \
    <<<"$args" >/dev/null || fail "bearer header missing: $args"

if run_bridge >/dev/null 2>&1; then
    fail "bridge started without PIBOX_URL or PIBOX_MCP_URL"
fi
log INFO "OpenClaw bridge contract passed"
