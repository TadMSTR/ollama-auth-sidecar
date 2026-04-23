#!/bin/sh
# Test: container exits non-zero with expected error for each bad config fixture.

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_config_validation ==="

FIXTURES_DIR="$(dirname "$0")/fixtures/bad-configs"

# image tag used during tests
IMAGE=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "^ollama-auth-sidecar" | head -1)
[ -n "$IMAGE" ] || IMAGE="ollama-auth-sidecar:latest"

run_bad_config() {
    local fixture="$1"
    local expected_substr="$2"
    local label
    label=$(basename "$fixture" .yaml)

    output=$(docker run --rm \
        -e TEST_KEY=some-value \
        -v "${fixture}:/etc/ollama-auth-sidecar/config.yaml:ro" \
        "$IMAGE" 2>&1) && exit_code=0 || exit_code=$?

    assert_exit_nonzero "exits non-zero for $label" "$exit_code"
    if [ -n "$expected_substr" ]; then
        assert_contains "error mentions '$expected_substr' for $label" "$expected_substr" "$output"
    fi
}

run_bad_config "${FIXTURES_DIR}/missing-name.yaml"        "missing required field"
run_bad_config "${FIXTURES_DIR}/missing-upstream.yaml"    "missing required field"
run_bad_config "${FIXTURES_DIR}/port-out-of-range.yaml"   "1024"
run_bad_config "${FIXTURES_DIR}/duplicate-port.yaml"      "already used"
run_bad_config "${FIXTURES_DIR}/unresolved-env-var.yaml"  "unset or empty"
run_bad_config "${FIXTURES_DIR}/invalid-upstream-url.yaml" "not a valid"
run_bad_config "${FIXTURES_DIR}/header-with-bare-dollar.yaml" "bare '\$'"

summary
