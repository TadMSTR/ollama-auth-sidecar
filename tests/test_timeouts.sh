#!/bin/sh
# Test: when upstream sleeps longer than the configured timeout, client gets 504.
# Runs a one-off sidecar with a 2s timeout against mock-upstream's /slow endpoint
# (which sleeps 3s by default as set in docker-compose.test.yml SLOW_SECONDS=3).

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_timeouts ==="

# Ensure mock-upstream is running (run-all.sh starts it before this test)
mock_id=$($COMPOSE ps -q mock-upstream 2>/dev/null | head -1)
[ -n "$mock_id" ] || {
    echo "Starting mock-upstream..."
    $COMPOSE up -d mock-upstream
    sleep 3
    mock_id=$($COMPOSE ps -q mock-upstream | head -1)
}
[ -n "$mock_id" ] || die "Could not start mock-upstream"

# Find the network mock-upstream is on
network=$(docker inspect "$mock_id" \
    --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)

# Resolve sidecar image (same priority as test_config_validation.sh)
if docker image inspect ollama-auth-sidecar:ci > /dev/null 2>&1; then
    IMAGE="ollama-auth-sidecar:ci"
elif docker image inspect ollama-auth-sidecar-test-sidecar:latest > /dev/null 2>&1; then
    IMAGE="ollama-auth-sidecar-test-sidecar:latest"
elif docker image inspect ollama-auth-sidecar:dev > /dev/null 2>&1; then
    IMAGE="ollama-auth-sidecar:dev"
else
    echo "ERROR: no sidecar image found" >&2; exit 1
fi

# Write a minimal config with a 2s timeout (shorter than mock-upstream's 3s sleep)
TIMEOUT_CONFIG=$(mktemp /tmp/timeout-config-XXXXXX.yaml)
cat > "$TIMEOUT_CONFIG" <<'YAML'
services:
  - name: timeout-test
    listen: 11450
    upstream: http://mock-upstream:8080
    timeout: 2s
    headers:
      Authorization: "Bearer ${TEST_KEY}"
YAML

container_id=$(docker run -d \
    --network "$network" \
    -e NGINX_BIND=0.0.0.0 \
    -e TEST_KEY=test-key \
    --tmpfs /tmp:uid=101,gid=101 \
    --tmpfs /var/cache/nginx:uid=101,gid=101 \
    --tmpfs /var/run:uid=101,gid=101 \
    -v "${TIMEOUT_CONFIG}:/etc/ollama-auth-sidecar/config.yaml:ro" \
    "$IMAGE")

# Wait for nginx to start
sleep 4

# Hit /slow (upstream sleeps 3s); with 2s timeout we expect 504
http_code=$(docker exec "$container_id" \
    wget -qO/dev/null --server-response "http://127.0.0.1:11450/slow" 2>&1 \
    | awk '/HTTP\//{print $2}' | tail -1)

docker rm -f "$container_id" > /dev/null
rm -f "$TIMEOUT_CONFIG"

assert_equals "upstream timeout returns 504" "504" "$http_code"

summary
