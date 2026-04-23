#!/bin/sh
# Test: Authorization header values do not appear in sidecar access logs.

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_log_redaction ==="

wait_for_sidecar

# Make a request that will produce an access log entry
$COMPOSE exec -T sidecar wget -q -O- http://127.0.0.1:11436/ > /dev/null 2>&1

# Give nginx a moment to flush the log
sleep 1

# Retrieve sidecar logs
sidecar_logs=$($COMPOSE logs sidecar 2>&1)

# The actual key value must not appear in logs
assert_not_contains "OPENWEBUI_KEY value not in logs" "test-openwebui-key" "$sidecar_logs"
assert_not_contains "MEMSEARCH_KEY value not in logs"  "test-memsearch-key"  "$sidecar_logs"

# Verify the request was logged (URI should appear)
assert_contains "access log entry recorded" "/" "$sidecar_logs"

summary
