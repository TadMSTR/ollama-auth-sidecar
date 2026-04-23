#!/bin/sh
# Test: /health returns 200 on each listen port without hitting mock upstream.
# Verified by checking mock-upstream access logs stay empty during health probes.

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_health ==="

wait_for_sidecar

for port in 11436 11437 11438; do
    response=$($COMPOSE exec -T sidecar wget -q -S -O- "http://localhost:${port}/health" 2>&1)

    # Check 200 status
    status=$(printf '%s' "$response" | grep "HTTP/" | tail -1 | awk '{print $2}')
    assert_equals "port ${port} /health returns 200" "200" "$status"

    # Check body
    body=$(printf '%s' "$response" | tail -1)
    assert_contains "port ${port} /health body is 'ok'" "ok" "$body"
done

# Verify mock-upstream access logs have no /health entries
# (health endpoint should return without proxying)
upstream_logs=$($COMPOSE logs mock-upstream 2>&1)
assert_not_contains "/health not proxied to upstream" "/health" "$upstream_logs"

summary
