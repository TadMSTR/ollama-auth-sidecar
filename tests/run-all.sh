#!/bin/sh
# Run all integration tests. Brings up the test stack once, runs all tests, tears down.

set -eu

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE="docker compose -f ${TEST_DIR}/docker-compose.test.yml"

cleanup() {
    echo ""
    echo "--- Tearing down test stack ---"
    $COMPOSE down --remove-orphans --volumes 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Building test images ==="
$COMPOSE build

echo ""
echo "=== Starting test stack ==="
$COMPOSE up -d

TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
    local script="$1"
    echo ""
    echo "---"
    sh "$script"
    # parse pass/fail counts from output (best-effort; failures also cause non-zero exit)
}

run_test "${TEST_DIR}/test_header_injection.sh"
run_test "${TEST_DIR}/test_streaming.sh"
run_test "${TEST_DIR}/test_health.sh"
run_test "${TEST_DIR}/test_log_redaction.sh"

# Config validation tests don't need the running stack
$COMPOSE down 2>/dev/null || true
run_test "${TEST_DIR}/test_config_validation.sh"

# Timeout test brings its own container
$COMPOSE up -d mock-upstream
sleep 2
run_test "${TEST_DIR}/test_timeouts.sh"

echo ""
echo "=== All tests complete ==="
