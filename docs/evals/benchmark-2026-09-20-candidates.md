# The unwired models — benchmark and wiring, 2026-09-20

Six GGUFs were sitting on jarvis with no llama-swap entry, so nothing could serve them
and `bin/model` could not list them honestly. They are wired in now and measured.

Host and method as in `benchmark-2026-09-20-all.md`: RTX 3090 24 GB, llama-swap on
`:8000`, generation tok/s from llama.cpp `timings`, temperature 0.6.

| id        | quant          | size      | gen tok/s | VRAM MiB | notes                    |
|-----------|----------------|-----------|-----------|----------|--------------------------|
| `gsq-rco` | IQ3_S MTP      | 11.3 GiB  | **67.8**  | 13848    | fastest 27B on the box   |
| `heretic` | Q4_K_M MTP     | 15.8 GiB  | **64.5**  | 18026    | multilingual tune        |
| `huihui`  | UD-Q4_K_XL     | 16.2 GiB  | 39.1      | 17336    | abliterated              |
| `swift`   | Q4_K_M         | 16.8 GiB  | 38.6      | 17710    |                          |
| `q38-q4`  | UD-Q4_K_XL     | ~104 GB   | 16.5      | 22966    | prefill 13 tok/s         |
| `q38-q5`  | UD-Q5_K_XL     | ~148 GB   | 15.2      | 19166    | prefill 19 tok/s         |

## The headline

**The two MTP quants are the fastest 27B-class models here**, ahead of `turbo` (52)
and well ahead of stock `planner` (34) — same size class, same card. `gsq-rco` and
`heretic` both have `mtp` in the filename, so `--spec-type draft-mtp` turns the
embedded multi-token-prediction head into a self-draft. That is the whole difference:
nothing about these tunes is otherwise faster.

Worth noticing that these had been on disk since 2026-09-15 and the old `bin/model`
listed them with speeds that were never measured, alongside `-ngl` values sized for a
16 GB card the box no longer has.

**The big Flash-Next quants beat the small ones.** `q38-q4` (104 GB) runs at 16.5 tok/s
against `q38-q2`'s 13 — because Q4/Q5 live on the root LV (the Kingston) and Q2/IQ3
live on `/mnt/models2`. When a model streams from disk the whole time it runs, the
disk it streams from matters more than the quant. Their prefill is the real limit
though: 13–19 tok/s, so a long prompt is measured in minutes.

`~/models-fast/BF16` (330 GB) is not wired and will not be — it cannot run here.
`q38-q6` and `q38-q8`, which the old MODELS list carried, do not exist on disk at all.

## Refusal probing does not identify an uncensored tune

Seven models — `planner`, `swift`, `gsq-rco`, `huihui`, `heretic`, `turbo`,
`qwen3-coder-30b` — were each asked two things a guarded assistant typically declines
(how a pin tumbler lock is picked; a deliberately mean roast). **All seven answered
both, stock `planner` included.** Zero refusals out of fourteen.

So the `for` column takes "uncensored" from the tune's own provenance — `abliterated`
in Huihui's name, `Heretic` in the RVN tune's, `Heretic-Uncensored` on DavidAU's card
— and never from a behaviour test. A model passing a refusal probe here says nothing:
the base model passes it too.

_Raw: `benchmark-2026-09-20-candidates.json`_
