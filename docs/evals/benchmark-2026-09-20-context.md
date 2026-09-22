# Maximising context per model — 2026-09-20

Every model's context was hard-coded, mostly at 32768, on a card that could hold far
more. This pass handed the decision to llama.cpp's `--fit` and measured what each one
actually got.

## The mechanism

`--fit` adjusts the arguments the config leaves **unset**. The old config set both
`-ngl 99` and `-c N`, so it had nothing to adjust and aborted every time:
`n_gpu_layers already set by user to 99, abort`. The margins in that config were
therefore decorative.

Three combinations, measured on `gsq-rco`:

| `-ngl` | `-c` | result |
|--------|------|--------|
| 99     | 32768 (old) | 32k, 67.8 tok/s — `--fit` aborts, nothing adjusted |
| unset  | 262144      | 256k, **16.5 tok/s** — keeps context, spills layers to CPU |
| **99** | **unset**   | **200k, 63.7 tok/s** — picks the biggest context that fits |

The third is what the config does now, everywhere except `turbo`.

## Result

| model             | ctx before | ctx after   | tok/s | VRAM MiB |
|-------------------|-----------:|------------:|-------|----------|
| `ocr-vlm`         |       8192 | **225536**  | 43    | 22990    |
| `gsq-rco`         |      32768 | **203264**  | 68    | 21144    |
| `huihui`          |      32768 | **180992**  | 39    | 22982    |
| `swift`           |      32768 | **171520**  | 39    | 22994    |
| `q38-q2`          |      98304 | **262144**  | 9     | 15760    |
| `q38-q4`          |      32768 | **262144**  | 16    | 18246    |
| `q38-q5`          |      32768 | **243968**  | 15    | 23108    |
| `q38-iq3x`        |      32768 | **124416**  | 11    | 22996    |
| `planner`         |      65536 | **101632**  | 34    | 22980    |
| `heretic`         |      32768 | **101120**  | 63    | 20934    |
| `qwen3-coder-30b` |      32768 | **99584**   | 162   | 23100    |
| `dsv4-q8`         |      32768 | **1048576** | 3.4   | 18748    |
| `turbo`           |      65536 | 65536       | 51    | 23242    |

`ocr-vlm` gained 27x, `dsv4-q8` reached its native 1M ceiling (MLA keeps its KV cache
tiny), and both big Flash-Next quants hit Flash-Next's native 262144.

**It cost almost no speed.** `gsq-rco` measured 55.9 tok/s on a single run at 203k and
68.5 as a median of three — the drop was run-to-run noise, not the larger KV cache.
`heretic` 63.1, `turbo` 51.3, `qwen3-coder-30b` 160 — all unchanged within noise
despite 2-6x the context.

## What had to be fixed along the way

- **The margin is the cap.** `--fit-target` (MiB left free per device) went 2704 → 1024.
  At 2704 `planner` got 57344 — *less* than the 65536 it had hard-coded. At 1024 it gets
  101632. Every reserved MiB is context not allocated; raise it back if the desktop ever
  needs the card and expect context to fall everywhere.
- **`--fit` cannot see an MTP draft context.** It is allocated after `--fit` finishes and
  scales with context. `turbo` (19.7 GiB of weights, ~3.3 GB left for everything else)
  bottomed out at the 4096 floor with a large margin, and OOMed on load at `-c 98304`.
  It is pinned to 65536, the only hard-coded context left. `gsq-rco` and `heretic` are
  smaller, so a 2600 MiB margin is enough slack for their draft contexts.
- **`-ncmoe` and context compete for the same VRAM.** `q38-q2` at `-ncmoe 30` could only
  fit 23296 tokens, down from the 98304 it is kept for. Back at 42 it reaches the full
  262144, at 9 tok/s instead of ~12. For a model kept for breadth and long context that
  is the right trade. `q38-q4` at 38 bottomed out at 4096; at 44 it gets 262144 and is
  no slower (15.9 vs 16.5).

## Caveat worth keeping in mind

These contexts fit, they are not free to use. Prefill is the limit for the big MoEs:
13-19 tok/s for the Flash-Next quants and 6 tok/s for `dsv4-q8`, so filling even a
fraction of that 1M window takes hours. The GPU-resident models prefill at ~1200 tok/s,
where a 100k prompt is about 80 seconds.

_Raw: `benchmark-2026-09-20-context.json`_
