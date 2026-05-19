#!/bin/bash
# Verifies pibox/extensions/mcp-bridge/index.ts actually wires workspace
# .mcp.json files into pi as tools. Drops a tiny stdio MCP server into the
# workspace, points .mcp.json at it, runs pi non-interactively, asserts pi
# invoked the tool (the tool produces a marker no other code path can).

_mcp_bridge_setup() {
    MCP_TEST_DIR="$WORKDIR/tests/logs/mcp-bridge-$$"
    rm -rf "$MCP_TEST_DIR"
    mkdir -p "$MCP_TEST_DIR"
    chmod 777 "$MCP_TEST_DIR"

    cp "$WORKDIR/tests/fixtures/mcp_echo/server.py" "$MCP_TEST_DIR/testsrv.py"
    chmod 755 "$MCP_TEST_DIR/testsrv.py"

    cat > "$MCP_TEST_DIR/.mcp.json" <<'EOF'
{
  "mcpServers": {
    "testsrv": {
      "command": "python3",
      "args": ["/workspace/testsrv.py"]
    }
  }
}
EOF
}

test_mcp_bridge_pulls_workspace_mcp_json() {
    _mcp_bridge_setup
    local cname="${CONTAINER_PREFIX}-mcp-bridge-$$"
    EXTRA_CONTAINERS+=("$cname")

    local prompt
    prompt="There is a tool named mcp__testsrv__echo registered in this session. \
Call it exactly once with arguments {\"text\":\"HELLO\"}. \
After the tool call, output the tool's response text verbatim and nothing else."

    local out rc
    out=$(docker run --rm --name "$cname" \
        --network host \
        -v "$MCP_TEST_DIR:/workspace" \
        -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
        -e "ANTHROPIC_MODEL=$TEST_MODEL" \
        -e "AICODEBOX_WORKSPACE=/workspace" \
        -e "AICODEBOX_CONTAINER_NAME=$cname" \
        "$IMAGE" -p --no-session --provider anthropic --model "$TEST_MODEL" \
        --thinking medium "$prompt" 2>&1)
    rc=$?

    if [ "$rc" != "0" ]; then
        log "  FAIL: pi exited $rc"
        log "  output: ${out:0:1500}"
        return 1
    fi
    assert_contains "$out" "MCP_BRIDGE_OK:HELLO" \
        "pi response contains MCP tool marker (proves bridge registered + invoked the tool)"
}

test_mcp_bridge_absent_mcp_json_is_silent() {
    # No .mcp.json in workspace → bridge must load without error and pi
    # must still produce normal output. Guards against the bridge breaking
    # pi when there are no MCP servers configured.
    local empty_dir="$WORKDIR/tests/logs/mcp-bridge-empty-$$"
    rm -rf "$empty_dir"
    mkdir -p "$empty_dir"
    chmod 777 "$empty_dir"

    local cname="${CONTAINER_PREFIX}-mcp-empty-$$"
    EXTRA_CONTAINERS+=("$cname")

    local out rc
    out=$(docker run --rm --name "$cname" \
        --network host \
        -v "$empty_dir:/workspace" \
        -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN" \
        -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL" \
        -e "ANTHROPIC_MODEL=$TEST_MODEL" \
        -e "AICODEBOX_WORKSPACE=/workspace" \
        -e "AICODEBOX_CONTAINER_NAME=$cname" \
        "$IMAGE" -p --no-session --provider anthropic --model "$TEST_MODEL" \
        "Reply with the single word OK and nothing else." 2>&1)
    rc=$?

    if [ "$rc" != "0" ]; then
        log "  FAIL: pi exited $rc without .mcp.json"
        log "  output: ${out:0:1000}"
        return 1
    fi
    if echo "$out" | grep -q "\[mcp-bridge\]"; then
        log "  FAIL: bridge emitted errors when no .mcp.json present"
        log "  output: ${out:0:1000}"
        return 1
    fi
    assert_contains "$out" "OK" "pi works normally when .mcp.json absent"
}

ALL_TESTS+=(
    test_mcp_bridge_pulls_workspace_mcp_json
    test_mcp_bridge_absent_mcp_json_is_silent
)
