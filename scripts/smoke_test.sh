#!/usr/bin/env bash
# smoke_test.sh — verify the local server responds sanely.
# Exits 0 on success, non-zero with a diagnostic line on failure.

set -euo pipefail

PORT="${RWKV7_SKILL_PORT:-8000}"
HOST="${RWKV7_SKILL_HOST:-127.0.0.1}"
BASE="http://$HOST:$PORT"
STATE_DIR="${RWKV7_SKILL_STATE_DIR:-$HOME/.rwkv7-skill/state}"
CHOICE_FILE="${RWKV7_SKILL_CHOICE:-$STATE_DIR/choice.env}"
URLS=(
    "$BASE/v1/chat/completions"
    "$BASE/openai/v1/chat/completions"
)

if [ -f "$CHOICE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CHOICE_FILE"
fi

MODEL="${RWKV7_SKILL_MODEL:-${SERVED_MODEL_NAME:-}}"
if [ -z "$MODEL" ] && [ -n "${MODEL_SIZE:-}" ]; then
    MODEL="rwkv7-$MODEL_SIZE"
fi
MODEL="${MODEL:-rwkv7}"

PAYLOAD="$(
    MODEL="$MODEL" python3 - <<'PY'
import json
import os

print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 16,
    "temperature": 1.0,
}))
PY
)"

# 1. /health is optional; not every native engine exposes it.
HEALTH="$(curl -sf --max-time 3 "$BASE/health" || echo "")"
if [ -n "$HEALTH" ] && ! echo "$HEALTH" | grep -q '"ok": *true'; then
    echo "WARN: /health exists but is not ok. Response: $HEALTH" >&2
fi

# 2. A trivial chat completion should return a non-empty assistant message
START=$(date +%s)
RESP=""
URL=""
for CANDIDATE in "${URLS[@]}"; do
    if RESP="$(curl -sf --max-time 60 -X POST "$CANDIDATE" \
        -H 'Content-Type: application/json' \
        -d "$PAYLOAD")"; then
        URL="$CANDIDATE"
        break
    fi
done
END=$(date +%s)

if [ -z "$RESP" ]; then
    echo "FAIL: no response from known chat endpoints:" >&2
    printf '  %s\n' "${URLS[@]}" >&2
    exit 2
fi

# crude JSON field check without jq dependency
CONTENT="$(echo "$RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"])' 2>/dev/null || echo "")"
COMPLETION_TOKENS="$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["usage"]["completion_tokens"])' 2>/dev/null || echo 0)"

if [ -z "$CONTENT" ] || [ "${#CONTENT}" -lt 1 ]; then
    echo "FAIL: empty assistant content. Full response:" >&2
    echo "$RESP" >&2
    exit 3
fi

ELAPSED=$((END - START))
[ "$ELAPSED" -lt 1 ] && ELAPSED=1
TOK_PER_S=$(( COMPLETION_TOKENS / ELAPSED ))

echo "PASS: got $COMPLETION_TOKENS tokens in ${ELAPSED}s (~${TOK_PER_S} tok/s)"
echo "Endpoint: $URL"
echo "Model: $MODEL"
echo "Sample reply: ${CONTENT:0:80}"
