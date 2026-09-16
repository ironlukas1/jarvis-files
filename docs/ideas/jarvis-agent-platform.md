# Jarvis — From Voice Assistant to Agent Platform

**Written:** 2026-08-19
**Supersedes the framing of:** `migration_plan.md` (2026-08-18)
**Status:** direction agreed; model quality and tool calling both validated — cleared to provision `.59`

---

## Problem Statement

**How might we** give a Slovak-speaking household one assistant that controls the house, answers
hard questions honestly, and does real work on Luke's PC — without the voice path becoming slower,
less reliable, or less trustworthy than what they already have?

## Recommended Direction

**The original question is answered, and it wasn't a hardware question.** The migration plan asked
"which bigger model fixes Slovak?" and hedged that the answer was a language ceiling. DeepSeek V4
Flash 0731 (284B total / **13B active**, MIT) came back clean on all five axes — no invented words,
no drift, correct grammar, no confabulation, and it admitted ignorance — despite Slovak appearing in
*none* of DeepSeek's published language tiers. The ceiling was **knowledge capacity**, not language
coverage, and MoE decouples those two things. That is precisely why a dense 27–32B sweep would never
have found it. Measured via OpenRouter/GMICloud: **60.2 tok/s, $0.000208/query, 15.8s wall for a
779-token answer.**

**That collapses the hardware question.** The same model through Colibri on `.59` would be 15–60×
slower for identical output, at roughly the annual cost of the electricity to run it. So the brain
goes hosted, and `.59` takes the jobs where a local GPU is genuinely irreplaceable: **Whisper STT** —
on the critical path of every single interaction and currently stuck on `.15`'s CPU — neural TTS, a
resident fast model for tight agentic loops where network round trips hurt most, the agent runtime
itself, and eventually fine-tuning a Slovak voice. Inference rents for ~$11/year. Training doesn't
rent at all.

**The scope is bigger than a migration.** PDFs, email, and file editing mean Jarvis stops being an
intent matcher with an LLM fallback and becomes an **agent with a voice front-end**: HA Assist keeps
wake word, STT, TTS and local Slovak intents (so house control stays instant), an agent runtime loops
behind it over MCP servers, and long tasks acknowledge in voice — *"dobre, pripravím to"* — then
report back asynchronously via `notify-bridge`.

## Key Assumptions to Validate

- [x] **V4 Flash makes correct tool calls.** ✅ **Validated 2026-08-19** against six representative
      HA-shaped tools (area control, state query, memory write, PC confirm) via OpenRouter. Correct
      tool selection on Slovak commands, and — the important half — **no over-triggering** on
      knowledge questions or the honesty probe. Not yet run against the real twelve definitions.
- [ ] **The clean result generalizes.** Re-run the 13-prompt set 3× and grade blind. N=1 hand-graded
      screened GO; it is not a benchmark.
- [ ] **4–5s voice latency is acceptable to the household.** 2.6s provider latency + ~1.7s generation
      for a short reply. Validate by *asking*, not assuming. Already the most likely revert cause.
- [ ] **Ubuntu 26.04 / kernel 7.0 has a working NVIDIA driver path.** Secure Boot is now **disabled**
      on `.59`, so MOK enrolment is moot — but kernel 7.0 is new enough that driver availability
      needs checking rather than assuming.
- [ ] **HA 2026.8 can hand off cleanly to an external agent runtime.** Verify what its conversation
      agent actually supports for multi-step before designing around it.

## MVP Scope

**In:**

1. `.59` provisioned — NVIDIA driver, CUDA, Whisper STT + Piper TTS moved off `.15`
2. HA conversation agent → OpenRouter V4 Flash; local model on `.59` configured as a **second**
   conversation agent for WAN outages
3. The existing 12 HA tools working through the hosted brain
4. Latency conversation with the household **before** cutover
5. Load-bearing settings preserved: `prefer_local_intents: true`, `think` **off**, `should_expose`
   written **with HA stopped**, `shell_command:` block present

**Out of MVP (phase 2 of the project, not "never"):** agent runtime, MCP servers, PDF/email/file
capabilities, vision/screen reading, any fine-tuning.

The MVP tests exactly one thing: **does a hosted brain plus a GPU voice pipeline beat today's setup
on answer quality without the household noticing a regression?** Everything agentic builds on that
foundation and is worth nothing without it.

## Not Doing (and Why)

- **Phase 6 — llama.cpp RPC across `.23` + `.59`.** Pooling 28GB of VRAM solves a dense-model problem
  that no longer exists.
- **The dense 27–32B sweep.** Wrong axis entirely. Keep one control run against `qwen3:14b` for the
  record; drop the rest.
- **The 64GB RAM purchase.** The brain isn't local. There is no remaining mechanism by which it helps.
- **Colibri / local V4 Flash.** Parked, not deleted — 15–60× slower for identical output. The
  two-tier architecture leaves a slot if that ever changes.
- **Voice-only confirmation for destructive actions.** Ambient mic + Slovak STT + no speaker
  authentication is too much blast radius for file writes and outbound email. Reads run free; writes
  gate through a phone notification (`confirm_pc_action` / `cancel_pc_action` already exist for this).

## Decisions Made (2026-08-19)

1. **`.23` is retired entirely.** `.59` fills the fallback role better and the gaming PC goes back to
   its owner. **Sequencing:** keep `.23`'s models intact until `.59` has run clean for at least a
   week, then wipe. This also retires Phase 1's disk-pressure work — no reason to reclaim space on a
   box being decommissioned, beyond exporting the `jarvis-sk` Modelfile for the record.
2. **Vision model: `qwen3.7-flash`** for screen reading, pending a cost check (see below).
3. **The agent runtime runs on `.59`.** `.15` is at 71% disk with 47 containers; `.59` has 1.6TB free
   and no competing load.
4. **OpenRouter stays the router.** Provider flexibility and per-task model choice at zero VRAM cost
   is the main reason to go hosted at all — going direct to GMICloud would give that up.

## Open Questions

- **Vision cost.** Screenshots are token-expensive and `qwen3.7-flash` was flagged as pricey. Before
  building the screen-reading path, measure cost per screenshot and compare against cheaper vision
  models — the vision step only needs to *describe* the screen for a text brain, which is a lower bar
  than full visual reasoning. Not MVP-blocking.
- **Agentic token cost.** Chat is ~$1/year. Tool loops with growing context are plausibly $5–15/month.
  Worth measuring once the agent runtime exists rather than being surprised by it.
- **Which agent runtime.** MCP is the plumbing decision; the loop itself is still open.
