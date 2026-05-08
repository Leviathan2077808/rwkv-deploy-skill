#!/usr/bin/env bash
# serve.sh - start a native API server when the selected engine provides one.
# This script does not start custom wrapper code for engines without a server.

set -euo pipefail

STATE_DIR="${RWKV7_SKILL_STATE_DIR:-$HOME/.rwkv7-skill/state}"
CHOICE_FILE="${RWKV7_SKILL_CHOICE:-$STATE_DIR/choice.env}"
PORT="${RWKV7_SKILL_PORT:-8000}"
HOST="${RWKV7_SKILL_HOST:-127.0.0.1}"

if [ ! -f "$CHOICE_FILE" ]; then
    echo "ERROR: $CHOICE_FILE missing. Write ENGINE= and MODEL_SIZE= first." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CHOICE_FILE"
: "${ENGINE:?ENGINE not set}"

case "$ENGINE" in
nano_vllm)
    : "${MODEL_PATH:?MODEL_PATH not set - run fetch_model.sh or set it manually}"
    NANO_VLLM_DIR="${NANO_VLLM_DIR:-${RWKV_ENGINE_ROOT:-$HOME/rwkv-engines}/nano-vllm}"
    SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-rwkv7-${MODEL_SIZE:-local}}"

    if [ ! -d "$NANO_VLLM_DIR/.git" ]; then
        echo "ERROR: nano-vLLM source not found at $NANO_VLLM_DIR" >&2
        exit 1
    fi

    cd "$NANO_VLLM_DIR"
    if [ ! -f nanovllm/entrypoints/openai/api_server.py ]; then
        echo "ERROR: worktree is not on the RWKV branch. Try:" >&2
        echo "  git fetch origin" >&2
        echo "  git switch rwkv || git switch -c rwkv --track origin/rwkv" >&2
        exit 1
    fi

    if [ -f .venv/bin/activate ]; then
        # shellcheck disable=SC1091
        source .venv/bin/activate
    else
        echo "ERROR: nano-vLLM venv missing. Follow references/deploy.md Step 4A first." >&2
        exit 1
    fi

    exec python -m nanovllm.entrypoints.openai.api_server \
        --model "$MODEL_PATH" \
        --served-model-name "$SERVED_MODEL_NAME" \
        --host "$HOST" \
        --port "$PORT" \
        --gpu-memory-utilization "${NANO_VLLM_GPU_MEMORY_UTILIZATION:-0.97}" \
        --max-num-seqs "${NANO_VLLM_MAX_NUM_SEQS:-512}" \
        --max-num-batched-tokens "${NANO_VLLM_MAX_NUM_BATCHED_TOKENS:-16384}" \
        --rwkv-prefill-token-budget "${NANO_VLLM_PREFILL_TOKEN_BUDGET:-2048}" \
        --rwkv-prefill-max-batch-size "${NANO_VLLM_PREFILL_MAX_BATCH_SIZE:-128}" \
        --rwkv-prefill-chunk-size "${NANO_VLLM_PREFILL_CHUNK_SIZE:-256}" \
        ${NANO_VLLM_EXTRA_ARGS:-}
    ;;
rwkv_lightning)
    : "${MODEL_PATH:?MODEL_PATH not set}"
    RWKV_LIGHTNING_DIR="${RWKV_LIGHTNING_DIR:-${RWKV_ENGINE_ROOT:-$HOME/rwkv-engines}/rwkv_lightning}"
    if [ ! -d "$RWKV_LIGHTNING_DIR" ]; then
        echo "ERROR: rwkv_lightning source not found at $RWKV_LIGHTNING_DIR" >&2
        exit 1
    fi
    cd "$RWKV_LIGHTNING_DIR"
    exec python app.py --model-path "$MODEL_PATH" --port "$PORT" ${RWKV_LIGHTNING_EXTRA_ARGS:-}
    ;;
rwkv_lightning_libtorch)
    echo "Start the native LibTorch binary from its build/dist directory; see references/deploy.md Step 4D." >&2
    exit 64
    ;;
rwkv_app)
    echo "RWKV App server is started from the app UI. Default app API port is 52345." >&2
    exit 64
    ;;
web_rwkv|webrwkv)
    echo "WebRWKV is an inference library and has no native OpenAI API server." >&2
    echo "Ask the user whether to create a separate wrapper task after deployment selection." >&2
    exit 64
    ;;
*)
    echo "ERROR: unknown ENGINE=$ENGINE" >&2
    exit 2
    ;;
esac
