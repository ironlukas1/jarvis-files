# Jarvis — Execution Plan (hand-off)

**Written:** 2026-08-19
**Audience:** a fresh Claude Code session + Luke
**Supersedes:** `migration_plan.md` — that document's *premise* is obsolete. Read it only for host
detail; do not execute its Phases 1, 3, or 6. See "Retired work" at the bottom.
**Direction rationale:** `docs/ideas/jarvis-agent-platform.md`

> **Self-contained by design — do not assume prior session state.**

---

## The decision, in one paragraph

The original plan asked "which bigger local model fixes Slovak?" That question is answered and it was
not a hardware question. **DeepSeek V4 Flash 0731** (284B total / 13B active, MIT) tested clean on all
five Slovak quality axes — no invented words, no language drift, correct grammar, no confabulation,
and it admits ignorance — despite Slovak not appearing in DeepSeek's published language tiers. The
binding constraint was **knowledge capacity**, not language coverage; MoE decouples those. Running it
locally would be 15–60× slower for identical output at roughly the cost of the electricity, so **the
brain is hosted via OpenRouter** and `.59` takes the work a local GPU is irreplaceable for: GPU
Whisper STT, TTS, a resident fallback model, the future agent runtime, and fine-tuning.

**Measured:** 60.2 tok/s · 2.6s provider latency · $0.000208/query · GMICloud via OpenRouter.

---

## Current state

### Done ✅
- `.59` Secure Boot **disabled** in BIOS (physical access via Luke's uncle). No MOK enrolment needed.
- `.59` NVIDIA `nvidia-headless-595-open` 595.84 installed, DKMS modules loaded.
  `nvidia-smi` → **RTX 5070 Ti, 16303MiB, CUDA 13.2**. Persistence mode on.
- `.59` Ollama installed natively (not Docker), with systemd override:
  `OLLAMA_HOST=0.0.0.0:11434`, `OLLAMA_KEEP_ALIVE=30m`. **Reachable from `.15`** (verified).
- `.59` hostname → `jarvis`, timezone → `Europe/Bratislava`.
- `jarvis-sk` Modelfile exported off `.23` (`temperature 0.2`, `top_p 0.85`, `top_k 30`).
  **Confirm the file's location before relying on it.**

### Validated ✅
- V4 Flash Slovak quality — clean on all five axes. **N=1, hand-graded, not blind.**
- V4 Flash tool calling — correct tool selection on Slovak commands, **and no over-triggering** on
  knowledge questions. Tested with six representative HA-shaped tools, not the real twelve.

### Not done ❌
Everything in "Remaining work" below.

---

## Hosts

| Host | Identity | Role | Key facts |
|---|---|---|---|
| `.15` | `ppf-server`, Alpine 3.23.4 | Hub / orchestrator | i5-8500T 6C/6T, 15.4GB RAM, 453GB NVMe (71% used). Docker, 47 containers. Traefik v3.7.10, Technitium DNS. ufw default-deny. **No GPU.** SSH user `admin`. `/mnt/synology` NFS mount available. |
| `.59` | `jarvis`, Ubuntu 26.04, kernel 7.0.0-29 | **New Jarvis host** | Core Ultra 7 270K Plus (24 threads), 30GB RAM, **RTX 5070 Ti 16GB**, 1.7TB NVMe (1.6TB free). SSH user `ocino`. |
| `.23` | `Petko`, Windows 11 Pro | **Being retired** | RTX 5070 12GB, Ollama 0.32.5. Keep models intact until `.59` runs clean for one week, then wipe. |
| `.47` | Synology DSM | NAS | On `.15` at `/mnt/synology`. Backups + benchmark artifacts. |

**Voice pipeline (all on `.15`, containerized):** Home Assistant 2026.8.2, `wyoming-piper` (10200),
`wyoming-whisper` + `wyoming-whisper-router` (10300), `wyoming-openwakeword` (10400) — all bound to
localhost. Custom: `jarvis-satellite`, `jarvis-lab`, `notify-bridge`.

**Source of truth:** `/home/admin/homelab/documentation/jarvis-voice-assistant.md` on `.15`.
**Update it at the end of every step.**

---

## Remaining work, in order

### 1. Local fallback model on `.59`
Pull `qwen3:14b`, rebuild `jarvis-sk` from the exported Modelfile with identical params. This is both
the WAN-outage fallback and the control arm for any future benchmark.
**Exit:** `.15` gets sane Slovak from `http://192.168.100.59:11434` for model `jarvis-sk`.

### 2. Household latency conversation — before cutover, not after
Responses go from 0.72s to ~4–5s. Tell the household first. Your own plan flags this as the most
likely reason the migration gets reverted, and it is a social problem, not a technical one.

### 3. HA conversation agent → OpenRouter
- Primary: OpenRouter, DeepSeek V4 Flash 0731. Confirm the exact model slug on the OpenRouter model
  page — a wrong slug returns 400, not a silent fallback.
- Secondary: `.59` Ollama `jarvis-sk`, so falling back is a config change and not a rebuild.
- **Verify HA can set a custom base URL.** The built-in OpenAI Conversation integration may not
  expose one; if not, use a community integration that does, or a small local proxy. Check this
  before planning the cutover.
- **Rollback:** repoint the conversation agent. One config change.
**Exit:** end-to-end Slovak through the real `jarvis-satellite` — wake word → STT → LLM → tool → TTS.
Not curl against the API.

### 4. Whisper STT → `.59` GPU
The single biggest latency win available: STT is on the critical path of *every* interaction and is
currently CPU-only on an i5-8500T. Also unblocks the parked Slovak-STT work
(`NaiveNeuron/whisper-large-v3-turbo-sk` vs `nvidia/parakeet-tdt-0.6b-v3`).
CUDA 13.2 is new — target CUDA 12.x builds; the driver is backward-compatible.

### 5. Piper TTS → `.59`
Lower priority: Piper is already fine on CPU. The real gain is that a GPU makes heavier TTS viable,
which is the only path to the male Slovak voice that doesn't exist in Piper today.

### 6. Retire `.23`
After `.59` has run clean for one week. Luke's uncle gets his gaming PC back.

### 7. Documentation
Update the source-of-truth doc. Commit the 13-prompt Slovak eval set and results to `/mnt/synology`
**and** the docs repo — the 2026-08-07 eval set going missing is exactly the failure to avoid
repeating. Also record what `jarvis-lab` and `notify-bridge` actually do.

### Phase 2 (not now)
Agent runtime on `.59` + MCP servers for house/files/email/PDF. Voice becomes a front door; long
tasks acknowledge in voice and report back async. **Destructive or outbound actions must confirm
through a second channel (phone notification), never voice alone** — ambient mic + Slovak STT + no
speaker authentication is too much blast radius.

---

## Load-bearing — do not change without measuring

- `prefer_local_intents: true` — HA's Slovak intents stay the fast path. **More** important now, not
  less: it's what keeps routine commands instant when the brain is a network hop away.
- `think` mode **OFF** — measured 0.93s vs 36.7s. Never re-enable without re-measuring.
- `should_expose=True` for `remember_fact`, `forget_fact`, `confirm_pc_action`, `cancel_pc_action`
  must be written **with Home Assistant stopped**. Websocket-API exposure does not survive a restart.
- The `shell_command:` block must exist. A missing one makes `shell_command.jarvis_remember` fire and
  fail with **no user-visible error**.
- **The household actively uses this system and speaks Slovak.** Every step ends with a working
  assistant. Schedule disruption deliberately.

---

## Gotchas

1. **HA `should_expose` must be set with HA stopped**, or it silently reverts on restart.
2. **A missing `shell_command:` block** = tools fire and fail silently.
3. **Over-triggering is the tool-call failure mode to watch** — a model that calls tools when it
   shouldn't is worse in a voice assistant than one that occasionally misses. It turns a question
   into an action in someone's house.
4. **Blackwell (GB203) requires the `-open` driver variants.** The proprietary kernel module does not
   support these GPUs, even though `ubuntu-drivers` lists non-open options.
5. **Ollama binds localhost by default.** Already fixed on `.59`; re-check after any Ollama upgrade,
   since package updates can drop systemd overrides.
6. **`.59`'s internet is now load-bearing.** WAN down = no brain. That's what step 1's local
   fallback agent exists for; verify it actually takes over.
7. **Verify from `.15`, never from the box itself** — a local curl proves nothing about bind address.

---

## Retired work — do not resurrect

- **migration_plan.md Phase 1 (`.23` disk cleanup)** — the box is being decommissioned. Only the
  Modelfile export mattered, and it's done.
- **Phase 3 dense 27–32B sweep** — wrong axis. The win came from MoE knowledge capacity, not
  parameter count. One `qwen3:14b` control run is enough.
- **Phase 6 llama.cpp RPC across `.23` + `.59`** — pooling VRAM solves a dense-model problem that no
  longer exists.
- **The 64GB RAM purchase** — the brain isn't local. No mechanism left by which it helps.
- **Colibri / local V4 Flash** — parked, not deleted. 15–60× slower for identical output. The
  architecture leaves a slot if that ever changes.

---

## Open questions

- Vision model for screen reading (Phase 2). `qwen3.7-flash` is the current pick but is expensive,
  and the step only needs to *describe* a screen for a text brain — a lower bar than full visual
  reasoning. Measure cost per screenshot before committing.
- Agentic token cost. Chat is ~$1/year; tool loops with growing context are plausibly $5–15/month.
- Which agent runtime. MCP is the plumbing decision; the loop itself is undecided.
