# AGENTS.md

This file provides guidance to Claude Code (and other coding agents) when working with this repository.

## What this repo is

Infrastructure-as-config for a single-host home media server (Beelink mini PC at `10.0.0.50`, Ubuntu 24.04). The repo is checked out to `/opt/media-server/` on the server and contains Docker Compose definitions plus shell utilities. There is no application code to build or test — changes are deployed by editing files and re-running `docker compose up -d`.

## Two independent compose stacks

The repo runs **two separate `docker-compose.yml` files**, not one. They are launched independently from their own directories:

- **`./docker-compose.yml`** — the media stack (Plex, Sonarr, Radarr, Lidarr, Prowlarr, SABnzbd, qBittorrent, **Livrarr**, **Audiobookshelf**, Pi-hole, Portainer).
- **`./web-server/docker-compose.yml`** — a standalone nginx serving `web-server/www/` on port 80 (landing page / dashboard). Has nothing to do with the *arr stack and shares no network or volumes with it.

When changing one, you usually do not need to touch the other.

## Source of truth for ports

The README's port table is now in sync with `docker-compose.yml`. Both should agree on these host ports: Plex 32400, Sonarr 38080, Radarr 38081, Lidarr 38082, **Livrarr 38083**, SABnzbd 8080, qBittorrent 8081, Prowlarr 9696, **Audiobookshelf 13378**, Pi-hole 8053 (web) + 53 (DNS), Portainer 9000/9443. If they ever drift, **trust `docker-compose.yml`**.

Container-internal ports are different from host ports for the *arr apps (Sonarr internal 8989 vs host 38080, etc.). Cross-container service calls use container hostnames + **internal** ports (`http://sonarr:8989`, not `:38080`). Browser/external traffic uses host ports.

## Path conventions and a gotcha

- **Server deployment path:** `/opt/media-server/` — what the README and restore instructions assume.
- **Scripts assume `$HOME/media-server/`** instead (`backup-plex.sh`, `move-episodes.sh`). This works on the original author's machine but will silently target the wrong directory if run from `/opt/media-server/`. Fix the path or `cd` accordingly before running, and prefer parameterizing over hardcoding when editing these scripts.
- **NAS mount:** `/mnt/nas/{Television,Movies,Music,Audiobooks,Backups}` — all *arr containers, Plex, and ABS bind-mount these. If a container can't see media, check the host mount first (`df -h | grep nas`).
- **Downloads:** `./downloads/` (relative to the compose file) is shared between SABnzbd, qBittorrent, and all the *arr-style apps (Sonarr, Radarr, Lidarr, Livrarr) so they can hand files off without copying across filesystems. SABnzbd `audiobooks` category drops into `./downloads/audiobooks/`.
- **ABS backups:** scheduled backups land at `/mnt/nas/Backups/audiobookshelf/` (mounted into the container as `/backups`). Files named `YYYY-MM-DDTHHMM.audiobookshelf`. Survives SSD loss.

## Common operations

All `docker compose` commands run from the directory containing the relevant compose file.

```bash
# Media stack (from repo root)
docker compose up -d                  # start/update all
docker compose pull && docker compose up -d   # update images
docker compose logs -f <service>      # follow logs for one container
docker compose restart <service>

# Web server (from web-server/)
cd web-server && docker compose up -d
```

`backup-plex.sh` stops Plex, tars the four critical Plex Media Server data dirs into `plex-migration/backup/`, and restarts Plex. The restore procedure is documented in the README and regenerated into `plex-migration/RESTORE_INSTRUCTIONS.md` by the script itself.

`move-episodes.sh` is a one-off migration helper with hardcoded episode filenames — not a general utility. Read it before running; it uses `sudo mv` with retries.

## Things to know when editing

- `.gitignore` excludes `config/*/` (per-service state, including Plex and ABS databases). Don't try to commit container state.
- Plex runs with `network_mode: host`; the other services use the default bridge network and reach each other by container name (`sonarr`, `sabnzbd`, etc.) — that's why Prowlarr/*arr configs use hostnames like `http://sonarr:8989` (internal port, not the host-published 38080).
- Most containers (`lscr.io/linuxserver/*`, ABS) take `PUID`/`PGID` env vars; we use 1000/1000 stack-wide. **Livrarr is the exception** — it ignores PUID/PGID and runs as hardcoded UID/GID 1000. Works for us by coincidence; if you ever change the stack UID, Livrarr needs upstream support to follow.
- Files written to `/mnt/nas` or `./downloads` need to be owned by 1000:1000 or the *arr apps can't import them — this is the single most common cause of "downloads not importing."
- Pi-hole binds host port 53 (DNS). On a dev machine that already has systemd-resolved, `docker compose up` for the full stack will fail on that port. Comment out the `pihole` service when testing the compose file off-server.

## Audiobook stack gotchas

- **Livrarr is alpha** (`ghcr.io/kkodecs/livrarr:0.1.0-alpha5`). We're here because Readarr was retired (upstream archived 2024) and both LinuxServer and Hotio dropped their Readarr images. Livrarr is the only actively-maintained book manager for the *arr ecosystem right now. Expect rough edges in multi-user, cover quality, and UI labels.
- **Livrarr writes to `/Audiobooks/1/<Author>/<Book>/`**, not `/Audiobooks/<Author>/<Book>/`. The `1/` is its user-namespace directory (user id 1 = admin). ABS scans recursively so it doesn't care, but any tooling that walks the audiobook tree needs to account for the extra level. Legacy audiobook migration must target the `1/` path to stay consistent.
- **Audiobookshelf serves under `/audiobookshelf` base path**, not at the URL root. URL is `http://10.0.0.50:13378/audiobookshelf/`. Same prefix is required when configuring Prologue on iOS.
- **qBittorrent rejects connections from *arr-style apps by default** due to host-header validation. Disable "Enable Host header validation" (and optionally CSRF protection) under qBittorrent → Tools → Options → Web UI for any internal containers to connect. Safe because qBit is LAN/Tailscale-only.

## Remote access

Tailscale is installed on the host (not in a container) with `--advertise-routes=10.0.0.0/24 --accept-routes`. Anything on the tailnet (phone, laptop) can reach any service at `http://10.0.0.50:<port>` via the subnet route. No port forwarding on the router; no public exposure.

The Beelink needs `net.ipv4.ip_forward=1` and `net.ipv6.conf.all.forwarding=1` for subnet routing to work. Persisted in `/etc/sysctl.d/99-tailscale.conf`.

Tailscale's MagicDNS clobber attempt of `/etc/resolv.conf` fails on this box (file is held by systemd-resolved). It's a benign warning — we don't use MagicDNS on the server itself.
