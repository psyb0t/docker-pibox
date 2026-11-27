#!/bin/bash
# Offline check that the MCP bridge gives Pi a server's instructions and
# resources, over stdio and over streamable HTTP, not only its tools.
#
# Runs the published image with this checkout's pibox/extensions/mcp-bridge/
# index.ts mounted over the shipped one, a scripted model
# (tests/fixtures/mock_llm/server.py) instead of a real one, and two copies of
# tests/fixtures/mcp_guide/server.py: one over stdio, one over HTTP behind a
# bearer token taken from an environment variable. No network, no
# credentials, no image build.
#
# Checks, from what Pi sent to the model:
#   - both servers' instructions are in the system prompt;
#   - both servers' tools and resource tools are declared;
#   - read_resource returns each server's resource text;
#   - a normal tool call still works.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${PIBOX_TEST_IMAGE:-psyb0t/pibox:latest}"

out="$(docker run --rm -i --network none --entrypoint bash \
	-v "$ROOT/pibox/extensions/mcp-bridge/index.ts:/opt/pibox/extensions/mcp-bridge/index.ts:ro" \
	-v "$ROOT/tests/fixtures:/fixtures:ro" \
	-e GUIDE_TOKEN=EXAMPLE-DO-NOT-USE \
	"$IMAGE" -s <<'INNER'
set -euo pipefail
agent="$HOME/.pi/agent"
ws=/tmp/ws
mkdir -p "$agent" "$ws"
cat >"$agent/settings.json" <<'EOF'
{ "extensions": ["/opt/pibox/extensions/mcp-bridge/index.ts"], "quietStartup": true }
EOF
cat >"$agent/models.json" <<'EOF'
{ "providers": { "mock": { "baseUrl": "http://127.0.0.1:18080/v1", "api": "openai-completions",
  "apiKey": "EXAMPLE-DO-NOT-USE", "models": [{ "id": "example-model" }] } } }
EOF
cat >"$ws/.mcp.json" <<'EOF'
{ "mcpServers": {
  "local": { "command": "python3", "args": ["/fixtures/mcp_guide/server.py", "stdio", "local"] },
  "remote": { "type": "http", "url": "http://127.0.0.1:18090/mcp",
              "headers": { "Authorization": "Bearer ${GUIDE_TOKEN}" } }
} }
EOF
cat >/tmp/scenario.json <<'EOF'
[
  { "tool": "mcp__local__read_resource", "args": { "uri": "guide://local/howto" } },
  { "tool": "mcp__remote__read_resource", "args": { "uri": "guide://remote/howto" } },
  { "tool": "mcp__remote__ping", "args": {} }
]
EOF
python3 /fixtures/mcp_guide/server.py http remote 18090 "$GUIDE_TOKEN" </dev/null >/tmp/guide.log 2>&1 &
python3 /fixtures/mock_llm/server.py 18080 /tmp/scenario.json /tmp/requests.jsonl </dev/null >/tmp/mock.log 2>&1 &
for _ in $(seq 1 100); do
	python3 -c 'import socket; [socket.create_connection(("127.0.0.1", p), 0.2).close() for p in (18080, 18090)]' 2>/dev/null && break
	sleep 0.1
done
cd "$ws"
# The script itself is on stdin; Pi would read the rest of it as prompt.
timeout 120 pi -p --mode json --no-session --provider mock --model example-model "go" </dev/null >/tmp/pi.out 2>/tmp/pi.err || true
python3 - <<'PY'
import json
reqs = [json.loads(l) for l in open("/tmp/requests.jsonl") if l.strip()]
first = reqs[0] if reqs else {}
def text(m):
    c = m.get("content")
    return c if isinstance(c, str) else " ".join(p.get("text", "") for p in c or [] if isinstance(p, dict))
system = " ".join(text(m) for m in first.get("messages", []) if m.get("role") in ("system", "developer"))
tools = [t.get("function", {}).get("name") for t in first.get("tools", [])]
results = []
for r in reqs:
    for m in r.get("messages", []):
        if m.get("role") == "tool" and text(m) not in results:
            results.append(text(m))
print(json.dumps({"requests": len(reqs), "system": system, "tools": tools, "results": results}))
PY
echo "PI_STDERR_START"; tail -20 /tmp/pi.err; echo "PI_STDERR_END"
INNER
)"

report="$(printf '%s\n' "$out" | grep -m1 '^{"requests"')" || {
	printf 'FAIL no report from the container\n%s\n' "$out" >&2
	exit 1
}

failures=0
check() {
	local label="$1" expr="$2"
	if jq -e "$expr" >/dev/null <<<"$report"; then
		printf 'PASS %s\n' "$label"
	else
		printf 'FAIL %s\n' "$label"
		failures=$((failures + 1))
	fi
}

check "stdio server instructions reach the system prompt" '.system | contains("INSTRUCTIONS_MARKER_local")'
check "HTTP server instructions reach the system prompt" '.system | contains("INSTRUCTIONS_MARKER_remote")'
check "resource tools are declared for both servers" '(.tools | index("mcp__local__read_resource")) and (.tools | index("mcp__remote__list_resources"))'
check "the stdio server's resource is read" '.results | any(contains("RESOURCE_MARKER_local"))'
check "the HTTP server's resource is read with the expanded bearer header" '.results | any(contains("RESOURCE_MARKER_remote"))'
check "a normal tool call still works" '.results | any(contains("TOOL_MARKER_remote"))'

if [ "$failures" -gt 0 ]; then
	printf '%s\n' "$out" | sed -n '/PI_STDERR_START/,/PI_STDERR_END/p' >&2
	printf '%d check(s) failed\n' "$failures" >&2
	exit 1
fi
printf 'all MCP bridge context checks passed\n'
