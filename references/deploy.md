# Deploy RWKV-7 Locally

This flow is for deployment assessment and native engine startup. It does not add custom application tools or custom API-server code.

## Step 1 - Probe

Run:

```bash
bash scripts/probe.sh
nvidia-smi
df -h "$HOME"
```

Capture:

- OS and whether it is WSL2/container/remote SSH;
- GPU name, driver, CUDA version, total/free VRAM;
- system RAM;
- free disk;
- whether `python3`, `uv`, `git`, and `curl` exist.

## Step 2 - Decide Route

Use [hardware-engine-matrix.md](hardware-engine-matrix.md).

If the probe shows Ubuntu/Linux + NVIDIA CUDA and the target is high-concurrency serving, start with:

```text
ENGINE=nano_vllm
MODEL_SIZE=7.2B
```

Use a fallback only when hardware or platform requires it:

- tight VRAM -> smaller model or quantized route;
- Windows-native requirement -> native bundle route;
- macOS or integrated GPU -> RWKV App/WebGPU route;
- engine has no native API server -> propose a separate wrapper task after deployment choice.

## Step 3 - Fetch Model

Use [model-catalog.md](model-catalog.md) for current model filenames.

For G1 `.pth` weights, [../scripts/fetch_model.sh](../scripts/fetch_model.sh) prints a resumable download command:

```bash
mkdir -p ~/.rwkv7-skill/state
cat >> ~/.rwkv7-skill/state/choice.env <<'EOF'
ENGINE=nano_vllm
MODEL_SIZE=7.2B
EOF

bash scripts/fetch_model.sh
```

If the model already exists, verify file size and set `MODEL_PATH` manually if needed.

## Step 4A - nano-vLLM Native Server

Use a user-provided engine directory, or clone into a neutral local workspace:

```bash
ENGINE_ROOT="${RWKV_ENGINE_ROOT:-$HOME/rwkv-engines}"
mkdir -p "$ENGINE_ROOT"

if [ ! -d "$ENGINE_ROOT/nano-vllm/.git" ]; then
  git clone https://github.com/MollySophia/nano-vllm "$ENGINE_ROOT/nano-vllm"
fi

cd "$ENGINE_ROOT/nano-vllm"
git fetch origin
git switch rwkv || git switch -c rwkv --track origin/rwkv
```

Install:

```bash
uv venv
source .venv/bin/activate
uv sync --extra torch-cu130
```

Use `torch-cu126`, `torch-rocm`, or `torch-cpu` only when the machine requires it.

Start a 7.2B server:

```bash
python -m nanovllm.entrypoints.openai.api_server \
  --model "$MODEL_PATH" \
  --served-model-name rwkv7-7.2b \
  --host 0.0.0.0 \
  --port 8000 \
  --gpu-memory-utilization 0.97 \
  --max-num-seqs 512 \
  --max-num-batched-tokens 16384 \
  --rwkv-prefill-token-budget 2048 \
  --rwkv-prefill-max-batch-size 128 \
  --rwkv-prefill-chunk-size 256
```

Optional int8 trial:

```bash
python -m nanovllm.entrypoints.openai.api_server \
  --model "$MODEL_PATH" \
  --served-model-name rwkv7-7.2b-int8 \
  --host 0.0.0.0 \
  --port 8000 \
  --gpu-memory-utilization 0.97 \
  --rwkv-quant-int8
```

Smoke test:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "rwkv7-7.2b",
    "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
    "max_tokens": 32,
    "temperature": 0.8
  }'
```

## Step 4B - RWKV App Native API

Use when the user wants a desktop/mobile path or cross-platform quick validation.

Local code shows:

- API UI page calls `http://127.0.0.1:<port>/v1/chat/completions`;
- default port is `52345`;
- server exposes model/status/log UI in the app.

Deployment is app-driven:

1. Install/open RWKV App.
2. Load a model that fits the device.
3. Open API Server, set port, start server.
4. Smoke test `/v1/chat/completions`.

## Step 4C - WebRWKV Library

Use when WebGPU compatibility is the main goal. Local README says it supports NVIDIA/AMD/Intel GPUs, Vulkan/Dx12/OpenGL backends, batched inference, int8/NF4, and RWKV V4-V7.

It does **not** provide an OpenAI API server. After confirming it runs on the machine, ask whether the user wants a separate wrapper task.

## Step 4D - Other Native Servers

Use only when their platform fit is better than nano-vLLM:

- `rwkv_lightning`: Python server with CUDA/ROCm install path and multiple native endpoints.
- `rwkv_lightning_libtorch`: C++/LibTorch bundle path, useful for native Windows packaging.

Always verify the request schema with curl because some endpoints use private request fields rather than standard OpenAI fields.

## Step 5 - Benchmark

Direct nano-vLLM model benchmark:

```bash
python benchmark_rwkv.py \
  --model-pth "$MODEL_PATH" \
  --concurrency 128 256 512 \
  --prompt-length 128 \
  --decode-steps 128 \
  --gpu-memory-utilization 0.97 \
  --rwkv-prefill-token-budget 2048 \
  --rwkv-prefill-max-batch-size 128
```

HTTP benchmark on the native server:

```bash
python benchmark_openai_api.py \
  --base-url http://127.0.0.1:8000 \
  --model rwkv7-7.2b \
  --endpoint chat \
  --users-sweep 32 64 128 256 \
  --total-requests 512 \
  --max-tokens 128 \
  --prompt "Summarize why batching improves inference throughput."
```

Report:

- engine, model, quantization, launch flags;
- GPU model, total/free VRAM;
- prompt length and output length;
- concurrency or arrival rate;
- success/error counts;
- throughput;
- p50/p95 latency;
- peak VRAM if available from `nvidia-smi`.

## Step 6 - API Server Check

End every deployment assessment with one of:

- "Native API server exists and passed smoke test."
- "Native API server exists but smoke test failed; here is the failing command and error."
- "Selected engine has no native API server. Ask the user whether to create a separate wrapper after this deployment decision."
