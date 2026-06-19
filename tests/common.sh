#!/bin/bash
# Shared helpers for pibox e2e tests.
# Sourced by test.sh and every tests/test_*.sh file.

IMAGE_NAME="psyb0t/pibox"
TEST_TAG="local"
IMAGE="pibox:local"
# Use the published aicodebox base — we no longer develop the two repos
# in parallel, so the suite tests pibox on top of whatever the released
# base ships. Override with PIBOX_BASE_IMAGE if you need to test against
# a local fork of the base.
BASE_IMAGE="${PIBOX_BASE_IMAGE:-psyb0t/aicodebox:v0.8.3}"
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
    # Base image: pulled fresh by default (so the suite always tests against
    # the current released base). Skip with SKIP_BASE_PULL=1 when you've
    # already got it locally and just want to iterate on pibox changes fast.
    if [ "${SKIP_BASE_PULL:-0}" != "1" ]; then
        echo "pulling base image ($BASE_IMAGE)..."
        if ! docker pull "$BASE_IMAGE" >"$TEST_LOG_DIR/pull.log" 2>&1; then
            echo "❌ base image pull failed; see $TEST_LOG_DIR/pull.log" >&2
            tail -30 "$TEST_LOG_DIR/pull.log" >&2
            exit 1
        fi
        echo "✅ base image present"
    else
        if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
            echo "❌ SKIP_BASE_PULL=1 but $BASE_IMAGE not found locally" >&2
            exit 1
        fi
        echo "✅ SKIP_BASE_PULL=1 — using existing $BASE_IMAGE"
    fi

    # pibox image: SKIP_BUILD=1 reuses an existing $IMAGE tag, otherwise
    # always rebuild so test runs reflect current source.
    if [ "${SKIP_BUILD:-0}" = "1" ]; then
        if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
            echo "❌ SKIP_BUILD=1 but $IMAGE not found" >&2
            exit 1
        fi
        echo "✅ SKIP_BUILD=1 — using existing $IMAGE"
        return 0
    fi

    echo "building pibox image ($IMAGE) on top of $BASE_IMAGE..."
    if ! docker build --build-arg "BASE_IMAGE=$BASE_IMAGE" \
            -t "$IMAGE" "$WORKDIR" \
            >"$TEST_LOG_DIR/build.log" 2>&1; then
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
