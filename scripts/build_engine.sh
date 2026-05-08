#!/usr/bin/env bash
# build_engine.sh - preflight the chosen native inference engine.
# This script does not build custom wrappers. It checks local prerequisites and
# prints the native setup path documented in references/deploy.md.

set -euo pipefail

STATE_DIR="${RWKV7_SKILL_STATE_DIR:-$HOME/.rwkv7-skill/state}"
CHOICE_FILE="${RWKV7_SKILL_CHOICE:-$STATE_DIR/choice.env}"

if [ ! -f "$CHOICE_FILE" ]; then
    echo "ERROR: $CHOICE_FILE missing. Write ENGINE= and MODEL_SIZE= first." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CHOICE_FILE"
: "${ENGINE:?ENGINE not set in $CHOICE_FILE}"

PREFLIGHT_MISSING=()

require_cmd() {
    local cmd="$1" hint="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        PREFLIGHT_MISSING+=("  - $cmd: $hint")
    fi
}

case "$ENGINE" in
nano_vllm)
    require_cmd git "install with the OS package manager"
    require_cmd python3 "install Python 3"
    require_cmd uv "install uv, then follow references/deploy.md Step 4A"
    ;;
rwkv_lightning)
    require_cmd python3 "install Python 3"
    require_cmd pip "install pip for the selected Python"
    ;;
rwkv_lightning_libtorch)
    require_cmd cmake "install CMake"
    require_cmd git "install with the OS package manager"
    ;;
rwkv_app)
    echo "RWKV App is app-driven. Install/open the app, load a model, then start API Server in the UI."
    exit 0
    ;;
web_rwkv|webrwkv)
    require_cmd cargo "install Rust/Cargo"
    ;;
*)
    echo "ERROR: unknown or unsupported ENGINE=$ENGINE" >&2
    echo "Supported values: nano_vllm, rwkv_app, web_rwkv, rwkv_lightning, rwkv_lightning_libtorch" >&2
    exit 2
    ;;
esac

if [ "${#PREFLIGHT_MISSING[@]}" -gt 0 ]; then
    {
        echo "ERROR: missing prerequisites for ENGINE=$ENGINE:"
        printf '%s\n' "${PREFLIGHT_MISSING[@]}"
    } >&2
    exit 10
fi

case "$ENGINE" in
nano_vllm)
    NANO_VLLM_DIR="${NANO_VLLM_DIR:-${RWKV_ENGINE_ROOT:-$HOME/rwkv-engines}/nano-vllm}"
    if [ ! -d "$NANO_VLLM_DIR/.git" ]; then
        echo "ERROR: nano-vLLM local repo not found at $NANO_VLLM_DIR" >&2
        echo "Set NANO_VLLM_DIR or clone https://github.com/MollySophia/nano-vllm first." >&2
        exit 1
    fi
    cd "$NANO_VLLM_DIR"
    if ! git cat-file -e origin/rwkv:nanovllm/entrypoints/openai/api_server.py 2>/dev/null; then
        echo "ERROR: origin/rwkv is missing or stale. Run: git fetch origin" >&2
        exit 1
    fi
cat <<EOF
nano-vLLM preflight passed.

Next:
  cd "$NANO_VLLM_DIR"
  git switch rwkv || git switch -c rwkv --track origin/rwkv
  uv venv
  source .venv/bin/activate
  uv sync --extra torch-cu130

Then start the native server per references/deploy.md Step 4A.
EOF
    ;;
rwkv_lightning|rwkv_lightning_libtorch|web_rwkv|webrwkv)
    echo "Preflight passed for ENGINE=$ENGINE. Follow the native engine instructions in references/deploy.md."
    ;;
esac
