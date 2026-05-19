#!/bin/bash
# E2E test runner — loads tests/test_*.sh, builds images, runs tests.
# Usage:
#   ./test.sh                 # run every test
#   ./test.sh test_smoke_pi   # run a single test
#   KEEP_IMAGE=1 ./test.sh    # don't rmi pibox:local at the end
set -u

cd "$(dirname "$0")"

export TEST_LOG_DIR="${TEST_LOG_DIR:-$(pwd)/tests/.logs}"
mkdir -p "$TEST_LOG_DIR"

# shellcheck disable=SC1091
source tests/common.sh

for f in tests/test_*.sh; do
    # shellcheck disable=SC1090
    source "$f"
done

REQUESTED=("$@")
if [ "${#REQUESTED[@]}" -eq 0 ]; then
    REQUESTED=("${ALL_TESTS[@]}")
fi

setup
trap cleanup EXIT

PASSED=()
FAILED=()

for t in "${REQUESTED[@]}"; do
    echo ""
    echo "▶ $t"
    _begin_test_log "$t"
    test_setup
    if "$t"; then
        echo "✅ $t"
        PASSED+=("$t")
    else
        echo "❌ $t"
        FAILED+=("$t")
    fi
    test_teardown
done

echo ""
echo "──── summary ────"
echo "passed: ${#PASSED[@]}"
echo "failed: ${#FAILED[@]}"
if [ "${#FAILED[@]}" -gt 0 ]; then
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
