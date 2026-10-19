# jarvis repo — read this first

This repo = the AI-box tooling (model switcher `bin/model`, llama-swap config, benchmarks, jarvismon).
It runs from the laptop `cachyT15` and talks to other machines. Full homelab map: [docs/homelab-max.md](docs/homelab-max.md).

## Names (final since 2026-10-12): name = hostname = ssh alias

| name | ssh | IP | role |
|---|---|---|---|
| **p620** | `ssh p620` | 192.168.100.68 | AI box: Lenovo P620, RTX 3090, llama-swap :8000, jarvismon-web :8777. This repo's target. |
| **max** | `ssh max` | 192.168.100.15 | Homelab server (RTX 5070 Ti): 47 containers, Traefik, Home Assistant, Immich, Jellyfin... Agent doc on it: `/home/admin/homelab/AGENTS.md` |
| **dell** | `ssh dell` (user `umbrel`) | 192.168.100.59 | Old ppf OptiPlex, umbrelOS 2.0, WoL-woken, usually idle |
| petko | — | 192.168.100.23 | Windows gaming PC: Ollama :11434 (voice brain) |
| Synology | — | 192.168.100.47 | NAS, backups |

- **"jarvis" is NOT a machine.** It is the HA voice assistant (`conversation.jarvis`) and this repo's name.
- History trap: before 2026-10-12 "jarvis" = the box now called **max**; "ppf"/"hub" = **dell**. Old notes, logs, and files (`*.pre-jarvis`, `cutover-jarvis.sh`) mean max.
- The Fedora client 192.168.31.142 is the user's gaming PC at home, usually off, not yet repointed to p620.

## Access from the laptop

- Only `max` is direct (WAN 109.230.37.235, keys-only). `p620` and `dell` go through `ProxyJump max` (see `~/.ssh/config`).
- The LAN is not reachable directly from the laptop (AP isolation). Start with `ssh max`.
- `bin/model`, `bin/bench-model`, `bin/benchmark` default to `MODEL_REMOTE=p620`.

## How the pieces connect

- Laptop → p620: model switching, benchmarks (llama-swap :8000); `bin/model` writes pi + opencode configs.
- max → p620 / dell: Home Assistant, the `space` web desktop (space.misaligned.dev), and monitoring reach them over the LAN; space-agent on :9101 runs on p620 and dell.
- max → dell: HA `switch.ai_box` wakes dell by WoL and powers it off via ssh.
- Public: `*.misaligned.dev` and nexar.sk → Cloudflare → WAN :80/:443 → Traefik on max. `umbrel.misaligned.dev` → dell dashboard only.

## Rules

- Never print or copy secrets (`.env`, `secrets.yaml`, tokens, `/etc/synology.cred`).
- Never re-enable SSH password auth on max.
- Check live state before trusting any doc. Update `/home/admin/homelab/AGENTS.md` on max when the homelab changes, then re-copy it to `docs/homelab-max.md`.
- The server is at the user's uncle's place; physical actions go through him.

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
