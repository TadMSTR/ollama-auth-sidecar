#!/bin/sh
# Test: when upstream sleeps longer than per-service timeout, client receives 504.
# The test-config has timeout: 30s for all services; mock-upstream /slow sleeps 3s by default.
# To test timeout: temporarily run a sidecar with a very short timeout (2s) against /slow.

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_timeouts ==="

# Bring up a one-off sidecar with a 2s timeout pointing at mock-upstream's /slow endpoint
TIMEOUT_CONFIG=$(mktemp /tmp/timeout-config-XXXXXX.yaml)
cat > "$TIMEOUT_CONFIG" <<EOF
services:
  - name: timeout-test
    listen: 11450
    upstream: http://mock-upstream:8080
    timeout: 2s
    headers:
      Authorization: "Bearer test-key"
EOF

# Run a one-off sidecar container against the already-running mock-upstream
network=$($COMPOSE ps -q mock-upstream | xargs docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)

container_id=$(docker run -d \
    --network "$network" \
    -e NGINX_BIND=0.0.0.0 \
    -e CONFIG_PATH=/etc/ollama-auth-sidecar/config.yaml \
    -v "${TIMEOUT_CONFIG}:/etc/ollama-auth-sidecar/config.yaml:ro" \
    ollama-auth-sidecar:latest 2>/dev/null || \
  docker run -d \
    --network "$network" \
    -e NGINX_BIND=0.0.0.0 \
    -e CONFIG_PATH=/etc/ollama-auth-sidecar/config.yaml \
    -v "${TIMEOUT_CONFIG}:/etc/ollama-auth-sidecar/config.yaml:ro" \
    "$(docker images --format '{{.Repository}}:{{.Tag}}' | grep ollama-auth-sidecar | head -1)")

sleep 3

# Hit /slow which sleeps 3s; with a 2s timeout we expect 504
http_code=$(docker exec "$container_id" wget -q -S -O /dev/null "http://localhost:11450/slow" 2>&1 | grep "HTTP/" | tail -1 | awk '{print $2}')

docker rm -f "$container_id" > /dev/null
rm -f "$TIMEOUT_CONFIG"

assert_equals "upstream timeout returns 504" "504" "$http_code"

summary
