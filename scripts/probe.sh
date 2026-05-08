#!/usr/bin/env bash
# probe.sh — detect host hardware and write JSON to ~/.rwkv7-skill/state/probe.json
# Consumed by: SKILL.md Step 1, followed by hardware-engine-matrix.md decision.
# Output schema (all keys always present):
#   os, arch, cpu_cores, ram_gb, has_cuda, has_rocm,
#   gpu_name, gpu_vram_gb, gpu_free_vram_gb, nvidia_driver,
#   nvidia_cuda_version, disk_free_gb, is_wsl, in_container,
#   has_git, has_python3, has_uv, has_curl, has_cargo
# Unknowns are emitted as null / 0 / false so downstream JSON consumers don't crash.

set -euo pipefail

STATE_DIR="${RWKV7_SKILL_STATE_DIR:-$HOME/.rwkv7-skill/state}"
mkdir -p "$STATE_DIR"
OUT="${RWKV7_SKILL_PROBE_OUT:-$STATE_DIR/probe.json}"

json_quote() {
    if [ -z "${1:-}" ]; then
        printf 'null'
    else
        printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    fi
}

# --- OS / arch ---------------------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"          # darwin | linux | mingw*
ARCH="$(uname -m)"                                     # arm64 | x86_64 | aarch64
case "$OS" in
    mingw*|msys*|cygwin*) OS="windows" ;;
esac

IS_WSL="false"
if [ "$OS" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
    IS_WSL="true"
fi

IN_CONTAINER="false"
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
    IN_CONTAINER="true"
fi

# --- CPU cores ---------------------------------------------------------------
if [ "$OS" = "darwin" ]; then
    CPU_CORES="$(sysctl -n hw.ncpu)"
elif [ "$OS" = "linux" ]; then
    CPU_CORES="$(nproc)"
else
    CPU_CORES="${NUMBER_OF_PROCESSORS:-0}"
fi

# --- RAM (GB, rounded down) --------------------------------------------------
if [ "$OS" = "darwin" ]; then
    RAM_BYTES="$(sysctl -n hw.memsize)"
    RAM_GB=$(( RAM_BYTES / 1024 / 1024 / 1024 ))
elif [ "$OS" = "linux" ]; then
    RAM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
    RAM_GB=$(( RAM_KB / 1024 / 1024 ))
else
    RAM_GB=0
fi

# --- GPU / CUDA / ROCm -------------------------------------------------------
HAS_CUDA="false"
HAS_ROCM="false"
GPU_NAME="null"
GPU_VRAM_GB=0
GPU_FREE_VRAM_GB=0
NVIDIA_DRIVER="null"
NVIDIA_CUDA_VERSION="null"

if command -v nvidia-smi >/dev/null 2>&1; then
    # nvidia-smi present => NVIDIA + CUDA likely available
    GPU_LINE="$(nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
    if [ -n "$GPU_LINE" ]; then
        HAS_CUDA="true"
        GPU_NAME_RAW="$(echo "$GPU_LINE" | cut -d',' -f1 | sed 's/^ *//; s/ *$//')"
        GPU_NAME="$(json_quote "$GPU_NAME_RAW")"
        GPU_VRAM_MB="$(echo "$GPU_LINE" | cut -d',' -f2 | tr -d ' ')"
        GPU_FREE_VRAM_MB="$(echo "$GPU_LINE" | cut -d',' -f3 | tr -d ' ')"
        NVIDIA_DRIVER_RAW="$(echo "$GPU_LINE" | cut -d',' -f4 | sed 's/^ *//; s/ *$//')"
        NVIDIA_DRIVER="$(json_quote "$NVIDIA_DRIVER_RAW")"
        GPU_VRAM_GB=$(( GPU_VRAM_MB / 1024 ))
        GPU_FREE_VRAM_GB=$(( GPU_FREE_VRAM_MB / 1024 ))
        NVIDIA_CUDA_RAW="$(nvidia-smi 2>/dev/null | awk -F'CUDA Version: ' 'NF>1 {split($2,a," "); print a[1]; exit}' || true)"
        NVIDIA_CUDA_VERSION="$(json_quote "$NVIDIA_CUDA_RAW")"
    fi
fi

if [ "$HAS_CUDA" = "false" ] && command -v rocm-smi >/dev/null 2>&1; then
    # ROCm path
    HAS_ROCM="true"
    GPU_NAME_RAW="$(rocm-smi --showproductname 2>/dev/null | awk -F': ' '/Card series/ {print $2; exit}' || true)"
    [ -n "$GPU_NAME_RAW" ] && GPU_NAME="$(json_quote "$GPU_NAME_RAW")"
    GPU_VRAM_MB_RAW="$(rocm-smi --showmeminfo vram 2>/dev/null | awk '/Total/ {print $NF; exit}' || echo 0)"
    # ROCm reports in bytes; convert if numeric
    if [[ "$GPU_VRAM_MB_RAW" =~ ^[0-9]+$ ]]; then
        GPU_VRAM_GB=$(( GPU_VRAM_MB_RAW / 1024 / 1024 / 1024 ))
    fi
fi

# Apple Silicon: this probe does not model MLX/CoreML/WebGPU backends.
# GPU_NAME stays null; the matrix handles macOS through RWKV App/WebRWKV.

# --- Disk free in $HOME (GB) -------------------------------------------------
DISK_FREE_GB=0
if [ "$OS" = "darwin" ]; then
    # BSD df: -g prints in GiB already
    DISK_FREE_GB="$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4+0}')"
elif [ "$OS" = "linux" ]; then
    # GNU df: -BG appends "G" suffix
    DISK_FREE_GB="$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4+0}')"
fi
[ -z "$DISK_FREE_GB" ] && DISK_FREE_GB=0

# --- Tool availability -------------------------------------------------------
cmd_bool() {
    if command -v "$1" >/dev/null 2>&1; then
        printf 'true'
    else
        printf 'false'
    fi
}

HAS_GIT="$(cmd_bool git)"
HAS_PYTHON3="$(cmd_bool python3)"
HAS_UV="$(cmd_bool uv)"
HAS_CURL="$(cmd_bool curl)"
HAS_CARGO="$(cmd_bool cargo)"

# --- Emit JSON ---------------------------------------------------------------
cat > "$OUT" <<EOF
{
  "os": "$OS",
  "arch": "$ARCH",
  "is_wsl": $IS_WSL,
  "in_container": $IN_CONTAINER,
  "cpu_cores": $CPU_CORES,
  "ram_gb": $RAM_GB,
  "has_cuda": $HAS_CUDA,
  "has_rocm": $HAS_ROCM,
  "gpu_name": $GPU_NAME,
  "gpu_vram_gb": $GPU_VRAM_GB,
  "gpu_free_vram_gb": $GPU_FREE_VRAM_GB,
  "nvidia_driver": $NVIDIA_DRIVER,
  "nvidia_cuda_version": $NVIDIA_CUDA_VERSION,
  "disk_free_gb": $DISK_FREE_GB,
  "has_git": $HAS_GIT,
  "has_python3": $HAS_PYTHON3,
  "has_uv": $HAS_UV,
  "has_curl": $HAS_CURL,
  "has_cargo": $HAS_CARGO
}
EOF

echo "$OUT"
cat "$OUT"
