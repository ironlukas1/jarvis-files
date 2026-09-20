# Qwen3.8-27B TURBO Fable-Cold-Fusion — benchmark and thinking-level eval, 2026-09-20

Model: [`DavidAU/Qwen3.8-27B-TURBO-Fable-Cold-Fusion-735-882-Heretic-Uncensored-NEO-CODER-MAX-MTP-GGUF`](https://huggingface.co/DavidAU/Qwen3.8-27B-TURBO-Fable-Cold-Fusion-735-882-Heretic-Uncensored-NEO-CODER-MAX-MTP-GGUF)

- Host: jarvis, **RTX 3090 24 GB** + 62 GB RAM (the box no longer has the 5070 Ti)
- Runtime: llama-swap :8000 → `llama.cpp/build-3090/bin/llama-server`, `-ngl 99`, q8_0 KV, `-c 65536`
- Quant: `Q5_K_M` NEO di-imatrix, both the MTP and the regular file (`~/models-27b/turbo/`)
- Speeds from llama.cpp `timings` (server-side), `temperature=0.6`, non-streaming

## Speed

| id            | quant               | gen tok/s      | prefill tok/s @16k | VRAM used | VRAM free |
|---------------|---------------------|----------------|--------------------|-----------|-----------|
| `turbo`       | Q5_K_M **MTP**      | **52.4 – 55.1**| 1195               | 23248 MiB | 1328 MiB  |
| `turbo-plain` | Q5_K_M              | 34.1           | 1243               | 21966 MiB | 2610 MiB  |

MTP self-speculation (`--spec-type draft-mtp`) is worth **~1.6x**: draft acceptance measured
0.58 – 0.77 with mean draft length 2.3 – 3.3, well above the 0.50 the model card says is the
break-even point. Decode speed is identical whether thinking is on or off — thinking changes
how many tokens are produced, not how fast.

For scale, the same box benchmarked 2026-09-06 at 50 gen tok/s for Qwen3.8-27B UD-IQ4_XS on
the old 16 GB card.

### The VRAM trade-off

The MTP draft context costs ~1.4 GB on top of the weights, which is exactly the desktop margin
`config.yaml` reserves. So the two entries are a real choice, not redundancy:

- `turbo` — 52 tok/s, leaves 1.3 GB. Fine while the box is headless.
- `turbo-plain` — 34 tok/s, leaves 2.6 GB, the margin the shared `common` macro intends.
  Also the one to use above temperature 1, where the card says MTP acceptance degrades.

Note: `--fit on --fit-target` in the shared macro is currently a **no-op for every model** —
`-ngl 99` is set explicitly, so llama.cpp aborts the fit with
`n_gpu_layers already set by user to 99, abort`. The margins in this config hold by arithmetic,
not by enforcement.

## Thinking level: `low` vs `off`

The tune's Jinja template defaults to `reasoning_effort = xhigh` and accepts `xhigh|medium|low`;
llama-swap's `reasoning_effort: none` maps to thinking off. 15 tasks with checkable answers
(code graded by running it against assertions):

| task            | `low` (turbo) | `off` (turbo:fast) |
|-----------------|---------------|--------------------|
| bat-and-ball    | ok            | ok                 |
| count 'r'       | ok            | **fail** (3, correct 6) |
| count 'e'       | ok            | **fail** (10, correct 15) |
| arithmetic +10% | ok            | **fail** (42.00, correct 44.15) |
| date maths      | fail (3 Apr)  | **fail** (21 Apr, correct 2 Apr) |
| logic puzzle    | ok            | **fail** (3, correct 4) |
| unit conversion | ok            | ok                 |
| JSON conversion | ok            | ok                 |
| merge intervals | ok            | ok                 |
| roman numerals  | ok            | ok                 |
| LRU cache       | ok            | ok                 |
| fix off-by-one  | ok            | ok                 |
| fix 2nd-largest | ok            | ok                 |
| Slovak, 2 sent. | ok            | ok                 |
| **total**       | **14 / 15**   | **10 / 15**        |

The one `low` miss is sampling noise at temperature 0.6, not a pattern: the MTP build re-ran
the same 10 tasks at `low` and scored 10/10, date maths included.

**Off is much worse, not slightly** — and the damage is concentrated: every failure is a
multi-step task (counting, arithmetic, date arithmetic, constraint logic). With thinking off
the model answers those in 2 – 11 tokens, i.e. it blurts. Code generation, code repair, JSON
shaping and Slovak prose are unaffected — those pass in both modes.

Cost of `low`: 1656 output tokens / 52 s for the 10-task round versus 436 tokens / 15 s with
thinking off, so roughly 3.5x the tokens for +4 correct answers. Thinking blocks stay short
(200 – 600 characters), which is the point of this tune — stock Qwen3.8 27B spends thousands.

**Decision: `low` is the default.** Thinking off is kept as the `:fast` alias for extraction,
formatting and boilerplate, where it is 3x cheaper and gives up nothing measurable.

## llama-swap ids

| id             | thinking | temp | use                                        |
|----------------|----------|------|--------------------------------------------|
| `turbo`        | low      | 0.6  | default — coding, reasoning, chat          |
| `turbo:fast`   | off      | 0.6  | extraction, formatting, one-shot rewrites  |
| `turbo-plain`  | low      | 0.8  | creative / temp > 1, or when the desktop needs the VRAM |

Tool calling is advertised (`tools: true`); the card recommends ≥ Q4_K_M for it, and this is
Q5_K_M. Vision needs the separate `mmproj` file and is not wired up here.

_Raw results: `benchmark-2026-09-20-turbo.json`_
