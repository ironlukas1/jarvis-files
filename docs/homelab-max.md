# max — the homelab server

Read this first. It is the one-page map of this machine for any AI agent or human.
Snapshot verified **2026-10-12** (hostnames renamed the same night); check live state (`docker ps`, `systemctl`) before acting on it.
Deeper docs live next to this file in `/home/admin/homelab/documentation/` and
`/home/admin/homelab/homeassistant/AGENT.md` (see the "stale bits" note at the end).

## What this machine is

- **max** = this box (hostname `max` since 2026-10-12; it was `jarvis` before), IP
  **192.168.100.15**, the PC with the RTX 5070 Ti. It runs the whole homelab: 47 containers (Traefik, DNS, Home Assistant,
  Vaultwarden, Immich, Jellyfin + *arr, monitoring, …) plus the "clothes" app as host services.
- It took this role on **2026-10-11** from the old Alpine server **ppf** (now called **dell**),
  by copying `/home/admin/homelab` 1:1 and swapping IPs. Until then this box was the AI/LLM machine.
- It sits at the user's uncle's place. Physical actions (cables, power button, router) go through him.

### "jarvis" is not a machine
**Jarvis** is the voice assistant: Home Assistant's conversation agent `conversation.jarvis`
(Slovak, local), whose brain is Ollama on the gaming PC 192.168.100.23. Container names like
`jarvis-lab`, `jarvis-satellite` belong to it, and the user's AI project repo is called `jarvis`.
The machines are **max** (this server), **p620** (the AI box) and **dell** (the old server).

History trap: until 2026-10-12 *this* box's hostname was `jarvis` (and until 2026-10-11 it was the
AI box); on 2026-10-12 the P620 was briefly named `jarvis` too, before settling on `p620`. Older docs, logs and file names (`~/cutover-jarvis.sh`, `*.pre-jarvis`, `~/jarvis-prep.*`)
mean max.

## Network

| name (user's) | hostname | IP | MAC | role |
|---|---|---|---|---|
| **max** | max | 192.168.100.15 | 30:56:0f:a2:49:ee | this homelab server |
| **p620** | p620 | 192.168.100.68 | E0:4F:43:E6:C7:97 | AI box (Lenovo P620): RTX 3090, llama-swap :8000, jarvismon-web :8777 |
| **dell** | umbrel | 192.168.100.59 | b8:85:84:c3:4b:cf | Dell OptiPlex 5060 (ex ppf hub), **umbrelOS 2.0** since 2026-10-12 (Debian 13 based; web UI :80, LAN only; SSH user `umbrel`); wakes by WoL |
| petko | (Windows) | 192.168.100.23 | | gaming PC: Ollama :11434 (voice brain), PC agent :877, GPU Whisper :10300 |
| filipko | | 192.168.100.7 | | second gaming PC |
| Synology | | 192.168.100.47 | | NAS, CIFS backups |
| router | | 192.168.100.1 | | Huawei, DHCP reservations for all of the above |

- LAN 192.168.100.0/24. WAN **109.230.37.235**: router forwards **:22, :80, :443 → max**.
- `*.misaligned.dev` and `nexar.sk` are on **Cloudflare (proxied)** → WAN → Traefik here.
- The router hands out the WAN IP as the DNS server; that hairpins to **Technitium on max :53**,
  so if Technitium is down, LAN name resolution is down (use IPs, e.g. router admin at 192.168.100.1).
- The laptop cannot SSH directly to LAN IPs (AP client isolation): it does `ssh max` (= WAN IP,
  user `ocino`) and jumps from here (`ssh -J max ocino@192.168.100.68`, `admin@192.168.100.59`).
- Docker bridge network **`homelab` = 172.22.0.0/16** (gw 172.22.0.1), external, shared by all
  web services. Traefik and HA trust that range.

## Access and accounts

- User **`ocino`** (uid 1000), **passwordless sudo** (`/etc/sudoers.d/ocino-nopasswd`). ocino is in
  the docker group, but compose files and much of the tree are root-owned → use `sudo docker compose`.
- Docker daemon (`/etc/docker/daemon.json`): json-file logs capped at 10 MB × 3 per container, and
  **live-restore** on, so restarting/upgrading dockerd no longer stops the containers.
- `/home/admin` is **not a user**. It is just the path ppf used (`/home/admin/homelab`), kept so
  absolute paths in compose files and scripts still work. Owned by 1000:1000.
- SSH keys allowed for ocino (comments): `lunix@cachyT15` (laptop), `arch@cachyos-x8664`,
  `jarvis-troubleshoot`, `p620-model-sync`, `clothes-hub-pull` (forced `rrsync -ro`, from .15 only).
- **SSH is internet-facing (WAN :22) and keys-only** since 2026-10-12
  (`/etc/ssh/sshd_config.d/10-hardening.conf`: no passwords, no root, no X11, MaxAuthTries 3). Bots
  had made ~194k password attempts before that. Never re-enable password auth.
- **Second brain** (2026-10-20): `/home/ocino/ObsidianVault` is the always-on Syncthing hub copy of the
  user's Obsidian vault (`Brain/` = shared Claude memory, tasks, session archive), synced with the laptop
  and the phone. `syncthing@ocino.service` (Syncthing v2 from `apt.syncthing.net` stable-v2); GUI on
  127.0.0.1:8384 only. Staggered versioning, 365 days, in `.stversions/`.
- **Claude Code agent** (2026-10-20): Claude Code for ocino in `~/.local/bin/claude`, config in `~/.claude/`
  (auto mode, shared memory `~/ObsidianVault/Brain/memory`, guard hooks, Remote Control at startup).
  User units (`~/.config/systemd/user/`): `claude-rc.service` (always-on Remote Control server, opens in the
  Claude app), `ai-inbox.path/.timer` (tasks in `Brain/AI-Inbox.md` → `claude --bg`), `brain-nightly.timer`
  (04:00: session summaries, conflict report, git commit of the vault). Unit sources in `Brain/tools/systemd/`.

## Hardware and OS

Ubuntu 26.04.1 server (multi-user, no desktop), kernel 7.0, tz Europe/Bratislava.
Intel Core Ultra 7 270K Plus (Arrow Lake iGPU), 62 GB RAM, RTX 5070 Ti 16 GB (driver 595 open).
Disks: Kingston 2 TB NVMe = LVM root `/` (1.7 T, ~12 % used); Apacer 1 TB NVMe = `/mnt/models2`
(empty, reserved for model weights). Synology CIFS at `/mnt/synology` (fstab, creds `/etc/synology.cred`).

**GPU gotcha:** `/dev/dri/renderD128` is the **NVIDIA** card and the Intel iGPU is `renderD129`
(order not guaranteed across boots). Jellyfin therefore uses the stable path
`/dev/dri/by-path/pci-0000:00:02.0-render` (bind-mounted ro; set in `jellyfin/config/config/encoding.xml`).
Do **not** rename/remap render nodes in compose — VA-API breaks unless a node keeps its real name.
The 5070 Ti is not used by any container; it is for light AI jobs (`~/llama.cpp/build-3090`,
`~/cuda13`; llama-swap is installed but disabled with an empty config).

## Layout

```
/home/admin/homelab/          all compose projects (one dir each), owned ocino / root
  documentation/              adding-a-service.md, jarvis-voice-assistant.md, security-todo.md
  homeassistant/AGENT.md      deep doc for HA + the Jarvis voice assistant
  _dumps/                     nightly DB dumps (Immich postgres, Vaultwarden sqlite), 7 kept
  data/                       media for Jellyfin/*arr — EMPTY on max (media was not migrated, by choice)
  scripts/                    old one-off *arr/VPN setup helpers
/home/ocino/apps/clothes      clothes app source (server = apps/server, bun)
/home/ocino/builds/clothes    built artifacts; ~/clothes-data = its data + backups
/home/ocino/.config/clothes   clothes SECRETS (env, keystore, fcm-sa.json) — never print
/usr/local/sbin/ppf-backup    nightly backup script (root cron 02:00)
```

Convention here: before editing a config, copy it to `<file>.bak-<reason>` next to the original.
Many such backups exist (`*.bak-*`, `*.pre-jarvis` = state before the ppf→max move, `*.pre-gpu`).

## Services

All under `/home/admin/homelab/<project>`. Public URLs go through Traefik with Let's Encrypt.

| project | containers | public URL / access | notes |
|---|---|---|---|
| technitium | technitium | dns.misaligned.dev; :53 tcp/udp, :53443 | LAN DNS, ad-blocking, forwarders 1.1.1.1 / 8.8.8.8 over TLS |
| infra | traefik (v3.7) | :80 → :443 redirect | docker + file provider (`infra/dynamic/`), API on :8080 inside container only |
| homeassistant | homeassistant | ha.misaligned.dev; http://192.168.100.15:8123 | `network_mode: host`, route via `infra/dynamic/homeassistant.yml` |
| voice | wyoming-whisper (small-int8 sk) :10300, wyoming-whisper-router :10305, wyoming-piper (sk_SK-lili) :10200, wyoming-openwakeword :10400 | 127.0.0.1 only | HA's STT must stay `stt.whisper_router` (GPU Whisper on petko, CPU fallback here) |
| voice/satellite | jarvis-satellite | — | **stopped on purpose** (no mic on max). `sudo docker compose up -d` in that dir to restart |
| vaultwarden | vaultwarden | vault.misaligned.dev | passwords; nightly sqlite snapshot to `_dumps/` |
| immich | immich_server, _machine_learning (OpenVINO, iGPU), _postgres, _redis | immich.misaligned.dev | photos (copied fully); pg_dump nightly |
| jellyfin | jellyfin | jellyfin.misaligned.dev | QSV on the Intel iGPU (by-path, see GPU gotcha); libraries empty on max |
| media_automation | gluetun (Surfshark VPN), qbittorrent (inside gluetun's netns), prowlarr, recyclarr (daily TRaSH sync; created profiles WEB-1080p in sonarr, HD Bluray + WEB in radarr), unpackerr, cleanuparr (127.0.0.1:11011 only, ssh tunnel; admin account set up and connected to sonarr/radarr/qbittorrent 2026-10-21), prefetcharr (Jellyfin -> sonarr next-episode search; Jellyfin api key "arr-tools"), janitorr (DRY-RUN ON in config/janitorr/application.yml; deletion expirations 90d-730d; leaving-soon off; exclusion tag janitorr_keep; uses Jellyfin admin login), checkrr (:8585 internal, weekly scan, process:false = report only), flaresolverr (Cloudflare solver, Prowlarr proxy tag `flaresolverr`), radarr, sonarr, bazarr, seerr, tdarr-server/-node (jellystat removed 2026-10-21; data left in data/jellystat) | qbittorrent / prowlarr / radarr / sonarr / seerr .misaligned.dev | media not migrated → *arr may re-download monitored titles (user accepted) |
| monitoring | prometheus, alertmanager, grafana, node-exporter, cadvisor, exportarr ×3, uptime-kuma, notify-bridge | grafana / uptime .misaligned.dev | alerts → notify-bridge :8099 → HA webhook → phone push |
| dashboard | homepage, dockerproxy | home.misaligned.dev | config in `dashboard/config/` |
| searxng | searxng, searxng-valkey | search.misaligned.dev; 127.0.0.1:8888 | also the voice assistant's web-search tool |
| forgejo | forgejo (v16, SQLite, data in forgejo/data) | git.misaligned.dev (public via Traefik since 2026-10-21; host port 3300 dropped) | added 2026-10-20; registration off, sign-in required to view; HTTPS git only (SSH disabled) |
| mail | mailserver (docker-mailserver v16, Postfix+Dovecot+Rspamd, fail2ban, no ClamAV), mail-web (nginx stub that lets Traefik issue the cert for mail.misaligned.dev) | mail.misaligned.dev: SMTP 25, submission 465/587, IMAP 993 on the WAN IP 109.230.37.235 (DNS-only, not proxied) | added 2026-10-22; mailboxes menufy@ (Supabase auth SMTP), hello@, luke@misaligned.dev; passwords in mail/credentials.txt (600); TLS read from infra/letsencrypt/acme.json; DKIM selector `mail`; needs router forward of 25/465/587/993 to .15 and a PTR for the WAN IP set to mail.misaligned.dev by Orange |
| opengist / pingvin / privatebin | one each | gist / file / paste .misaligned.dev | |
| n8n | n8n (SQLite, data in n8n/data, key in n8n/.env) | n8n.misaligned.dev | added 2026-10-19; owner account created on first visit |
| menufy, nexar | nginx static sites | menufy.misaligned.dev, nexar.sk + www | |
| epicgames | epicgames-freegames | epic.misaligned.dev | claims free Epic games 4×/day; its web UI is up only during a login, **502 otherwise is normal** |
| jarvis-lab | jarvis-lab | LAN only (host net; ufw 8770/8099 from LAN) | test bench for the voice assistant; never expose publicly |
| (dell) umbrel | — (separate host .59) | umbrel.misaligned.dev | file route `infra/dynamic/umbrel.yml` → http://192.168.100.59:80; only umbrel's dashboard is public (its apps use other ports); `/mcp` needs umbrel's bearer token |
| space | space (privileged, pid: host) | space.misaligned.dev | the user's web desktop (Umbrel-like). See "space" section below |
| watchtowerr | watchtower | — | **auto-updates every container daily** (poll 86400 s, cleanup on); images are mostly `:latest` |

Not running: `code/` (code-server placeholder), `navidrome/` (music dir only), `jellyfin_automation/`
(leftover lidarr config; lidarr dropped). Container images were pulled at ppf's exact digests on
2026-10-11; watchtower moves them forward from there.

**Clothes app (host services, not docker; user units of ocino):** `clothes-api` (bun, :8790,
reached publicly as clothes.misaligned.dev via `infra/dynamic/clothes.yml` → 192.168.100.15:8790;
only `/api` and `/img` are routed, so `/` returning 404 is normal), `clothes-rembg` (127.0.0.1:7001),
`clothes-backup.timer` (03:00). Manage with `systemctl --user …` as ocino. Source of truth is the
user's laptop repo (`~/Projects/clothes`, deploy scripts push here); don't hand-edit deployed code.

## Adding or changing a service

Follow `documentation/adding-a-service.md`: compose in its own dir, join external network
`homelab`, Traefik labels (`entrypoints=websecure`, `tls.certresolver=letsencrypt`,
`loadbalancer.server.port=<container port>`), **no `ports:`** unless the service needs a raw host
port. Services on host networking (like HA) need a file-provider route in `infra/dynamic/`.
Admin panels are only behind their own logins today (see `documentation/security-todo.md`).

## Schedules and backups

| when | what | as |
|---|---|---|
| 02:00 | `/usr/local/sbin/ppf-backup` → Synology `/mnt/synology/Backups/ppf-server/` | root cron |
| 03:00 | `clothes-backup.timer` (`~/apps/clothes/deploy/backup.sh`) | ocino user timer |
| 03:15 | `/home/admin/bin/clothes-backup.sh` (pulls clothes data via rrsync key, `CLOTHES_PULL_SRC=ocino@192.168.100.15`) → `/home/admin/backups/clothes/` | ocino cron (`HOME=/home/admin`) |
| 22:04 | acme.sh cron (lists no certs; Traefik does all TLS) | ocino cron |
| daily | watchtower image updates | container |
| ~00:13 | the user's laptop pushes its backup over SSH (as ocino, `ssh max`) into `/mnt/synology/Backups/cachyT15/` | laptop timer |

`ppf-backup`: dumps Immich postgres + snapshots Vaultwarden into `_dumps/` (keeps 7), then
`rsync -a --delete` of `/home/admin/homelab` (minus `data/`, `media_automation/`, `navidrome/`,
`jellyfin/cache/`, `monitoring/prometheus/data/`, `immich/postgres/`) and `/etc/` to the Synology,
writes `LAST_BACKUP.txt` there. Log: `/var/log/ppf-backup.log`. It refuses to write if the CIFS
mount is missing. **First run on max: 2026-10-12 02:00** — check that log.

## Firewall (ufw)

Default deny incoming. Allowed: 22 (any); 8123 from LAN + 172.22/16; 8770, 8099 from LAN;
8790 from LAN + 172.22/16. rpcbind/NFS (an old leftover on :111) is disabled. **Docker-published ports bypass ufw** (80/443/53/53443 are open because
docker publishes them) — bind to 127.0.0.1 if something must stay local.
Syncthing's 22000 is **not** opened: devices reach max via QUIC hole-punching or public relays.

## Home Assistant essentials

- Config: `/home/admin/homelab/homeassistant/config/` (root-owned; `.storage/` edits only with HA
  **stopped**). Restart: `sudo docker restart homeassistant` (compose has `stop_grace_period: 60s`
  because HA needs >10 s to shut down cleanly — keep it).
- Reach it at **http://192.168.100.15:8123** (or 127.0.0.1 from this host). `127.0.0.1` sat in
  `ip_bans.yaml` from 2026-08-14 until 2026-10-12, which silently broke jarvis-lab; if a local IP shows
  up there again, something on the host is failing HA auth.
- Integrations: tplink ×5, tuya, lg_thinq, androidtv_remote, cast, xbox, ipp, mobile_app ×2, wyoming ×4,
  ollama (gaming PC .23), met, sun, backup, epic_games_store, shopping_list, radio_browser.
- Wake-on-LAN switches: Herny pocitac – Petko / – Filipko, Televízor, **P620** (`switch.p620`,
  off = ssh poweroff with `/config/.ssh/ha_ai_box`), **dell (starý server)** (`switch.ai_box` —
  entity_id kept from the old "AI Box"; wakes dell by WoL; off = `shell_command.dell_shutdown` →
  ssh `umbrel@192.168.100.59` with key `ha_ai_box`, which dell restricts to `sudo -n systemctl poweroff`
  via `/etc/sudoers.d/ha-poweroff`. umbrelOS updates switch system slots, so that sudo rule may need
  re-adding after an umbrelOS update (the key in /home persists)).
- dell's umbrelOS also has an MCP server at `http://192.168.100.59/mcp` (bearer token from umbrel's
  settings; the current token is read-only: system info, resources, OS update check, apps, VMs).
- Phone pushes: `script.notify_push` → `notify.mobile_app_xiaomi13` (respects quiet hours
  22:30–07:00). ntfy was removed 2026-09-17.
- 6 automations: washing-machine start/end, backup-failed alert, PC-action confirmation timeout,
  keep-brain-awake (wakes the gaming PC when `input_boolean.jarvis_always_ready` is on), notify-bridge relay.
- Voice assistant details (pipeline, confirmation gate, memory file, quiet hours): `homeassistant/AGENT.md`.

## Rules for agents working here

1. **Never print or copy secrets**: `*/.env`, `homeassistant/config/secrets.yaml`, `/etc/synology.cred`,
   `~/.config/clothes/*`, `infra/letsencrypt/acme.json`, `vaultwarden/data/`, `jarvis-lab/jarvis_lab.conf`,
   `space/data/space.sqlite` (HA token, sessions).
2. Ask the user before anything destructive or user-visible: deleting data, `docker compose down -v`,
   pruning volumes, changing router-facing ports, restarting HA during the day, powering hosts off.
3. Back up a file (`*.bak-<reason>`) before editing it; validate (`docker compose config -q`,
   YAML parse) before restarting a service.
4. Keep HA, jarvis-lab, voice ports and Prometheus off the public internet.
5. Prefer `sudo docker compose -f <dir>/docker-compose.yml …` over raw `docker run`.
6. Remember watchtower: a container may have changed version overnight; read its logs first.

## Open items / leftovers (as of 2026-10-12)

- Jellyfin/*arr see empty media folders: the media was not migrated (user's choice) and dell, which
  had the only copy, was wiped on 2026-10-12. It is gone; *arr may re-download monitored titles.
- `homeassistant/AGENT.md` stale bits: `binary_sensor.jarvis_brain` + its automation were **removed**
  2026-10-11; ntfy (`127.0.0.1:8880`, topic `home`) no longer exists — pushes go via the HA mobile app.
  `infra/dynamic/homeassistant.yml` says Technitium answers ha.misaligned.dev with the LAN IP; on
  2026-10-12 it returned Cloudflare IPs (no LAN override).
- Gaming-PC telemetry sensors in HA log "could not convert 'None'" while that PC is off — expected.

## No rollback any more

dell (the old ppf) was wiped on 2026-10-12, so there is no fallback copy of the pre-move homelab.
The only other copies are the nightly Synology backup (`/mnt/synology/Backups/ppf-server/`, written by
this host since 2026-10-12, by ppf before that) and `_dumps/`. Migration scripts and logs for the record:
`~/cutover-jarvis.{sh,log}`, `~/jarvis-prep.{sh,log}`.

## Change log
- 2026-10-21: jellystat + jellystat-db removed (compose + Homepage entry; backups `*.bak-remove-jellystat`; data dir kept).
  Vault git history started (`~/ObsidianVault/.git`); `Brain/tools/push-to-forgejo.sh` pushes repos to Forgejo.
- 2026-10-21: Forgejo made public (traefik.enable=true, 3300 host port removed). Cleanuparr first-run setup done (by the user).
- 2026-10-20: user `brain` removed again; vault + Syncthing moved to ocino. Claude Code agent for ocino
  (Remote Control server, AI Inbox, nightly brain job). Forgejo added (`forgejo/`).
- 2026-10-20: second brain: user `brain`, `syncthing@brain`, folder `obsidianvault` shared with
  cachyT15 (phone + p620 to follow). Plan: laptop `~/.claude/plans/sequential-fluttering-hollerith.md`.

- 2026-10-15: space v11: 3D VMs use QEMU's D-Bus display (`<graphics type='dbus'>` + gl + `<audio type='dbus'>` + ich9 sound) instead of VNC + egl-headless, for 60 fps consoles with sound; space converts old-style 3D VMs (and adds a qemu-vdagent clipboard channel to q35 VMs) when it starts them. Needed a new AppArmor drop-in `/etc/apparmor.d/abstractions/libvirt-qemu.d/space-dbus-display` (libvirt runs a per-VM dbus-daemon under the VM's profile; Ubuntu's profile lacked it). space's Dashboard reads app stats with the API keys Homepage already has: it resolves `{{HOMEPAGE_VAR_*}}` from the homepage container's environment at runtime (memory only, never written anywhere). Settings > Notifications can add an Uptime Kuma HTTP monitor per app (stops Kuma, backs up kuma.db as kuma.db.bak-space-<stamp>, inserts rows, starts it) -- not run yet, the user clicks it.
- 2026-10-14: space v10: qBittorrent opens inside space (router space-embed-qbittorrent + middleware of the same name in space-routes.yml: qBittorrent's own CSP kept, only frame-ancestors swapped; no qBittorrent config change). Tdarr 3.0: health checks enabled on Movies/Shows/Anime via its API (v3 shows "Some library queues won't be processed" without them); before-state saved in media_automation/tdarr-library-settings.bak-space-20261014-215747.json.
- 2026-10-14: space v9: VM consoles stream as video (WebRTC). New helper `/app/bin/space-stream` in the space image runs per viewer in the host network namespace (`nsenter -t 1 -n`), encodes with ffmpeg VAAPI on the iGPU (image now has intel-media-va-driver). No ufw or router changes. The user deleted their own VM `arch` themselves (confirmed).
- 2026-10-14: space v8: VM catalog (24 systems), 3D-accelerated Linux desktops. Installed qemu-system-modules-opengl, libegl1, libegl-mesa0, libgbm1, libgl1-mesa-dri (virgl/egl-headless) and genisoimage (cloud-init seed discs).
- 2026-10-14: space v7 = Phase 2 (VMs). Installed qemu-system-x86, qemu-utils, libvirt-daemon-system/clients, ovmf, swtpm(-tools), dnsmasq-base (user approved). libvirt network `default` redefined without DNS (Technitium owns :53); backup /etc/libvirt/space-backups/net-default.xml.bak-space.
- 2026-10-14: space v6 (Phase 1 done: compose/.env editor, updates, per-app access control, HA, Machines, Prometheus history). Alertmanager now also posts to space (second webhook in receiver whatsapp); Uptime Kuma got a default webhook notification "space" (Kuma has no monitors yet). Backups: alertmanager.yml.bak-space, kuma.db.bak-space.
- 2026-10-14: space v5 (Umbrel-style Spotlight, lens-style glass refraction, icon packs, up to 8 widgets with drag-to-arrange). App-only change; no homelab config touched.
- 2026-10-13: space v4 (Monitor tabs for p620/dell via space-agent, widget picker, paged desktop).
- 2026-10-13: space v3 (desktop menu, shortcuts, file thumbnails, wallpaper library + Blender renders in /mnt/models2/render).
- 2026-10-13: space v2 (WebGL liquid glass, new wallpapers, versioned deploys); NVIDIA modules reloaded (595.91 -> 595.99, fixed "Driver/library version mismatch" without a reboot).
- 2026-10-12: space web desktop deployed (space.misaligned.dev, `/space`, `/mnt/models2/{home,vms,models}`, `infra/dynamic/space-routes.yml`).

- 2026-10-11: ppf → max cutover (scripts/logs `~/cutover-jarvis.*`, `~/jarvis-prep.*`).
- 2026-10-12: hostnames max / p620 / dell; dell Wake-on-LAN fixed in its BIOS (from Linux, dell-wmi-sysman);
  SSH keys-only; rpcbind off; HA's old power-off key for this host and `/etc/sudoers.d/ha-poweroff`
  removed; docker log caps + live-restore; HA 127.0.0.1 ban lifted; Traefik's stale `group_add: 102`
  dropped; every project recreated (`~/maint-2026-10-12.{sh,log}`).
- 2026-10-12: dell wiped to a bare Alpine (homelab data incl. the only media copy, docker, NFS/CIFS,
  Synology creds, keys and histories removed; OS, SSH, WoL and HA's on/off control kept).
- 2026-10-12: dell reinstalled remotely with umbrelOS 2.0.0 (raw image via bin456789/reinstall `dd`).
  Remote/phone access to umbrel (Tailscale vs public URL) postponed by the user.
- 2026-10-12: umbrel's dashboard made public at umbrel.misaligned.dev (user's request); protected by umbrel's own login.

## Virtual machines (libvirt, added 2026-10-14)
Managed from space (Virtual Machines app); plain libvirt underneath, so `sudo virsh list --all` etc. work.
- **Files:** disks `/mnt/models2/vms/disks/<vm>.qcow2`, installer ISOs `/mnt/models2/vms/isos/` (space downloads Ubuntu,
  Debian, Fedora, HAOS and Windows 11 there; Windows comes from Microsoft's official download API), scratch
  `/mnt/models2/vms/.space/`. UEFI vars in `/var/lib/libvirt/qemu/nvram/`, TPM state in `/var/lib/libvirt/swtpm/`.
- **Network:** NAT `default` (virbr0, 192.168.122.0/24). libvirt's own DNS is **disabled** because Technitium's
  docker-published :53 blocks dnsmasq; DHCP hands out 192.168.122.1 as DNS, which Docker DNATs to Technitium.
  libvirt uses the iptables backend and its LIBVIRT_FW* chains sit before DOCKER/ufw in FORWARD, so VMs have internet.
- **Domains** are defined by space: q35 + OVMF (`OVMF_CODE_4M.fd`, Windows: `OVMF_CODE_4M.ms.fd` + `OVMF_VARS_4M.ms.fd`
  Secure Boot + swtpm TPM 2.0), CPU **host-model** (not host-passthrough: the 270K Plus is hybrid and a passthrough guest
  crashed once), VNC on a per-domain **unix socket** (no TCP ports), space bridges it to the browser (noVNC).
  Metadata `<space:vm>` in the domain XML records the preset. Snapshots = internal qcow2 snapshots taken while off.
- **3D acceleration:** Linux desktop VMs get virtio-gpu with `accel3d` + `<graphics type='egl-headless'>` rendering on the
  Intel iGPU (`/dev/dri/by-path/pci-0000:00:02.0-render`, shared with Jellyfin QSV / Immich OpenVINO). `virsh screenshot`
  fails for those ("no surface"); space captures frames over the VNC socket instead.
- **Ready-made systems** (Ubuntu/Debian cloud images, Bedrock) boot with a cloud-init seed disc `disks/<vm>-seed.iso`
  (user + password from space, also stored in the domain's `<space:login>` metadata). Bedrock = Debian cloud image that runs
  the official hijack script on first boot. Retro systems (TempleOS, FreeDOS, ReactOS, 9front) use machine `pc` + SeaBIOS + IDE.
- **Console streaming (v9, v11):** 3D VMs: `space-stream` registers a D-Bus display listener on the VM's bus (`/run/libvirt/qemu/dbus/<id>-<vm>-dbus.sock`), imports each dmabuf frame into VAAPI and encodes it there; sound comes from the D-Bus audio listener as Opus. Other VMs: space opens one `space-stream` process per viewer: it reads the VM's VNC socket (~30 fps max, QEMU's VNC refresh), encodes H.264/H.265/AV1/VP9 with ffmpeg VAAPI on renderD129 (iGPU) and sends WebRTC over UDP from max's host netns, ephemeral ports **50000-50999**, srflx via stun.cloudflare.com. Direct path = hole punching (ufw lets the replies in as ESTABLISHED); if it fails the same video goes over the space WebSocket. It waits 600 ms before its first ICE check because some routers lock a port pair when the first packet comes from outside. Processes exit with the browser tab.
- The ISO cache in `vms/isos/` is shared by all VMs; deleting a cached ISO only means the next VM downloads it again.
- Rules: deleting a VM deletes its disk; ask the user first. Don't change the `default` network back to DNS-enabled.

## Minecraft (added 2026-10-12)
`minecraft/` = itzg/minecraft-server, TYPE=MODRINTH, pack better-mc-neoforge-bmc5 **v31** (MC 1.21.1, NeoForge), 12G heap, 5 slots, :25565 (ufw open). Data in minecraft/data. Watchtower disabled for it. Public name play.misaligned.dev must be a **DNS-only** (grey cloud) A record -> WAN IP; router needs TCP 25565 -> .15 (pending user).

**Hostname routing (added 2026-10-23):** `minecraft-router/` = itzg/mc-router, the only thing on host :25565. Maps `play.misaligned.dev` -> `minecraft` (BMC5, default for bare-IP joins) and `atm.misaligned.dev` -> `atm10` (All the Mods 10, NeoForge 21.1.228, 10G, data in `minecraft-atm10/data`, from the user's atm100.zip). Both servers join docker network `mcnet` and publish no ports. Add a server = new container on `mcnet` + a MAPPING line. `atm.misaligned.dev` needs a DNS-only A record -> WAN IP. atm10 is still online-mode=true (pack default), no whitelist; BMC5 stays offline + whitelist.

## space (added 2026-10-12)
Web desktop for max at **https://space.misaligned.dev** (login = password + TOTP, single user). Source of truth:
the user's laptop repo `~/Projects/space`; deployed with its `deploy/deploy.sh` (rsync to `~/builds/space`, compose
build here). Don't hand-edit the deployed code or `space/docker-compose.yml` (deploy overwrites it, keeps `.bak-deploy`).
- Container `space` is **privileged + `pid: host`** on purpose: its Terminal app is a host shell (`nsenter` → `su - ocino`),
  it reads hwmon/GPU, manages containers via the docker socket and serves files from `/space` (the user's Home),
  `/mnt/models2/{home,vms,models}`, `homelab/data`, `/mnt/synology`, `homelab/`. Data (sqlite, account) in `space/data/`.
- It writes **`infra/dynamic/space-routes.yml`** (regenerated at start + every 10 min from Traefik's API):
  `space-embed-<app>` override routers (priority 1000, same service) that add middleware `space-embed` = strip
  X-Frame-Options + `CSP frame-ancestors https://space.misaligned.dev`, so apps open inside space windows; and
  `sp-<app>.misaligned.dev` routes for LAN-only apps (bazarr, tdarr, prometheus, alertmanager) behind
  forwardAuth to space. **Delete that file to undo all of it**; the original routers are untouched.
- **Versions:** every deploy is a git tag `vN` in the laptop repo and an image `space:vN` here (`space:latest` = running).
  Roll back: Settings > About in space, or `deploy/rollback.sh vN` from the laptop (= `docker tag space:vN space:latest`
  + `docker compose up -d --no-build` in `homelab/space`). Keep old `space:v*` images; they are the rollback points.
- **Wallpapers:** library in `space/data/wallpapers/{rendered,user}` (index.json each; user = uploads + Wallhaven
  downloads). `rendered` comes from Blender: workspace `/mnt/models2/render` (Blender 5.2.2 in `blender/`, NASA +
  Solar System Scope textures in `tex/`, scene scripts in `scripts/` = laptop repo `render/`, outputs in `out/`).
  Render: `scripts/run.sh earth saturn ...` (Cycles on the 5070 Ti via CUDA; OptiX lib not installed), publish:
  `sudo python3 scripts/publish.py`. Thumbnails (Files + wallpapers) are cached in `space/data/thumbs`.
- **space-agent** (laptop repo `agent/space-agent.py`, stdlib Python, port 9101, bearer token, allow-list
  192.168.100.15): p620 = system unit `space-agent` (/opt/space-agent, runs as nobody, token /etc/space-agent.env);
  dell = user unit of `umbrel` (~/.local/share/space-agent, token ~/.config/space-agent/token, linger enabled).
  space reads them via `SPACE_AGENTS` + `SPACE_AGENT_TOKEN` in `homelab/space/.env` (0600, not overwritten by deploys).
- **Compose editor (v6):** space can edit an app's `docker-compose.yml` / `.env` (app settings > Compose & .env). It validates with
  `docker compose config`, writes a timestamped backup next to the file (`<file>.bak-space-YYYYMMDD-HHMMSS`, newest 8 kept) and
  runs `docker compose up -d` only when the user clicks Apply. The watchtower toggle adds/removes
  `com.centurylinklabs.watchtower.enable=false` on the app's main service. Expect such edits and backups in project dirs.
- **Access per app (v6):** stored in space's DB and rendered into `space-routes.yml`: `space-embed-<app>` with `space-auth` (public host
  behind the space login, plus bridge router `space-bridge-<app>`) or `space-off-<app>` (host answers with a "turned off" page from space).
  Deleting `space-routes.yml` undoes it only until space regenerates the file (10 min); change the setting back in space instead.
- **Home Assistant token** (long-lived, created by the user) lives in `space/data/space.sqlite` (kv `ha`): treat that file as a secret.
- space-agent also reports p620's loaded llama-swap model (`llm` field, reads 127.0.0.1:8000/running).
- Notifications: docker events + webhooks `http://space:3000/hooks/<token>/{alertmanager,uptime,generic}` (token in space Settings).

## This laptop: cachyT15 (checked live 2026-10-19)

- ThinkPad T15, i5-10310U (4C/8T), 15G RAM, CachyOS, kernel 7.2.9-2-cachyos, swayfx 0.6 (sway 1.12) on Wayland, btrfs on one NVMe (`/` and `/home` share it: 237G, 66% used, 80G free). Docs elsewhere that say 84% are stale. Still mention it before anything that writes many GB.
- Login shell is **fish 4.9**. The agent Bash tool runs **zsh 5.9**: no word splitting on unquoted vars, unmatched globs error. Wrap real logic in `bash -c`.
- Aliases: `find`=`fd`, `ls`=`eza -al`, `vim`=`nvim`, `r`=`rm -rf` (never use). `command <name>` bypasses them.
- Packages: `paru` only. Python 3.14 + `uv`; never `pip install --user`. Node: v24 via Vite+ shim in fish, v26 at `/usr/bin/node` for non-fish parents; prefer `pnpm`. Also bun, deno, go, rustc (all `/usr/sbin`), `docker` at `/usr/local/bin/docker`. `paccache.timer` is enabled, btrfs scrub timer is not; no `swayidle` (no auto-lock).
- Dotfiles: **roost**. Edit `~/.roost/lunix/<app>/`, not the `~/.config` symlink. `~/.roost` has no git remote (last commit 2026-06-11). `~/.claude/` is not roost-managed.
- sudo has no tty: use `SUDO_ASKPASS` (zenity).
- Sway: `,` and `;` split commands even inside `exec`; single-quote them. `swaymsg -t get_config` does not prove a binding parses.
- Claude Code hooks in `~/.claude/hooks/`: `bash-guard.sh` (blocks `rm -rf`/`r`, warns when disk >= 85% before heavy installs/builds), `sway-check.sh` (runs `sway -C` after sway config edits).
- Home Assistant MCP: `https://ha.misaligned.dev/api/mcp`, bearer token from env `HA_TOKEN` (the LAN IP is not reachable from here).
- This file is `~/Projects/jarvis/AGENTS.md`; `~/AGENTS.md` is a symlink to it. The same section is appended on max in `/home/admin/homelab/AGENTS.md`.
