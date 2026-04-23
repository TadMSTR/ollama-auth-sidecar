#!/bin/sh
# Test: /health returns 200 on each listen port without hitting mock upstream.
# Verified by checking mock-upstream access logs have no entries (server suppresses /health logs).

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_health ==="

wait_for_sidecar

# Snapshot mock-upstream log line count before health probes — previous tests may have
# left earlier log entries; we only want to assert on lines added during THIS test.
log_lines_before=$($COMPOSE logs mock-upstream 2>&1 | wc -l)

for port in 11436 11437 11438; do
    # Check body — should return "ok"
    body=$($COMPOSE exec -T sidecar wget -qO- "http://127.0.0.1:${port}/health" 2>&1)
    assert_contains "port ${port} /health body contains 'ok'" "ok" "$body"

    # Check HTTP status code separately using wget exit code and server response
    http_code=$($COMPOSE exec -T sidecar sh -c \
        "wget -qO/dev/null --server-response http://127.0.0.1:${port}/health 2>&1 | awk '/HTTP\\//{print \$2}' | tail -1")
    assert_equals "port ${port} /health returns 200" "200" "$http_code"
done

# Verify mock-upstream received no proxied requests during health checks.
# Server suppresses /health pings from its own Docker healthcheck. Any new "GET " or
# "POST " entry since snapshot_before means the sidecar incorrectly proxied /health.
new_logs=$($COMPOSE logs mock-upstream 2>&1 | tail -n +"$((log_lines_before + 1))")
assert_not_contains "/health not proxied to upstream (no GET in mock logs)" "GET " "$new_logs"
assert_not_contains "/health not proxied to upstream (no POST in mock logs)" "POST " "$new_logs"

summary
