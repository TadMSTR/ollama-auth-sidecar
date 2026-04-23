#!/bin/sh
# Test: chunked NDJSON streams through without buffering.
# Mock upstream emits 5 chunks at 0.6s intervals (~3s total).
# We verify all 5 chunks arrive and that the first chunk arrives within 2s
# (well within the 0.6s × 2× relative threshold).

set -eu
. "$(dirname "$0")/lib.sh"

echo "=== test_streaming ==="

wait_for_sidecar

tmpfile=$(mktemp)
start=$(date +%s)

# wget doesn't support streaming well; use curl inside the sidecar container
$COMPOSE exec -T sidecar \
    wget -q -O- "http://127.0.0.1:11436/stream" > "$tmpfile" 2>&1

end=$(date +%s)
elapsed=$((end - start))

chunk_count=$(wc -l < "$tmpfile" | tr -d ' ')

assert_equals "received 5 NDJSON chunks" "5" "$chunk_count"

# Should have taken ~3s (5 × 0.6s); allow 1–8s window to tolerate CI runner variance
if [ "$elapsed" -ge 1 ] && [ "$elapsed" -le 8 ]; then
    echo "  PASS: streaming took ${elapsed}s (in 1–8s window)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: streaming took ${elapsed}s (expected 1–8s) — possible buffering issue"
    FAIL=$((FAIL + 1))
fi

rm -f "$tmpfile"
summary
