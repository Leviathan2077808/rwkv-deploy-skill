---
name: rwkv7-skill
description: Review a user's local machine configuration and choose/deploy a suitable RWKV-7 inference engine and model for local Codex/agent demos across Linux, Windows, macOS, NVIDIA CUDA, WebGPU, and app-based paths. Use when the user asks whether a local RWKV deployment skill is appropriate, how to set up high concurrency, whether concurrency increases VRAM usage, which GPU/model/engine combination to choose, or how to benchmark local RWKV serving capacity. 
---

# rwkv7-skill

Use this skill to answer: "Can this machine run RWKV locally, which engine/model should I deploy, and how do I validate concurrency?"

Choose the deployment path from the user's actual OS, GPU, VRAM, RAM, disk, and API needs. 

## Workflow

1. **Inspect the machine**
   - Run [scripts/probe.sh](scripts/probe.sh), or manually collect `uname -a`, `nvidia-smi`, RAM, disk, CUDA/Torch readiness, and whether the user is inside WSL2/container/remote SSH.
   - Summarize OS, GPU model, VRAM, RAM, free disk, and driver/CUDA status before recommending anything.

2. **Choose engine**
   - Read [references/hardware-engine-matrix.md](references/hardware-engine-matrix.md).
   - Prefer native API servers already provided by the selected engine.
   - Do not add a custom wrapper inside this skill. If the chosen engine has no API server, finish by asking whether the user wants an agent to write one separately.

3. **Choose model**
   - Read [references/model-catalog.md](references/model-catalog.md).
   - For agent/high-concurrency demos, start from 7.2B when VRAM allows it. Use smaller models only when the target task is narrow or memory constrained.

4. **Deploy**
   - Follow [references/deploy.md](references/deploy.md).
   - If the user already has engine clones, ask for their local engine root or use `RWKV_ENGINE_ROOT`.
   - For nano-vLLM, inspect `origin/rwkv`; a generic `main` checkout is not enough.

5. **Validate concurrency**
   - Smoke test the API endpoint.
   - Run a benchmark with the same prompt length, output length, streaming mode, and target concurrency as the demo.
   - Report p50/p95 latency, success/error counts, throughput, GPU memory, and the exact launch flags.

## High-Concurrency Rules

- More concurrency increases memory use because each active request needs RWKV state slots, scheduler buffers, prompt prefill work, and response bookkeeping.
- The model weights are not duplicated per request.
- There is no fixed "GPU X supports N users" answer. Capacity depends on model size, quantization, prompt length, output length, max active sequences, and latency target.
- If GPU utilization is low, first increase concurrency or batching limits. If OOM occurs, lower active sequence/prefill settings, use quantization, or choose a smaller model.

## Local Source Priority

Before browsing, inspect user-provided local repositories. Do not hard-code private local paths in generated instructions or committed skill files.

```text
RWKV_ENGINE_ROOT=/path/to/user/engine/root
```

Relevant sources:

| Engine | Public source | Check |
|---|---|---|
| nano-vLLM | `https://github.com/MollySophia/nano-vllm` | `origin/rwkv` branch has RWKV server and benchmarks |
| llama.cpp | `https://github.com/ggml-org/llama.cpp` and `https://wiki.rwkv.com/inference/llamacpp.html` | GGUF/quantized path; verify selected RWKV GGUF model and server support |
| WebRWKV | `https://github.com/cryscan/web-rwkv` | WebGPU library, no API server |
| RWKV App | `https://github.com/RWKV-APP/RWKV_APP` | desktop/mobile app with local API server |
| rwkv_lightning | `https://github.com/RWKV-Vibe/rwkv_lightning` | native batch/private APIs |
| rwkv_lightning_libtorch | `https://github.com/Alic-Li/rwkv_lightning_libtorch` | native C++/LibTorch bundle path |
| rwkv-rs | `https://github.com/rwkv-rs/rwkv-rs` | track only unless server story is clear |

## Output Shape

When helping a user, answer in this order:

1. Machine summary.
2. Recommended engine/model and one fallback.
3. Exact deploy commands or hand-off commands.
4. Smoke test command.
5. Benchmark command and what numbers to report.
6. Whether a native API server exists. If not, ask whether to create one as a separate follow-up task.
