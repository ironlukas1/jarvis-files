# Rules for the `model` binary

What a row in `bin/model`'s `MODELS` array is allowed to say. Follow these and the
listing stays a table of facts instead of a pile of notes.

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
key | name | quant | size | n-cpu-moe | tok/s | path | ctx | ngl | reasoning | chat-template
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
| `ctx`, `ngl` | as configured. `ngl` blank means 99 / full offload. |
| `reasoning` | `on`/`off`/`auto` → `--reasoning`; anything else → `--reasoning-effort`. |
| `chat-template` | only when the GGUF's built-in template is wrong. |

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

## The tok/s field carries no prose

It used to be a free-text note ("fits RAM, tight", "mmap from Kingston, RAM+disk") and
the table turned into commentary nobody could scan. Caveats — VRAM headroom, paging
behaviour, what the model is for — go in the comment block above `MODELS`, where they
do not cost a column.

## Keep it honest

- Re-benchmark after changing hardware, `-ncmoe`, ctx, or quant. Stale numbers are
  worse than no numbers: the `-ncmoe` values survived a GPU swap and quietly wasted
  half the card.
- Drop a row the moment llama-swap stops serving it.
- Record negative results in `docs/evals/` so nobody re-runs a dead end.
