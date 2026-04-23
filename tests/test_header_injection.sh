#!/bin/sh
# Test: injected Authorization and X-Client-Name headers arrive at mock upstream

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_header_injection ==="

wait_for_sidecar

# Query through openwebui port (11436) — expects OPENWEBUI_KEY and X-Client-Name: openwebui
response=$($COMPOSE exec -T sidecar wget -q -O- http://127.0.0.1:11436/)
auth_header=$(printf '%s' "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('authorization',''))")
client_name=$(printf '%s' "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('x-client-name',''))")

assert_equals "openwebui Authorization header" "Bearer test-openwebui-key" "$auth_header"
assert_equals "openwebui X-Client-Name header" "openwebui" "$client_name"

# Query through memsearch port (11437) — expects MEMSEARCH_KEY and extra header
response2=$($COMPOSE exec -T sidecar wget -q -O- http://127.0.0.1:11437/)
auth_header2=$(printf '%s' "$response2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('authorization',''))")
client_name2=$(printf '%s' "$response2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('x-client-name',''))")
extra_header=$(printf '%s' "$response2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('x-client-extra',''))")

assert_equals "memsearch Authorization header" "Bearer test-memsearch-key" "$auth_header2"
assert_equals "memsearch X-Client-Name header" "memsearch" "$client_name2"
assert_equals "memsearch X-Client-Extra header" "memsearch-client" "$extra_header"

# Verify special chars key with / and & is passed through intact
response3=$($COMPOSE exec -T sidecar wget -q -O- http://127.0.0.1:11438/)
api_key=$(printf '%s' "$response3" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('x-api-key',''))")
assert_equals "special-chars X-Api-Key header" "test/special&key" "$api_key"

summary
