# Troubleshooting

## Local Paths

- **Need engine code** - inspect the user's configured `RWKV_ENGINE_ROOT` before browsing or cloning.
- **nano-vLLM looks generic** - check `origin/rwkv`; `main` may not contain RWKV server code.

```bash
NANO_VLLM_DIR="${NANO_VLLM_DIR:-${RWKV_ENGINE_ROOT:-$HOME/rwkv-engines}/nano-vllm}"
git -C "$NANO_VLLM_DIR" branch -a
git -C "$NANO_VLLM_DIR" show origin/rwkv:README.md
```

## Probe Issues

- **NVIDIA missing** - run `nvidia-smi`. For high-concurrency demo work, do not continue on CPU if GPU throughput is the target.
- **CUDA mismatch** - use the Torch build that matches the installed driver/CUDA path (`torch-cu130`, `torch-cu126`, etc.).
- **Disk too small** - model download size is not enough; leave extra headroom for venvs, build artifacts, and converted/quantized files.

## nano-vLLM

- **`nanovllm.entrypoints.openai.api_server` not found** - wrong branch or stale checkout. Switch to or inspect `origin/rwkv`.
- **OOM at startup** - lower `--max-num-seqs`, prefill settings, or model size. If only slightly short, test int8.
- **OOM during benchmark** - active state slots/prefill buffers are too large for the requested concurrency.
- **GPU utilization low** - increase benchmark concurrency or batch/prefill limits before changing engines. Very small models may not fill a strong GPU.
- **OpenAI request rejected** - local code rejects unsupported fields such as tools, response_format, parallel_tool_calls, some logprobs/stop combinations, and `n != 1`. Use the minimal chat payload for smoke tests.
- **HTTP benchmark differs from direct benchmark** - expected. Direct benchmark measures model kernel/scheduler ceiling; HTTP adds frontend, serialization, queueing, and client latency.

## RWKV App

- **API server says no model** - load/select a model in the app first.
- **Port mismatch** - local code defaults to port `52345`, not `8000`.
- **Only one active request or conservative concurrency** - treat app server as compatibility path. Use nano-vLLM for formal high-concurrency benchmarking.

## WebRWKV

- **No `/v1/chat/completions`** - expected. Local README says WebRWKV is an inference library and has no API server.
- **GPU not detected through WebGPU/Vulkan** - switch backend if available or use another engine. Do not spend demo time debugging device discovery unless compatibility is the goal.
- **Model too large** - README notes device loss / severe slowdown when VRAM is insufficient; use quantization or a smaller model.

## Other Native Servers

- **Private request schemas** - some engines expose batch/private APIs whose fields differ from standard OpenAI chat. Smoke test the exact endpoint and payload before wiring agents.
- **Native bundle build is complex** - CMake, Torch/LibTorch, CUDA toolkit, and platform package managers may all be involved. If the target machine is Ubuntu + NVIDIA, prefer the nano-vLLM path first.

## Benchmark Interpretation

- **One request works but concurrency fails** - smoke test only proves the model loads. Capacity requires benchmark.
- **p95 latency explodes** - server is past saturation. Lower concurrency, output length, or prefill limits.
- **Throughput rises with concurrency then plateaus** - normal. Use the plateau before p95 becomes unacceptable.
- **Different GPUs** - compare by measured results, not by model name alone. VRAM controls state-slot capacity; compute controls decode speed.
