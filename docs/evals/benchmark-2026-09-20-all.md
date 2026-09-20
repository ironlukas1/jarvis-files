# Jarvis full-catalogue benchmark and speed retune — 2026-09-20

Host: jarvis, **RTX 3090 24 GB** + 62 GB RAM. Runtime: llama-swap v256 on `:8000`,
`llama.cpp/build-3090`. All figures from llama.cpp `timings` (server side),
`temperature 0.6`, one model resident at a time.

The box changed GPU since the last benchmark (2026-09-06 ran on a 5070 Ti 16 GB), and
several settings were still sized for that card. This pass measured everything, then
retuned for speed.

## Baseline — every model as it was configured

| id                | quant             | gen tok/s | prefill tok/s | VRAM MiB | thought? |
|-------------------|-------------------|-----------|---------------|----------|----------|
| `qwen3-coder-30b` | Q4_K_M (30B-A3B)  | **162.1** | 3296          | 19578    | no       |
| `turbo`           | Q5_K_M NEO-MTP    | 51.7      | 1193          | 23242    | yes, low |
| `ocr-vlm`         | UD-IQ4_XS+mmproj  | 43.0      | — (8k ctx)    | 14722    | no       |
| `planner`         | UD-Q5_K_XL        | 34.2      | 1227          | 21606    | yes, high|
| `turbo-plain`     | Q5_K_M NEO        | 34.1      | 1235          | 21962    | yes, low |
| `q38-27b-q5`      | UD-Q5_K_XL        | 34.0      | 1216          | 22922    | yes      |
| `q38-q2`          | UD-Q2_K_XL (MoE)  | 13.0      | 268           | 12142    | yes      |
| `q38-iq3x`        | UD-IQ3_XXS (MoE)  | 9.8       | 256           | 11652    | yes      |
| `dsv4-q8`         | UD-Q8_K_XL (284B) | 3.4       | **6**         | ~15700   | yes      |

Two things stand out. `qwen3-coder-30b` is 4.7x faster than the 27B dense models —
a 3B-active MoE that fits entirely on the card. And `dsv4-q8` prefills at 6 tok/s,
so a 16k-token prompt needs roughly 45 minutes: it is a curiosity, not a tool.

## What changed

### 1. Thinking level: `high` → `low` on the dense 27B

`planner` was running `reasoning_effort: high` — a value the Qwen3.8 template does not
even document (it accepts `xhigh`, `medium`, `low`). Same design question at each level:

| level          | thinking chars | answer chars | tokens | wall |
|----------------|----------------|--------------|--------|------|
| none           | 0              | 4641         | 1029   | 31s  |
| **low**        | **2402**       | 3927         | 1445   | ~43s |
| medium         | 4788           | 6069         | 2586   | 79s  |
| xhigh          | 6954           | 3826         | 2333   | 137s |
| **high** (old) | **10637**      | 1954         | 2720   | 170s |
| (unset)        | 11589          | 1866         | 3000†  | 89s  |

† hit the token cap while still thinking — no answer at all.

Accuracy over 11 tasks with checkable answers (code graded by executing it):

| level  | score     | tokens | wall |
|--------|-----------|--------|------|
| none   | 7 / 11    | 1123   | 40s  |
| **low**| **11 / 11**| 3555  | 108s |
| medium | 11 / 11   | 4295   | 129s |
| xhigh  | 11 / 11   | 3344   | 102s |

`low` is the lowest level that still answers multi-step questions — `none` drops
counting, arithmetic, date maths and constraint logic. Everything above `low` buys
nothing measurable and costs up to 4x the latency. Applied to `planner`, `critic`
and `planner-deep`; the `:fast` aliases keep `none` for extraction and formatting.

Measured after the change: the same design question went from ~170 s to ~43 s, with
thinking down from 10637 to 3006 characters and a complete answer.

### 2. `-ncmoe` retuned for the 24 GB card

The Flash-Next MoEs were set to `-ncmoe 42`, sized for the old 16 GB GPU, and were
using barely half the card:

| model      | ncmoe | VRAM MiB | gen tok/s (median of runs) |
|------------|-------|----------|----------------------------|
| `q38-q2`   | 42    | 12114    | 10.4                       |
| `q38-q2`   | **30**| 23090    | **12.8**                   |
| `q38-q2`   | 26    | —        | CUDA OOM                   |
| `q38-iq3x` | 42    | 11624    | 9.7                        |
| `q38-iq3x` | **32**| 21276    | **11.7**                   |
| `q38-iq3x` | 28    | —        | CUDA OOM                   |

Worth 10–20%, and honestly noisy: a 74 GB model against 62 GB of RAM streams experts
from disk, so throughput depends on page-cache state and individual runs ranged
11.6–16.7 tok/s at the same setting. The bottleneck is paging, not the GPU. The cost
is VRAM headroom — `q38-q2` now leaves 1.4 GB instead of 12 GB, so if the desktop
needs the card, put these back to 34 / 42.

### 3. `turbo` added

The DavidAU TURBO tune (see `benchmark-2026-09-20-turbo.md`): 52 tok/s via MTP
self-speculation, 14/15 on the checkable set at thinking `low`. It is 1.5x faster
than `planner` on the same class of weights.

## Negative results — do not re-test these

**N-gram speculative decoding does not pay off.** It needs no draft weights, so it
looked free, but:

| model                 | variant          | prose | code  | edit  |
|-----------------------|------------------|-------|-------|-------|
| Qwen3.8-27B Q5_K_XL   | baseline         | 34.2  | 34.1  | 34.1  |
| Qwen3.8-27B Q5_K_XL   | `ngram-simple`   | 33.8  | 34.8  | **37.1** |
| Qwen3.8-27B Q5_K_XL   | `ngram-map-k4v`  | 33.7  | 33.8  | 33.7  |
| Qwen3-Coder-30B-A3B   | baseline         | 159.2 | 159.4 | 159.3 |
| Qwen3-Coder-30B-A3B   | `ngram-map-k4v`  | 151.7 | 150.0 | 152.6 |

The only win is `ngram-simple` on the dense model's rewrite-this-function case (+9%),
where output echoes the prompt. On the coder it is a 5% *loss*. Left off everywhere.
MTP self-speculation is the speculation that works here (+55% on `turbo`).

**`--fit on --fit-target` in the shared `common` macro does nothing.** `-ngl 99` is
set in the same macro, so llama.cpp aborts the fit:
`n_gpu_layers already set by user to 99, abort`. Every VRAM margin in that config
holds by arithmetic, not by enforcement.

## Where the speed actually is

1. `qwen3-coder-30b` — 162 tok/s. For anything it can do, nothing else is close.
2. `turbo` — 52 tok/s, uncensored, reasons well at `low`.
3. `planner` / `turbo-plain` — 34 tok/s, full 27B dense quality.
4. `q38-q2` / `q38-iq3x` — 12–13 tok/s. Big MoEs that do not fit; use for breadth of
   knowledge, not for speed.
5. `dsv4-q8` — 3.4 tok/s and 6 tok/s prefill. Eval only, as its description says.

## Not covered

Weights on disk that llama-swap does not serve, so they were neither benchmarked nor
tuned: `/mnt/models2/candidates` (swift, gsq-rco, huihui-abliterated, 0bserverx-heretic,
~61 GB) and `~/models-fast` (the Flash-Next Q4/Q5/Q6/Q8 ladder). `dsv4-q8`'s `-ncmoe`
was left at 43 — each load takes ~15 minutes, and at 3.4 tok/s the payoff is not worth
the hour.

_Raw: `benchmark-2026-09-20-all.json`_
