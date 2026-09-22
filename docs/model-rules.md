# Rules for the `model` binary

What a row in `bin/model`'s `MODELS` array is allowed to say. Follow these and the
listing stays a table of facts instead of a pile of notes.

## Context: give every model the most it can hold

Do not hard-code `-c`. In `config.yaml`, pin `-ngl 99` and leave `-c` unset, and
llama.cpp's `--fit` gives the model the largest context that still keeps every layer
on the GPU. It re-decides on its own when the quant or the card changes, which a
hard-coded number does not.

This only works when exactly one of the two is set. `--fit` adjusts the arguments the
config leaves **unset**:

| `-ngl` | `-c` | what `--fit` does |
|---|---|---|
| set | set | nothing — aborts with "n_gpu_layers already set by user" |
| unset | set | keeps your context, moves layers to CPU — **4x slower**, do not do this |
| **set** | **unset** | **picks the biggest context that still fits. This is the one.** |

Two things to watch:

- **The VRAM margin is what caps context.** `--fit-target` is per-device MiB left free;
  every MiB reserved is context not allocated. It is 1024 here. Raise it if the desktop
  needs the card, and expect context to drop across the board.
- **`--fit` cannot see an MTP draft context.** It is allocated after `--fit` finishes
  measuring and grows with the context, so an MTP model can be handed a context that
  then OOMs on load. Give those a larger `--fit-target`, and pin `-c` outright if the
  weights are big enough that the margin leaves nothing (this is why `turbo` is the
  one model with a hard-coded context).

Then record what it chose in the row, and re-measure after changing quant, `-ncmoe`,
`--fit-target` or the GPU. A context in the table that llama.cpp did not actually
choose is a lie with a number on it.

Where context and speed genuinely fight — a MoE whose `-ncmoe` is spending the VRAM
that KV needs — context wins for a model kept for breadth, speed wins for one kept for
throughput. Say which in the `for` column.

## Order of work

1. **Wire it into llama-swap first.** `~/.config/llama-swap/config.yaml` on jarvis
   (tracked copy: `models/llama-swap-config.yaml`). `bin/model` starts nothing — if
   llama-swap does not serve the id, `model <key>` cannot work.
2. **Benchmark it.** `bin/bench-model <id>` — three runs, prints the median.
3. **Pick the thinking level by eval, not by taste.** Lowest level that still answers
   multi-step questions. See `docs/evals/benchmark-2026-09-20-all.md` for the method
   and what "tolerable" turned out to mean.
4. **Then** add the row.

Never add a row with a guessed number. An unmeasured model is not ready to be listed.

## Field format

```
key | name | quant | size | n-cpu-moe | tok/s | path | ctx | ngl | reasoning | chat-template | for
```

| field | rule |
|---|---|
| `key` | exactly the llama-swap id. No aliases, no inventing a nicer one. |
| `name` | the official name, shortened — see below. Max ~30 chars. |
| `quant` | as published: `Q5_K_M NEO-MTP`, `UD-IQ4_XS`, `Q4_K_M`. Not "4-bit". |
| `size` | file size on disk, `19.7 GiB` or `~74 GB`. The real number, not the repo's rounding. |
| `n-cpu-moe` | `--n-cpu-moe` for MoEs that spill to RAM, `0` otherwise. |
| `tok/s` | **a number and nothing else.** `52`, `162`, `3.4`. |
| `path` | absolute path to the GGUF on jarvis. |
| `ctx` | the context `--fit` chose — measured, not picked. See **Context** below. |
| `ngl` | blank means 99 / full offload. |
| `reasoning` | `on`/`off`/`auto` → `--reasoning`; anything else → `--reasoning-effort`. |
| `chat-template` | only when the GGUF's built-in template is wrong. |
| `for` | why you would pick this one. `uncensored` when the tune is built that way, otherwise the job it does: `coding`, `images, OCR`, `reasoning, specs`, `eval only`. Two or three words. |

## Naming

Take the official name and cut until it fits, in this order: drop the `-GGUF` suffix,
the quant and imatrix markers (`NEO`, `MTP`, `UD-`, `Q4_K_M`), the uploader's initials
(`NM-DAU`), the training-recipe words, and the benchmark numbers. Keep the family, the
parameter count, and the one trait you would actually pick it for.

```
DavidAU/Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NM-DAU-NEO-MTP-GGUF
  ->  DavidAU Qwen3.8 27B Uncensored
```

Keep the uploader when the tune is the point (`DavidAU`, `Huihui`); drop it for stock
weights (`Qwen3.8-27B dense`). If two rows would collide, the `quant` column separates
them — do not pad the name to disambiguate.

## Calling something uncensored

Take it from the tune's own name or card — `abliterated`, `heretic`, `uncensored` —
not from testing it. A behaviour probe does not work here: on 2026-09-20 seven models
were asked two things a guarded assistant typically declines, and **all seven answered,
stock Qwen3.8-27B included**. This family is permissive by default, so a model passing
a refusal probe tells you nothing about whether it was abliterated.

If a tune makes no such claim, the field gets its purpose instead. Do not guess.

## The tok/s field carries no prose

It used to be a free-text note ("fits RAM, tight", "mmap from Kingston, RAM+disk") and
the table turned into commentary nobody could scan. Caveats — VRAM headroom, paging
behaviour, what the model is for — go in the comment block above `MODELS`, where they
do not cost a column.

## Order

Fastest first. The list is read by someone choosing a model, and on this box speed is
the axis that varies most — 162 tok/s to 3.4.

## Keep it honest

- Re-benchmark after changing hardware, `-ncmoe`, ctx, or quant. Stale numbers are
  worse than no numbers: the `-ncmoe` values survived a GPU swap and quietly wasted
  half the card.
- Drop a row the moment llama-swap stops serving it.
- Record negative results in `docs/evals/` so nobody re-runs a dead end.
