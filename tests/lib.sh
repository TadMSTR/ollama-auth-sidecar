#!/bin/sh
# Shared test helpers

PASS=0
FAIL=0
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE="docker compose -f ${TEST_DIR}/docker-compose.test.yml"

assert_equals() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label"
        echo "        expected: $expected"
        echo "        actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*)
            echo "  PASS: $label"
            PASS=$((PASS + 1))
            ;;
        *)
            echo "  FAIL: $label"
            echo "        expected to contain: $needle"
            echo "        actual: $haystack"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*)
            echo "  FAIL: $label (found forbidden string)"
            echo "        forbidden: $needle"
            FAIL=$((FAIL + 1))
            ;;
        *)
            echo "  PASS: $label"
            PASS=$((PASS + 1))
            ;;
    esac
}

assert_exit_nonzero() {
    local label="$1" exit_code="$2"
    if [ "$exit_code" -ne 0 ]; then
        echo "  PASS: $label (exit $exit_code)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected non-zero exit, got 0)"
        FAIL=$((FAIL + 1))
    fi
}

wait_for_sidecar() {
    echo "Waiting for sidecar to be ready..."
    $COMPOSE up -d --build
    $COMPOSE wait --condition healthy sidecar 2>/dev/null || {
        # Fallback: poll
        local i=0
        while [ $i -lt 30 ]; do
            if $COMPOSE exec -T sidecar wget -q -O- http://localhost:11436/health > /dev/null 2>&1; then
                echo "Sidecar ready."
                return 0
            fi
            sleep 1
            i=$((i + 1))
        done
        echo "ERROR: Sidecar did not become healthy in time" >&2
        $COMPOSE logs sidecar >&2
        return 1
    }
}

summary() {
    echo ""
    echo "Results: ${PASS} passed, ${FAIL} failed"
    [ "$FAIL" -eq 0 ]
}
