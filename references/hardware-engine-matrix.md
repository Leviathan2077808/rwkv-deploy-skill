# Hardware -> Engine -> Model Matrix

Use this after hardware probing. The goal is not to list every possible backend; it is to choose a path that can run on the user's machine and can be benchmarked.

## Engine Priority

| Priority | Engine | Best fit | Native API server | Notes from local code |
|---:|---|---|---|---|
| 1 | `nano_vllm` | Ubuntu/Linux + NVIDIA CUDA high-concurrency demo | Yes | `origin/rwkv` has `nanovllm.entrypoints.openai.api_server`, OpenAI routes, request batcher, frontend workers, `--max-num-seqs`, `--rwkv-prefill-*`, and int8 flags. |
| 2 | `llama.cpp` | Low VRAM / quantized deployment | Usually yes | Verify the user's selected clone and RWKV/GGUF support before prescribing commands. |
| 3 | `RWKV App` | Cross-platform desktop/mobile local API and quick hardware fit checks | Yes | Local app has API Server UI and `/v1/chat/completions`; default API port in code is `52345`. |
| 4 | `web-rwkv` | WebGPU compatibility, integrated GPUs, browser/Rust experiments | No | README says it is an inference library only; it supports batched inference and int8/NF4, but no OpenAI API. |
| 5 | `rwkv_lightning` | Existing private batch API workflows, CUDA/ROCm experiments | Yes | README exposes `/v1`, `/v2`, `/state`, `/openai/v1`, batch translation, and FIM endpoints; request schemas are not purely standard OpenAI. |
| 6 | `rwkv_lightning_libtorch` | Windows/native bundle, no Python runtime at serving time | Yes | README documents CMake/LibTorch bundle and batch benchmark; setup is heavier than nano-vLLM on Linux. |
| Track | `rwkv-rs` | Rust evaluation | Verify first | Do not default until deployment/API path is clear. |

## First Matching Route

| Machine condition | Route | Model baseline | Why |
|---|---|---|---|
| Linux/Ubuntu + NVIDIA + `>= 16 GB` VRAM | `nano_vllm` | `7.2B` | Primary high-concurrency path. |
| Linux/Ubuntu + NVIDIA + `8-16 GB` VRAM | `nano_vllm` with `2.9B`, or 7.2B int8 only after testing | `2.9B` | 7.2B fp16 may fit poorly once state slots and prefill buffers are included. |
| Linux/Ubuntu + NVIDIA + `< 8 GB` VRAM | quantized path; verify `llama.cpp` or a smaller model | `1.5B`/`2.9B` quant | Not ideal for the high-concurrency demo. |
| Windows + NVIDIA | WSL2 + `nano_vllm`; fallback native bundle | `7.2B` if VRAM allows | WSL2 keeps parity with Linux deployment. |
| macOS | RWKV App / MLX/CoreML/WebGPU route | app benchmark decides | Good for compatibility checks, not the first high-concurrency baseline. |
| Mixed/unknown GPU or integrated GPU | RWKV App or `web-rwkv` | fit by benchmark | Use if "can run locally" matters more than server throughput. |
| No working GPU | CPU/quant path only | smallest task-sufficient model | Not a high-concurrency target. |

## nano-vLLM Concurrency Facts

The RWKV branch's server exposes these relevant defaults:

| Setting | Default | Meaning |
|---|---:|---|
| `--max-num-seqs` | `512` | requested active sequence cap; effective value is limited by available state slots |
| `--max-num-batched-tokens` | `16384` | scheduler token cap |
| `--max-model-len` | `4096` | server context cap, then clamped by model config |
| `--gpu-memory-utilization` | `0.9` | fraction used to compute available cache/state memory |
| `--rwkv-prefill-token-budget` | `2048` | prefill token budget per scheduling step |
| `--rwkv-prefill-max-batch-size` | `128` | prefill sequence batch cap |
| `--rwkv-prefill-chunk-size` | `256` | prompt chunking granularity |
| `--frontend-workers` | POSIX default `2` | HTTP frontend listeners/workers |

The actual active sequence limit is computed after model load from free CUDA memory. In local code, each state slot is sized from model layers, heads, head dimension, dtype, and extra token-shift cache. The effective `max_num_seqs` becomes the smaller of requested sequences and computed state blocks.

Representative local benchmark from the RWKV branch README, using 7.2B on RTX 5090 32 GB:

| Concurrency | fp16 decode tok/s | int8 decode tok/s |
|---:|---:|---:|
| 128 | 6534 | 6536 |
| 256 | 7897 | 8070 |
| 512 | 8753 | 9252 |
| 768 | 9443 | 9756 |
| 960 | 9816 | 9924 |

These are direct model benchmark numbers, not HTTP p95 latency. Use them only as an upper-bound signal.

## VRAM And Concurrency

Concurrency increases VRAM pressure through:

- per-active-request RWKV recurrent state;
- prefill buffers for prompt chunks;
- scheduler/front-end queues and response buffers;
- CUDA graph/int8/runtime scratch space;
- fragmentation and driver overhead.

Weights stay shared. A GPU does not have a universal request limit; the limit is measured for a specific model, prompt length, output length, quantization, and latency target.

## Tuning Order

If startup or benchmark OOMs:

1. Lower `--max-num-seqs`.
2. Lower `--rwkv-prefill-max-batch-size`.
3. Lower `--rwkv-prefill-token-budget` or `--rwkv-prefill-chunk-size`.
4. Lower `--gpu-memory-utilization` only if instability suggests not enough headroom; increase it only when state-slot capacity is too low and the machine is otherwise stable.
5. Try int8 or a smaller model.

If GPU utilization is low:

1. Increase benchmark concurrency.
2. Increase `--max-num-seqs` if state slots allow.
3. Increase prefill batch/token budget for long prompts.
4. Avoid using a very small model as the demo baseline on a strong GPU.
