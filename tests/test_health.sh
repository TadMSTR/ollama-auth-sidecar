#!/bin/sh
# Test: /health returns 200 on each listen port without hitting mock upstream.
# Verified by checking mock-upstream access logs have no entries (server suppresses /health logs).

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_health ==="

wait_for_sidecar

for port in 11436 11437 11438; do
    # Check body — should return "ok"
    body=$($COMPOSE exec -T sidecar wget -qO- "http://127.0.0.1:${port}/health" 2>&1)
    assert_contains "port ${port} /health body contains 'ok'" "ok" "$body"

    # Check HTTP status code separately using wget exit code and server response
    http_code=$($COMPOSE exec -T sidecar sh -c \
        "wget -qO/dev/null --server-response http://127.0.0.1:${port}/health 2>&1 | awk '/HTTP\\//{print \$2}' | tail -1")
    assert_equals "port ${port} /health returns 200" "200" "$http_code"
done

# Verify mock-upstream received no proxied requests — server suppresses its own /health
# healthcheck logs, so any "GET " or "POST " entry here means the sidecar incorrectly
# forwarded a /health probe to upstream.
upstream_logs=$($COMPOSE logs mock-upstream 2>&1)
assert_not_contains "/health not proxied to upstream (no GET in mock logs)" "GET " "$upstream_logs"
assert_not_contains "/health not proxied to upstream (no POST in mock logs)" "POST " "$upstream_logs"

summary
