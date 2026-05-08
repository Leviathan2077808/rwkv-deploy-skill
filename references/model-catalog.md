# Model Catalog

Use base G1 `.pth` weights unless a project explicitly requires another format.

## Selection Policy

| Scenario | Default | Fallback |
|---|---|---|
| High-concurrency agent demo on NVIDIA | `7.2B` | `2.9B` only if VRAM/latency forces it |
| Constrained NVIDIA GPU (`8-16 GB`) | `2.9B` | 7.2B int8/quant only after benchmark |
| Very small GPU or CPU-only | smallest task-sufficient quantized model | stop if quality target cannot be met |
| Quality-first single-user test | `7.2B` or `13.3B` | downgrade only after measuring |
| Cross-platform app test | model chosen by app/backend benchmark | use smaller/quantized if device swaps |

Do not pick model size only by raw token speed. Smaller models can underuse a strong GPU and may fail agent-style tasks.

## File Pins

Source:

```text
https://huggingface.co/BlinkDL/rwkv7-g1/tree/main
```

| Size | File | Approx GB | Deployment note |
|---|---|---:|---|
| `0.4B` | `rwkv7-g1d-0.4b-20260210-ctx8192.pth` | 0.9 | smoke/experiments only |
| `1.5B` | `rwkv7-g1f-1.5b-20260419-ctx8192.pth` | 3.06 | narrow tasks or very constrained hardware |
| `2.9B` | `rwkv7-g1f-2.9b-20260420-ctx8192.pth` | 5.9 | constrained general deployment |
| `7.2B` | `rwkv7-g1f-7.2b-20260414-ctx8192.pth` | 14.4 | default high-concurrency baseline |
| `13.3B` | `rwkv7-g1f-13.3b-20260415-ctx8192.pth` | 26.5 | quality-first only |

On 404, update the pin from the Hugging Face tree and then update [../scripts/fetch_model.sh](../scripts/fetch_model.sh).

## Memory Budgeting

Use these as starting points, not hard promises:

| Available VRAM/RAM | Likely model choice | Notes |
|---|---|---|
| `< 8 GB` | `1.5B` or quantized smaller model | Not a high-concurrency target. |
| `8-16 GB` | `2.9B`; test 7.2B int8 only if needed | Leave headroom for state slots and prefill buffers. |
| `16-24 GB` | `7.2B` | Good baseline; benchmark actual concurrency. |
| `24-32 GB` | `7.2B`, possibly larger if quality-first | 7.2B leaves more concurrency headroom. |
| `>= 32 GB` | `7.2B` for concurrency, `13.3B` for quality | Choose based on measured p95 latency and quality. |

For nano-vLLM, VRAM after model load determines state-slot capacity. The code computes slots from free CUDA memory, dtype, model layers/heads/head dimension, and reserves prefill-probe memory. This is why "VRAM size -> concurrency" cannot be a fixed table.

## Context

The listed G1 files are `ctx8192`. Runtime servers may clamp request context lower, for example nano-vLLM server defaults `--max-model-len 4096`. Increase only after verifying memory and behavior.
