#!/bin/bash
# Shared helpers for pibox e2e tests.
# Sourced by test.sh and every tests/test_*.sh file.

IMAGE_NAME="psyb0t/pibox"
TEST_TAG="local"
IMAGE="pibox:local"
BASE_IMAGE="aicodebox-base:local"
CONTAINER_PREFIX="pibox-test"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTRA_CONTAINERS=()
ALL_TESTS=()

# load .env.test from repo root
ENV_FILE="$WORKDIR/.env.test"
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ $ENV_FILE not found — copy .env.test.example and fill it in" >&2
    exit 1
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# require Z.AI Anthropic-compatible test creds
: "${ANTHROPIC_AUTH_TOKEN:?ANTHROPIC_AUTH_TOKEN must be set in .env.test}"
: "${ANTHROPIC_BASE_URL:?ANTHROPIC_BASE_URL must be set in .env.test}"

# default test model — Z.AI's GLM-4.6 is fast and cheap
TEST_MODEL="${ANTHROPIC_MODEL:-glm-4.6}"

# common docker run args — every test uses these
DOCKER_RUN_BASE=(
    --rm
    --network host
    -e "ANTHROPIC_AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN"
    -e "ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
    -e "ANTHROPIC_MODEL=$TEST_MODEL"
    -e "AICODEBOX_WORKSPACE=/workspace"
)

# pi reads ANTHROPIC_API_KEY too (per its --help). Z.AI accepts the same token.
DOCKER_RUN_BASE+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_AUTH_TOKEN")

# ── per-test logging ──────────────────────────────────────────────────────────

CURRENT_LOG_FILE=""

_begin_test_log() {
    local name="$1"
    CURRENT_LOG_FILE="${TEST_LOG_DIR:-/tmp}/${name}.log"
    : > "$CURRENT_LOG_FILE"
    export CURRENT_LOG_FILE
}

log() {
    echo "$*"
}

# ── assertions ────────────────────────────────────────────────────────────────

assert_eq() {
    local actual="$1" expected="$2" name="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected '$expected', got '$actual'"
    return 1
}

assert_contains() {
    local actual="$1" expected="$2" name="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected to contain '$expected'"
    echo "  actual: ${actual:0:500}"
    return 1
}

assert_not_empty() {
    local actual="$1" name="$2"
    if [ -n "$actual" ]; then
        echo "  OK: $name"
        return 0
    fi
    echo "  FAIL: $name: expected non-empty output"
    return 1
}

assert_exit_code() {
    local actual="$1" expected="$2" name="$3"
    assert_eq "$actual" "$expected" "$name (exit code)"
}

# ── lifecycle ─────────────────────────────────────────────────────────────────

setup() {
    local base_dir="$WORKDIR/../docker-aicodebox"
    if [ ! -d "$base_dir" ]; then
        echo "❌ base repo not found at $base_dir — clone psyb0t/docker-aicodebox next to this repo" >&2
        exit 1
    fi
    echo "building aicodebox-base image ($BASE_IMAGE) from $base_dir..."
    if ! docker build -t "$BASE_IMAGE" "$base_dir" \
            >"$TEST_LOG_DIR/build.log" 2>&1; then
        echo "❌ base image build failed; see $TEST_LOG_DIR/build.log" >&2
        tail -50 "$TEST_LOG_DIR/build.log" >&2
        exit 1
    fi
    echo "✅ base image built"

    echo "building pibox image ($IMAGE)..."
    if ! docker build -t "$IMAGE" "$WORKDIR" \
            >>"$TEST_LOG_DIR/build.log" 2>&1; then
        echo "❌ pibox image build failed; see $TEST_LOG_DIR/build.log" >&2
        tail -50 "$TEST_LOG_DIR/build.log" >&2
        exit 1
    fi
    echo "✅ pibox image built"
}

_sweep_test_containers() {
    local names
    names=$(docker ps -a --filter "name=^${CONTAINER_PREFIX}-" --format '{{.Names}}' 2>/dev/null)
    if [ -n "$names" ]; then
        echo "$names" | xargs -r docker rm -f >/dev/null 2>&1 || true
    fi
}

cleanup() {
    _sweep_test_containers
    # Do NOT remove the base image — would force a slow rebuild next run.
    if [ "${KEEP_IMAGE:-0}" != "1" ]; then
        docker rmi -f "$IMAGE" >/dev/null 2>&1 || true
    fi
}

test_setup() { :; }
test_teardown() {
    _sweep_test_containers
    EXTRA_CONTAINERS=()
}

usage() {
    echo "usage: $0 [test_name ...]"
    echo ""
    echo "available tests:"
    for t in "${ALL_TESTS[@]}"; do
        echo "  $t"
    done
}

# ── helper: run pi inside the test image and capture stdout ───────────────────
# args: <prompt>
# pi's non-interactive mode is `pi -p <prompt>`. The image entrypoint passes
# argv straight through to pi, so we send `-p <prompt>` as the container args.
run_pi() {
    local prompt="$1"
    local cname="${CONTAINER_PREFIX}-pi-$$"
    EXTRA_CONTAINERS+=("$cname")
    docker run --name "$cname" "${DOCKER_RUN_BASE[@]}" \
        -e "AICODEBOX_CONTAINER_NAME=$cname" \
        "$IMAGE" -p --model "$TEST_MODEL" --provider anthropic "$prompt"
    RC=$?
    docker rm -f "$cname" >/dev/null 2>&1 || true
    return $RC
}
