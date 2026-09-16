# Jarvis — `.59` Provisioning, Model Benchmarking & Migration Plan

**Written:** 2026-08-18
**Audience:** Claude Code (agentic execution) + Luke
**Goal:** Make `.59` the primary Jarvis inference host, keep `.23` as fallback, and raise Slovak
response accuracy — explicitly trading latency for capability.

---

## 0. Context Claude Code needs (self-contained — do not assume prior session state)

### Network
LAN `192.168.100.0/24`, Huawei router at `.1`, public IP `109.230.37.235`.
Location: Luke's uncle's house. **The household actively uses this system and speaks Slovak.**
Anything that takes the voice assistant offline is user-visible — schedule disruptive steps
deliberately, and never leave the pipeline broken between phases.

### Hosts

| Host | Identity | Role | Key facts |
|---|---|---|---|
| `.15` | `ppf-server`, Alpine 3.23.4, kernel 6.18.31-0-lts | **Hub / orchestrator** | i5-8500T 6C/6T, 15.4GB RAM, 453GB NVMe (71% used). Docker 29.1.3, 47 containers. Traefik v3.7.10 on 80/443, Let's Encrypt for `*.misaligned.dev`. Technitium DNS. ufw **default-deny**. No discrete GPU. SSH user `admin`. |
| `.23` | `Petko`, Windows 11 Pro build 10.0.26200 | **Current sole inference host** | i7-12700KF 12C/20T, 32GB RAM, RTX 5070 **12GB** (Windows misreports 4GB via `AdapterRAM` 32-bit overflow — ignore that number). C: 930GB, **only 70GB free (92% used)**. Ollama 0.32.5. SSH user `ocino` (admin). Domain firewall profile on, Private/Public off. |
| `.59` | Ubuntu 26.04 LTS, kernel 7.0.0-29-generic | **Target: new primary** | Intel Core Ultra 7 270K Plus (24 threads, 5.5GHz), Gigabyte Z890M Gaming X, **30GB RAM**, **RTX 5070 Ti 16GB**, 1.7TB NVMe (1.6TB free). BIOS F20. **Bare OS — nothing installed.** |
| `.47` | Synology DSM | NAS | Mounted on `.15` at `/mnt/synology` via NFS (100GB share, 60GB used). Not a compute host. |

### Current voice pipeline (all on `.15`, all containerized)
- **Home Assistant 2026.8.2** — orchestrator, Assist pipeline, entity registry, automations.
- **Wyoming stack:** `wyoming-piper` (TTS), `wyoming-whisper` + `wyoming-whisper-router` (STT),
  `wyoming-openwakeword`. Ports `10200` / `10300` / `10400`, **bound to localhost only**.
- **Custom containers:** `jarvis-satellite` (mic/speaker endpoint), `jarvis-lab`, `notify-bridge`.
- Piper's only Slovak voice is `sk_SK-lili-medium` (female). No male Slovak voice exists.

### Current conversation model
- `jarvis-sk` = **`qwen3:14b`**, Modelfile params: `temperature 0.2`, `top_p 0.85`, `top_k 30`.
- Served by **Ollama 0.32.5 on `.23`** — currently the only host serving inference.
- `prefer_local_intents: true` — HA's built-in Slovak intents are the fast path, LLM is fallback only.
- `think` mode is **OFF** (measured 0.93s vs 36.7s). **Do not re-enable without re-measuring.**

### Baseline benchmark (2026-08-07, RTX 5070 12GB, 12 tools offered)

| model | tool calls | latency | Slovak quality |
|---|---|---|---|
| `gemma4:12b` | 40/40 | 1.15s | **unusable** — answers in PL/CZ/SI |
| **`qwen3:14b` (current)** | 35/40 | 0.72s | real Slovak, occasional invented words |
| `qwen3:8b` | 30/40 | 0.50s | more errors, one fully unrelated answer |

**Critical interpretation:** temp 0.2 measurably cut invented words but cannot fix knowledge gaps
(still confabulates e.g. kapustnica recipes). Prior conclusion was that this is a **language ceiling,
not a hardware ceiling** — `gemma4:12b` scored *better* on tool calls and *worse* on Slovak. Do not
assume "bigger model = better Slovak." That assumption is exactly what Phase 3 exists to test.

### Models currently on `.23` (~48GB on 70GB free)
`jarvis-sk:latest` (8.1GB) · `jarvis-sk-q4km:latest` (9.3GB) ·
`hf.co/unsloth/Qwen3-14B-GGUF:IQ4_XS` (8.1GB) · `qwen3:14b` (9.3GB) ·
`qwen3:8b` (5.2GB) · `gemma4:12b` (7.6GB — ruled out for Slovak)

### Source of truth
`/home/admin/homelab/documentation/jarvis-voice-assistant.md` on `.15`.
**Update this doc at the end of every phase.** It is the canonical record, not this plan.

### Decisions already made (do not relitigate)
- `.59` becomes the **new default AI host**; `.23` stays online as fallback. Not a clean replacement.
- Combined 28GB VRAM as a single pool via Ollama is **not possible** — Ollama has no cross-machine
  tensor split. If a model won't fit `.59`, the answer is CPU offload (Phase 3) or llama.cpp RPC
  (Phase 6), not "merge the GPUs."
- **Accuracy > speed.** Luke has explicitly deprioritized latency for this round. A 20–30s response
  is acceptable if it's meaningfully more correct. This inverts the old 0.72s target.
- SSH: add key auth, **keep password auth enabled** (do not disable).

---

## Phase 0 — Access, safety, and baseline capture

**Goal:** be able to work on all three boxes, and be able to undo anything.

### 0.1 SSH key auth (additive — password auth stays on)
- Generate a dedicated keypair if one isn't already in use for this fleet (ed25519).
- Install the public key to:
  - `.59` → `~/.ssh/authorized_keys` for the primary user
  - `.15` → `admin@.15`
  - `.23` → `ocino@.23` — **Windows OpenSSH gotcha:** for users in the Administrators group, the
    authorized keys file is `C:\ProgramData\ssh\administrators_authorized_keys`, **not**
    `~/.ssh/authorized_keys`, and it needs restrictive ACLs (SYSTEM + Administrators only) or sshd
    silently ignores it. This is the #1 reason key auth "doesn't work" on Windows.
- **Verify key login works before moving on.** Do not touch `PasswordAuthentication` in any sshd
  config — it stays `yes`.

### 0.2 Capture rollback points
- On `.15`: back up the Home Assistant config directory and the entity registry before any HA edit
  in Phase 4. Note the exact current conversation-agent config (which Ollama URL/model it points at)
  so it can be reverted in one step.
- On `.23`: record `ollama list` output verbatim before deleting anything.
- Confirm `/mnt/synology` on `.15` is writable and has room — it's a reasonable place to park
  backups and benchmark artifacts (60GB used of 100GB).

### 0.3 Re-verify the baseline before changing anything
Run a quick end-to-end sanity check that Jarvis currently works: wake word → STT → intent/LLM → TTS.
If something is already broken, find out now, not after three phases of changes.

**Exit criteria:** key auth works on all three hosts (password still enabled), rollback points
captured, current pipeline confirmed functional.

---

## Phase 1 — Relieve `.23` disk pressure (quick win, do first)

**Goal:** get `.23` off 92% disk usage so it remains a viable fallback.

- Delete `gemma4:12b` (7.6GB) — already ruled out for Slovak, no reason to keep it.
- Evaluate for removal: `qwen3:8b` (5.2GB) — benchmarked worse than the current model on both tool
  calls and Slovak. Keep only if Luke wants it as a low-latency fallback tier.
- Look for duplication: `jarvis-sk:latest` (8.1GB) vs `hf.co/unsloth/Qwen3-14B-GGUF:IQ4_XS` (8.1GB)
  and `jarvis-sk-q4km:latest` (9.3GB) vs `qwen3:14b` (9.3GB). The `jarvis-sk*` tags are almost
  certainly Modelfile-derived from those bases. **Before deleting any base model, confirm whether
  Ollama shares blobs between the derived tag and its base** — deleting a base whose blobs are shared
  may or may not free space depending on refcounting. Check actual freed space after each delete
  rather than assuming.
- **Do not delete `jarvis-sk:latest` or `jarvis-sk-q4km:latest`** — those carry the tuned Modelfile
  params and `.23` is still the live production host until Phase 4.
- **Export the `jarvis-sk` Modelfile before touching anything** (`ollama show --modelfile jarvis-sk`)
  and save it to `/mnt/synology` — it's needed verbatim in Phase 2 and it is the only record of the
  tuned params outside the running box.
- Also worth checking on `.23`: Windows-side space hogs unrelated to Ollama (hiberfil, Windows.old,
  Temp) — 930GB with 48GB of models means ~810GB is something else. `wmic` is gone on build 10.0.26200,
  **use PowerShell**.

**Target:** ≥150GB free on `.23`.

**Exit criteria:** `.23` has meaningful headroom, Modelfile exported and saved off-box, production
pipeline still working (nothing in this phase should touch the live model).

---

## Phase 2 — Provision `.59`

**Goal:** `.59` runs Ollama on GPU, reachable from `.15`, with the current model reproduced exactly.

### 2.1 NVIDIA driver — the hard part
`.59` has Secure Boot **enabled**, and the Secure Boot CA was updated 2011→2023 with dbx →20260402
this session. This matters: unsigned DKMS kernel modules will not load under Secure Boot.

- Prefer Ubuntu's **signed** driver packages from the archive over the `.run` installer.
- Prior research on this box favored the **`580-server-open`** branch over `595` for headless
  stability. Verify what's actually available for Ubuntu 26.04 / kernel 7.0.0-29 before committing —
  branch availability may have moved since that note, and kernel 7.0 is new enough that driver
  compatibility should be confirmed rather than assumed.
- If MOK enrollment is required, it needs physical/console access at the uncle's house on next
  reboot — **flag this to Luke before starting**, because a driver install that needs MOK enrollment
  will hang at a blue MOK Manager screen that cannot be cleared over SSH.
- Verify with `nvidia-smi`: expect **RTX 5070 Ti, 16GB**. Confirm the GPU is at the expected PCIe
  link width and that persistence mode is sane for a server role.

### 2.2 Ollama
- **Install natively (not in Docker).** Rationale: direct GPU access without needing
  `nvidia-container-toolkit`, simpler systemd management, and this box's entire job is inference.
  Docker can still be installed for anything else later.
- Match or exceed `.23`'s version (0.32.5) — **check for a newer release** rather than pinning to
  0.32.5, but note the version actually installed in the docs.
- **Critical:** Ollama binds `127.0.0.1:11434` by default. It must listen on the LAN for `.15` to
  reach it. Set `OLLAMA_HOST=0.0.0.0:11434` in the systemd unit override (`systemctl edit ollama`).
  **This is the single most common reason a remote Ollama "isn't reachable."**
- Set `OLLAMA_MODELS` to a path on the 1.6TB NVMe if the default location isn't already there —
  models will get large in Phase 3.
- Consider `OLLAMA_KEEP_ALIVE` — with big models, reload cost is high; keeping the model resident
  matters more than it did at 14B.

### 2.3 Firewall
- Ubuntu default has ufw inactive. Decide deliberately: either enable ufw with an allow rule for
  `11434/tcp` from `.15` only, or leave it off and rely on the LAN boundary. **Do not expose 11434
  to the internet** — Ollama has no auth.
- `.15` runs **ufw default-deny** — verify outbound to `.59:11434` is permitted (default-deny is
  usually inbound-only, but confirm rather than assume, since this is the link the whole system
  depends on).

### 2.4 Reproduce the current model on `.59`
- Pull `qwen3:14b` and rebuild `jarvis-sk` from the **exported Modelfile** (Phase 1) — same
  `temperature 0.2` / `top_p 0.85` / `top_k 30`. This gives an apples-to-apples control for Phase 3
  and a working fallback if bigger models disappoint.
- Smoke test: a Slovak prompt over the network from `.15` returns sane output.

**Exit criteria:** `nvidia-smi` shows the 5070 Ti, Ollama serves on `0.0.0.0:11434`, `.15` can reach
it, `jarvis-sk` reproduces on `.59` with identical params. **Production still points at `.23` — no
cutover yet.**

---

## Phase 3 — Benchmark harness + model testing

**This is the substance of the plan.** Everything before it is setup; everything after depends on
its results.

### 3.1 Build a repeatable harness first
Do not hand-test models. Write a script (Python, on `.59` or `.15`) that:

- Takes: model name, Ollama endpoint, a fixed prompt set, and the 12 tool definitions currently
  offered to the conversation agent.
- Records **per prompt**: full response text, tool call made (if any), whether it matched the
  expected tool, wall-clock latency, tokens/sec, and whether the model loaded to GPU/CPU/split.
- Writes results as JSON + a human-readable markdown table to `/mnt/synology` so runs are
  comparable across sessions and survive a box being rebuilt.
- Runs each prompt **N≥3 times** — the old 35/40 vs 40/40 numbers are single-run and temp 0.2 is not
  deterministic. Report variance, not just a score.

**Recover the original 40-prompt Slovak eval set if it still exists** (check `jarvis-lab` on `.15` —
that container's purpose wasn't re-derived in the last report and it's the likely home for eval
tooling). Reusing the exact prompts makes the new numbers directly comparable to the 2026-08-07
baseline. If it's gone, rebuild it and **write it down this time**, covering:
- Home control intents that should hit tools (lights, climate, locks)
- Slovak general-knowledge questions where confabulation showed up before (**include kapustnica** —
  it's a known failure case and therefore a real regression test)
- Morphologically tricky Slovak (declension, aspect pairs) where quantization damage shows first
- Multi-turn context retention
- Questions the model *should* refuse or say it doesn't know — confabulation is the headline problem,
  so measure honesty explicitly

### 3.2 The metric problem — read this before interpreting anything
**Slovak quality cannot be auto-graded.** Tool-call accuracy and latency are machine-measurable;
"real Slovak vs invented words" is not. The harness must dump responses in a form Luke can grade by
hand — a side-by-side markdown table, same prompt across models, is the right shape.

**Grade blind where practical** (don't label which model produced which response until after
scoring). With a native speaker scoring their own infrastructure's output, expectation bias is real.

Track at minimum: invented/non-existent words, wrong-language drift (the `gemma4` failure mode),
grammatical correctness, and factual confabulation — **as separate scores.** They have different
causes and different fixes; collapsing them into one "quality" number is what makes it impossible
to tell a language-coverage problem from a quantization problem.

### 3.3 Model sweep — GPU-only first
Establish the 16GB ceiling before introducing CPU offload as a variable.

- **Control:** `jarvis-sk` (qwen3:14b) on `.59` — confirms the new box reproduces the old numbers.
  If it doesn't, stop and find out why before testing anything else.
- Candidates in the 27B–32B class at IQ4_XS / Q4_K_M.
- **Do not hardcode model names from this plan.** Query what's actually available
  (`ollama list` on the registry / Hugging Face) at execution time. Luke mentioned "qwen3.8 27b" and
  a possible Qwen3 28B released mid-August 2026 — verify current Qwen releases and their real
  parameter counts rather than trusting any name in this document. Newer Qwen point-releases may
  have materially better Slovak coverage, which is the whole thing being chased here.
- **Quantization caveat that matters specifically here:** aggressive quantization disproportionately
  degrades morphologically rich languages, and Slovak is one. A 32B at Q3 may well be *worse* Slovak
  than a 14B at Q4 despite being "bigger." Test the quantization axis, not just the size axis —
  IQ4_XS vs Q4_K_M on the same model is a meaningful comparison, not a rounding error.

### 3.4 CPU offload sweep
Luke has explicitly accepted slow responses for better answers. This is where that gets cashed in.

- Ollama controls GPU layer count via `num_gpu` (in the Modelfile or per-request options). Layers
  beyond that run on CPU against system RAM.
- `.59` has 24 threads and 30GB RAM — check `num_thread` too; the default may not use the Ultra 7's
  full thread count well, and P-core vs E-core scheduling on Intel hybrid architectures is a known
  source of bad defaults for inference.
- **Sweep:** for the best 1–2 models from 3.3, plus one model too large for 16GB, vary `num_gpu`
  across (all-GPU where it fits) → (partial) → (heavily CPU) and record the accuracy/latency curve.
- **The key question:** does a bigger model running slowly on CPU offload actually produce better
  Slovak than a smaller model running fast on GPU? Prior evidence says maybe not — that's the
  "language ceiling" hypothesis. **This sweep is the experiment that settles it.** A negative result
  is a genuinely useful result: it means stop buying hardware for this problem and start looking at
  fine-tuning or retrieval instead.
- Record real memory pressure: 30GB total RAM minus whatever else runs. Note where it starts
  swapping — that's the practical ceiling and it directly answers the 64GB question.

### 3.5 The 64GB RAM decision
Do not buy RAM before this phase produces data. Answer it empirically:
- If CPU offload shows a **real accuracy gain** and 30GB is the binding constraint → 64GB is
  justified, and it's cheap relative to a GPU.
- If accuracy plateaus or regresses with bigger models → the ceiling is the model's Slovak coverage,
  not memory. **More RAM buys nothing.** Redirect effort to Slovak fine-tunes, RAG over a Slovak
  corpus, or accepting the 14B and routing hard questions elsewhere.
- Note for the record: system RAM does not raise the *GPU* ceiling. It only extends how far CPU
  offload can go.

**Exit criteria:** a written comparison table across models × quantizations × offload configs, with
Slovak quality graded by hand, committed to the source-of-truth doc. **A clear recommendation for
which model becomes the new `jarvis-sk`** — including "keep qwen3:14b" as a legitimate outcome.

---

## Phase 4 — Cutover: `.59` primary, `.23` fallback

Only start once Phase 3 has picked a winner.

- Build the chosen model as `jarvis-sk` on `.59` with tuned params.
- Point Home Assistant's Ollama conversation agent at `.59:11434`. Keep the `.23` integration
  configured as a **second** conversation agent so falling back is a config change, not a rebuild.
- **Preserve these settings — they are load-bearing and were established by measurement:**
  - `prefer_local_intents: true` (HA Slovak intents stay the fast path; this matters *more* now, not
    less — if the LLM is slower under CPU offload, the local-intent fast path is what keeps routine
    commands snappy)
  - `think` mode **OFF** — do not re-enable without re-measuring
- **HA entity registry gotcha:** exposure flags (`should_expose=True`) for `remember_fact`,
  `forget_fact`, `confirm_pc_action`, `cancel_pc_action` must be written **with Home Assistant
  stopped** — websocket-API exposure does not survive a restart. If tool calling silently stops
  working after cutover, check this first.
- **Also check the `shell_command:` block exists** — a missing one previously caused
  `shell_command.jarvis_remember` to fire and fail with no user-visible error. Silent failure is the
  signature.
- End-to-end test in Slovak through the actual satellite (`jarvis-satellite`), not just curl against
  the API. Wake word → STT → LLM → tool → TTS.
- **Set a latency expectation with the household.** If responses go from 0.72s to 20s, people will
  assume it's broken. This is a social problem, not a technical one, and it's the most likely reason
  this migration gets reverted. Worth a conversation before cutover, not after.

**Rollback:** repoint the conversation agent at `.23`. Keep `.23`'s models intact until `.59` has run
clean for at least a week.

---

## Phase 5 — Documentation & consolidation

- Update `/home/admin/homelab/documentation/jarvis-voice-assistant.md` with: `.59`'s full
  provisioned state, driver/Ollama versions, benchmark results table, the chosen model and why, and
  the rollback procedure.
- Commit the benchmark harness and prompt set somewhere durable (`/mnt/synology` + the docs repo) —
  the fact that the 2026-08-07 eval set may not be findable is exactly the problem to avoid repeating.
- Record what `jarvis-lab` and `notify-bridge` actually do while you're in there. Two custom
  containers with undocumented purpose on the critical path is a liability.

---

## Phase 6 — Stretch: llama.cpp RPC (only if Phase 3 justifies it)

**Trigger condition:** Phase 3 shows bigger models give genuinely better Slovak *and* `.59` + CPU
offload can't fit the model that wins. If Phase 3 shows a language ceiling instead, **skip this
entirely.**

**What it is:** `llama.cpp`'s `rpc-server` exposes `.23`'s GPU as a remote backend; `llama-server` on
`.59` splits model layers across both cards, giving ~28GB combined VRAM.

**What it costs:**
- Every layer boundary crossing the network is a per-token round trip over LAN. Expect single-digit
  tokens/sec. Acceptable only under the current accuracy-over-speed stance.
- **You leave Ollama behind.** No `ollama pull`, no Modelfiles, no HA Ollama integration — manual
  GGUF management and an OpenAI-compatible endpoint that HA must be reconfigured to use.
- Two boxes now on the critical path instead of one. `.23` is a shared Windows gaming PC that
  someone else uses. Reliability goes down.

**Shape if pursued:** build llama.cpp with RPC support on both hosts, `rpc-server` on `.23` bound to
LAN, `llama-server --rpc <.23>:<port> -ngl <n>` on `.59`, benchmark against the Phase 3 harness to
prove the gain is real before touching HA.

**Explicitly ruled out: vLLM.** It targets same-machine multi-GPU or datacenter interconnect
(NVLink/InfiniBand), and is built for concurrent-request throughput rather than a single-user voice
assistant. Over a home LAN it's more complexity for no advantage over llama.cpp RPC here.

---

## Parked items (not blocking, don't let them expand scope)

- **Slovak TTS voice.** `sk_SK-lili-medium` is Piper's only Slovak voice; no male voice exists, so
  the "calm butler" tone isn't reachable as-is. Local-first options worth investigating before
  reaching for cloud TTS: a Piper fine-tune on Slovak audio (the same approach as
  `NaiveNeuron/whisper-large-v3-turbo-sk`, which was the leading STT candidate — 2,806h of Slovak
  parliament speech), or Coqui/VITS Slovak coverage. **Cloud TTS (e.g. ElevenLabs) contradicts the
  privacy-first, local-only premise of this build** and sends a household's voice interactions
  off-LAN — treat as last resort, and as Luke's call, not a default.
- **Slovak STT.** Open thread from earlier: `NaiveNeuron/whisper-large-v3-turbo-sk` as a drop-in for
  the faster-whisper container, vs `nvidia/parakeet-tdt-0.6b-v3` (lighter, needs a different Wyoming
  wrapper). **New angle:** `.59` having a GPU changes this — STT no longer has to stay on CPU-only
  `.15`. Worth revisiting *after* the LLM migration settles, not during.
- **TP-Link Tapo onboarding** (`.12`/`.13`/`.14`/`.28`/`.36`) — blocked on account credentials.
  Luke-blocked, not work-blocked.
- **OpenRouter API key** — status unclear since 2026-08-03. Relevant only if a cloud fallback tier is
  still wanted; arguably less necessary once `.59` is running a stronger local model.
- **Synology as long-term memory / RAG store.** Now that `/mnt/synology` is mounted on `.15`, it's
  available as a document store. Genuinely interesting for the confabulation problem — retrieval over
  a Slovak corpus attacks knowledge gaps in a way that a bigger model may not. **But it's a separate
  project.** Don't fold it into this migration.

---

## Gotcha appendix (things that will silently waste an hour)

1. **Ollama binds localhost by default** — `OLLAMA_HOST=0.0.0.0` in a systemd override, or `.15`
   can't reach `.59` and nothing explains why.
2. **Windows admin SSH keys** live in `C:\ProgramData\ssh\administrators_authorized_keys` with strict
   ACLs, not `~/.ssh/authorized_keys`.
3. **`wmic` is gone** on Windows 11 build 10.0.26200 — use PowerShell on `.23`.
4. **`.23` reports its RTX 5070 as 4GB** via `AdapterRAM` (32-bit overflow). It's 12GB.
5. **Secure Boot is on for `.59`** — unsigned DKMS modules won't load; MOK enrollment needs console
   access and will hang a headless boot.
6. **HA `should_expose` must be set with HA stopped** — otherwise it silently reverts on restart.
7. **A missing `shell_command:` block** makes tools fire and fail with no user-visible error.
8. **`think` mode off** — 0.93s vs 36.7s. Never re-enable without measuring.
9. **Bigger ≠ better Slovak.** `gemma4:12b` beat the current model on tool calls and was unusable.
   Quantization hits morphologically rich languages hardest. Let the harness decide, not intuition.
10. **The household uses this system.** Every phase should end with a working assistant.
