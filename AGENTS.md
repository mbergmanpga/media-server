# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure-as-config for a single-host home media server (Beelink mini PC at `10.0.0.50`, Ubuntu 24.04). The repo is checked out to `/opt/media-server/` on the server and contains Docker Compose definitions plus shell utilities. There is no application code to build or test — changes are deployed by editing files and re-running `docker compose up -d`.

## Two independent compose stacks

The repo runs **two separate `docker-compose.yml` files**, not one. They are launched independently from their own directories:

- **`./docker-compose.yml`** — the media stack (Plex, Sonarr, Radarr, Lidarr, Prowlarr, SABnzbd, qBittorrent, Pi-hole, Portainer).
- **`./web-server/docker-compose.yml`** — a standalone nginx serving `web-server/www/` on port 80 (landing page / dashboard). Has nothing to do with the *arr stack and shares no network or volumes with it.

When changing one, you usually do not need to touch the other.

## Port mapping: README is stale

The README's port table lists *container-internal* ports (8989/7878/8686). The actual `docker-compose.yml` publishes **`sonarr:38080`, `radarr:38081`, `lidarr:38082`** on the host. SABnzbd (8080), qBittorrent (8081), Prowlarr (9696), and Pi-hole admin (8053) match the README. Plex uses `network_mode: host` so all its ports are on the host directly.

If asked about a service URL, trust `docker-compose.yml` over the README.

## Path conventions and a gotcha

- **Server deployment path:** `/opt/media-server/` — what the README and restore instructions assume.
- **Scripts assume `$HOME/media-server/`** instead (`backup-plex.sh`, `move-episodes.sh`). This works on the original author's machine but will silently target the wrong directory if run from `/opt/media-server/`. Fix the path or `cd` accordingly before running, and prefer parameterizing over hardcoding when editing these scripts.
- **NAS mount:** `/mnt/nas/{Television,Movies,Music}` — all *arr containers and Plex bind-mount these. If a container can't see media, check the host mount first (`df -h | grep nas`).
- **Downloads:** `./downloads/` (relative to the compose file) is shared between SABnzbd, qBittorrent, and the *arr apps so they can hand files off without copying across filesystems.

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

- `.gitignore` excludes `config/*/` (per-service state, including Plex databases). Don't try to commit container state.
- Plex runs with `network_mode: host`; the other services use the default bridge network and reach each other by container name (`sonarr`, `sabnzbd`, etc.) — that's why Prowlarr/*arr configs use hostnames like `http://sonarr:8989` (internal port, not the host-published 38080).
- All linuxserver.io containers run as `PUID=1000`/`PGID=1000`. Files written to `/mnt/nas` or `./downloads` need to be owned by 1000:1000 or the *arr apps can't import them — this is the single most common cause of "downloads not importing."
- Pi-hole binds host port 53 (DNS). On a dev machine that already has systemd-resolved, `docker compose up` for the full stack will fail on that port. Comment out the `pihole` service when testing the compose file off-server.
