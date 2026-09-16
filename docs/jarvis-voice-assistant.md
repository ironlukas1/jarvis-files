# Jarvis - local voice assistant

Local-only voice assistant: Home Assistant on this box, LLM inference on the
Windows gaming PC. No audio or house data leaves the LAN.

## Where things run

| Host | Role |
|---|---|
| `ppf-server` (192.168.100.15) | Home Assistant, Wyoming voice services |
| `DESKTOP-9VQ64J2` (192.168.100.23) | Ollama on an RTX 5070 12GB |
| Synology (192.168.100.47) | not yet integrated |

## Services

`~/homelab/homeassistant/` - HA on `network_mode: host`. Host networking is
required: Tapo/TP-Link discovery and mDNS/SSDP use LAN broadcast, which never
reaches the 172.22.0.0/16 homelab bridge. Deliberately **no Traefik labels** -
HA must not be reachable from the internet. Access is `http://192.168.100.15:8123`,
allowed by a ufw rule scoped to `192.168.100.0/24` only.

`~/homelab/voice/` - Wyoming faster-whisper (10300), Piper (10200) and
openWakeWord (10400), all bound to `127.0.0.1`. HA reaches them over loopback
because it runs host-networked, so no ufw rules are needed.

## Ollama

Runs as scheduled task "Ollama Server" (SYSTEM, at boot) on the Windows box.
Machine env vars: `OLLAMA_HOST=0.0.0.0:11434`, `OLLAMA_KEEP_ALIVE=-1`,
`OLLAMA_MODELS=C:\ollama\models`.

Windows Firewall is **disabled** on the active profile, so the scoped rule
"Ollama 11434 - HA only" is not currently enforced. Ollama has no authentication;
never port-forward 11434.

## Model choice

`gemma4:12b` - chosen after testing against `qwen3.5:9b`:

| | qwen3.5:9b | gemma4:12b |
|---|---|---|
| English | excellent, ~1.5s | good |
| Slovak | drifts to Czech, fumbles tool calls | correct |
| Latency | ~1-2s | ~1.3-5.7s |
| VRAM resident | 5.6 GB | 8.4 GB |

Slovak was the deciding factor. Both are kept pulled; switch by reconfiguring
the Ollama "conversation" subentry.

**`think` must stay false.** qwen3.5 measured 0.93s with thinking off versus
36.7s with it on - a 40x difference that makes voice unusable.

## Assist pipeline

Pipeline "Jarvis" is the default, `prefer_local_intents: true`. HA built-in
Slovak intents answer common commands instantly and correctly ("Zapni televizor"
-> "Zapinam televizor"); only unmatched phrasing reaches the LLM. This also means
the house keeps working when the gaming PC is off.

## Gotchas hit during setup

- The conversation `prompt` option **replaces** the HA base prompt, which is what
  normally supplies the current time. Without re-adding it the model invents
  times. The prompt is rendered as a Jinja template, so it now begins with a
  `Current time is ...` line built from `now().strftime(...)`.
- Two entities were both named `75TV`, which made every command fail with
  `no_valid_targets`. The Cast duplicate is unexposed; the remaining one is
  named `Televizor` with Slovak aliases.
- HA first came up as UTC/US despite correct IP geolocation. Set explicitly.

## Not done yet

- Tapo devices (.12 .13 .14 .28 .36) need TP-Link account credentials.
- Synology, Excel and browser MCP servers.
- OpenRouter routing for long agentic chains.
- No voice satellite hardware yet; pipeline is text-tested only.

## Web search tool (working)

SearxNG is published on `127.0.0.1:8888` (added to `~/homelab/searxng/docker-compose.yml`)
so the host-networked HA can reach its JSON API. Wired as a native HA tool, no MCP
server needed:

- `rest_command.searxng_search` in `configuration.yaml`
- `script.search_web` in `scripts.yaml`, exposed to Assist

Any script exposed to Assist becomes a tool the conversation agent can call. Verified:
"Kto vyhral majstrovstva sveta vo futbale 2026?" correctly returned Spain, which is
after the model training cutoff, so it genuinely searched.

Two things that had to be tuned:
- The model would not search unless the prompt explicitly ordered it to. The system
  prompt now says it MUST search for anything that may have changed since training.
- Snippets were truncated at 200 chars, which cut off the answer. Now 6 results at
  450 chars.

## Blocked

**Tapo plugs (.12 .13 .14 .28 .36)** - all five report
`SMART.TAPOPLUG encrypt_type='TPAP'`. The bundled python-kasa 0.10.2 supports only
AES, KLAP and XOR, so broadcast discovery returns zero devices. This is a firmware
change on TP-Link side, tracked upstream as python-kasa #1590 and home-assistant/core
#154300 / #157193. **Not a credentials problem** - the TP-Link account is irrelevant
until the library gains TPAP support. Options: check whether the plugs expose Matter
(newer models do, and Matter would bypass this entirely), or wait for upstream.

**OpenRouter** - the API key is valid but every request returns
`No endpoints available matching your guardrail restrictions and data policy`.
Free endpoints require enabling the training/data-sharing option at
https://openrouter.ai/settings/privacy. Also note the key has a $0 limit, so only
`:free` models will ever work. 13 free models support tool calling; the best is
`nvidia/nemotron-3-ultra-550b-a55b:free` at 1M context.

## Voice path

Verified by loopback rather than a microphone: Piper synthesised Slovak, ffmpeg
converted to 16 kHz mono PCM, and `/api/stt/stt.faster_whisper` transcribed it back.
"Zapni svetlo v kuchyni" came back as "Zatni svetlo v kuchyni" - close but the
consonant error would break intent matching. Real human speech usually does better
than synthetic; if accuracy is poor in practice, move Whisper from `small-int8` to
`medium-int8` and accept the extra CPU time, or move STT to the GPU box.

## Tapo plugs - RESOLVED

The TPAP block cleared after the third-party/local-access setting was changed in the
Tapo app. Symptom of the fix: `Discover.discover_single()` stopped raising
`UnsupportedDeviceError` and started returning `(P110)`. Broadcast discovery still
returns 0, so **add each plug by IP** rather than waiting for autodiscovery; the flow
then presents `user_auth_confirm` and accepts the TP-Link account.

All five are Tapo **P110** with energy monitoring:

| Entity | IP | Name |
|---|---|---|
| `switch.chladnicka` | .12 | fridge |
| `switch.deti` | .13 | kids room |
| `switch.za_tv` | .14 | behind TV |
| `switch.pracka` | .28 | washing machine |
| `switch.klima_nabijacka_stromcek` | .36 | AC + charger + tree |

Each also exposes power/voltage/current/daily+monthly kWh sensors, plus LED and
auto-update sub-switches. Only the five main switches are exposed to Assist; the
sub-switches are deliberately left unexposed so they do not clutter the tool list
or burn context.

**Safety note:** `switch.chladnicka` and `switch.pracka` control a fridge and a
washing machine. They are voice-controllable, so a misheard command can spoil food
or interrupt a wash cycle. STT has already been observed mishearing "Zapni" as
"Zatni". Consider unexposing those two, or leave them and accept the risk.

## Remote access (ha.misaligned.dev)

HA is reachable at `https://ha.misaligned.dev` **from the internet** (deliberate).
Traefik gained a file provider for this, because HA runs `network_mode: host` and
the docker provider cannot discover a host-networked container:

- `~/homelab/infra/dynamic/homeassistant.yml` - router + service pointing at
  `http://192.168.100.15:8123`, plus HSTS / frameDeny / nosniff headers.
- Traefik compose gained `--providers.file.directory=/dynamic` and a `./dynamic` mount.
- ufw needed a second rule: `8123 from 172.22.0.0/16`. Traefik reaches HA from the
  bridge network, not from the LAN, so the original LAN-only rule produced a 504.

Because it is public, `configuration.yaml` sets `ip_ban_enabled: true` and
`login_attempts_threshold: 5`. **Enable 2FA on the HA account** - that login page is
the only thing between the internet and the house.

Technitium serves a split-horizon record (`ha.misaligned.dev` -> `192.168.100.15`)
so LAN clients stay on the LAN instead of hairpinning out through Cloudflare.

Note the uncle's LAN and the owner's home LAN are **both** `192.168.100.0/24`, so
`192.168.100.x` addresses are ambiguous from outside. Reach the server by its public
IP and tunnel onward.

## Voice satellite (Windows)

`C:\jarvis\satellite.py` on the gaming PC streams microphone audio to HA's Assist
pipeline over the websocket API. Wake word, STT, intent and TTS all run server-side;
the satellite only moves audio. It never talks to Wyoming directly.

Scheduled task **"Jarvis Satellite"**, at logon as Ocino. It must run in an
interactive session - Windows audio devices are not reachable from a SYSTEM service,
which is why this differs from the Ollama and Whisper tasks.

It follows whatever Windows has set as the default recording/playback device and
switches within ~10s of a change. Devices are matched by **name, not index**:
PortAudio renumbers everything when a bluetooth device connects or disconnects, so
a hardcoded index silently becomes the wrong device. The default is re-read in a
fresh subprocess because PortAudio caches the device list at init.

Wake word is **"Hey Jarvis"** (`hey_jarvis`, pretrained). Bare "Jarvis" is not
available and two-syllable wake words false-trigger constantly.

Gotcha that cost a debugging round: Windows defaults stdout to cp1250, so printing a
Slovak transcript raised `UnicodeEncodeError` and killed the run *after* it had
already understood the command. The script now forces UTF-8 on stdout/stderr.

## Speech-to-text on the GPU

STT moved from the OptiPlex CPU to the RTX 5070. Measured on the same 2.85s clip:

| Engine | Time | Transcript |
|---|---|---|
| CPU `small-int8` | 2.35s | `Zatni svetlo v kuchyni a povedzme mi kolko je hodin.` |
| GPU `large-v3` | 0.91s | `Zapni svetlo v kuchyni a povedz mi, koľko je hodín.` |

The CPU model mis-hearing "Zapni" as "Zatni" had previously caused the model to call
`HassTurnOff` instead of on. large-v3 fixes it and restores diacritics.

Runs as scheduled task **"Jarvis Whisper GPU"** (SYSTEM, at boot) via
`C:\jarvis\whisper.bat`. The batch wrapper exists for one reason: CTranslate2 needs
`cublas64_12.dll` and cuDNN at *inference* time, and the pip `nvidia-cublas-cu12` /
`nvidia-cudnn-cu12` packages install them without adding them to PATH. Loading a
model succeeds without them - only inference fails - so test with a real
transcription, not a model load.

VRAM is now ~11.4 GB of 12 GB (gemma4 8.4 + whisper ~2 + desktop). Gaming on that
machine is effectively not possible while both are resident; this was a deliberate
choice. To reclaim it, set `OLLAMA_KEEP_ALIVE` to something finite.

The OptiPlex CPU whisper container is left running as a fallback and is renamed in
HA to "faster-whisper CPU (small, fallback)".

## DNS notes

**The split-horizon `ha.misaligned.dev` zone was removed.** It was created while HA
was LAN-only. Once HA became internet-exposed it did more harm than good: any client
still pointing at this DNS server received `192.168.100.15` regardless of where it
physically was, so a roaming laptop loaded HA's cached frontend and then failed to
open the websocket ("Unable to connect to Home Assistant"). All clients now resolve
via Cloudflare to the public IP, which works from both inside and outside the LAN.

If a LAN-local record is ever wanted again, scope it so it is only served to LAN
clients, or accept that roaming devices must not use this resolver.

**Known accepted risk: this DNS server is an open recursive resolver.** ufw allows
53/tcp and 53/udp from anywhere and `DNS_SERVER_RECURSION=Allow`, so any host on the
internet can resolve through it — verified from an external connection. That exposes
the line to DNS amplification abuse (spoofed source addresses turn this server into a
DDoS reflector) and lets strangers use the uncle's bandwidth. This was reviewed and
deliberately left as-is.

To close it later: set `DNS_SERVER_RECURSION=AllowOnlyForPrivateNetworks` in
`~/homelab/technitium/.env`, and narrow the ufw rules for port 53 to
`192.168.100.0/24`. Note that doing so breaks any device that relies on this resolver
while away from the uncle's LAN — check what your laptop's DNS is set to first
(`resolvectl status`), because it currently points at `109.230.37.235`.

## Backups

Automatic backups: **daily 04:30, 7 copies retained**, agent `backup.local`,
database included. Verified by generating a real backup (3.9 MB).

**Limitation worth knowing:** HA Container only offers the `backup.local` agent,
so archives land in `/config/backups` on the same NVMe as everything else. That
protects against a bad config change or a broken upgrade, but **not** against
disk failure. To fix properly, mount an SMB share from the Synology (.47) into
the container and add it as a backup location - that needs Synology credentials.

## Automations

`input_boolean.pracka_bezi` plus two automations in `automations.yaml`:

- `pracka_start` - draw above 15W marks the machine as running. The plug reads
  0.0W at rest, so 15W clears standby comfortably.
- `pracka_done` - draw below 4W **sustained for five minutes** ends the cycle and
  raises a persistent notification. The five minutes are load-bearing: washing
  machines drop to near-zero between fill, wash and spin, so an instant trigger
  announces completion mid-cycle.

Same pattern works for a dishwasher or a dryer on another P110.

Notifications currently go to HA's notification panel. For phone push, install the
Home Assistant companion app and swap `persistent_notification.create` for the
`notify.mobile_app_*` action.

## Energy dashboard

Seven meters registered: the five Tapo plugs (daily kWh) and both air
conditioners (monthly Wh). HA converts units itself. This also makes questions
like "how much power is the fridge using" answerable by voice, since the sensors
are exposed.

## Satellite audio cues

The satellite now plays a rising two-tone chime the instant the wake word fires,
and a falling tone when speech-to-text returns nothing. The second one matters:
previously a failed recognition produced complete silence, which is
indistinguishable from the wake word not being heard at all.

Tones are generated in code (no asset files) and each burst is faded in and out -
a raw sine starting at full amplitude clicks audibly. The microphone is muted for
the duration so the cue is never transcribed as speech.

## Scheduled task gotcha (cost a debugging round)

The satellite task was originally pinned to `Ocino` with `LogonType=Interactive`.
It silently stopped working because the person actually logged into that PC is a
different account (`x`) - `quser` shows the console session owner. A task pinned
to an account with no desktop session can never start, and reports
`LastTaskResult=1073807364`.

It now runs as **BUILTIN\Users with a bare LogonTrigger**, i.e. whoever logs in,
which is correct for a shared family machine. Check with:

    Export-ScheduledTask -TaskName "Jarvis Satellite"

A `<LogonTrigger/>` with no `<UserId>` means any user.

Note that starting this task manually over SSH looks like it works and then dies
with `0xC000013A` (Ctrl+C) when the SSH session closes - the process is torn down
with the session. That is an artefact of manual starts only; the logon trigger
path is unaffected. To activate it without waiting, log out and back in.
