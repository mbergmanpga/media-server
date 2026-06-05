# Audiobooks + Remote Access Plan

## Goals

1. Add an audiobook library that the iOS **Prologue** app can stream from.
2. Add **Readarr** to the *arr stack for automated audiobook downloads via SABnzbd.
3. Make the *arr web UIs and SABnzbd reachable from outside the home network, without exposing services to the public internet.
4. Consolidate any pre-existing audiobooks scattered on the server into the new `/mnt/nas/Audiobooks/` library so ABS is the single source of truth.

## Decisions (locked in)

| Area | Choice |
|------|--------|
| Audiobook server | **Audiobookshelf** (ABS) |
| Readarr scope | Audiobooks only (no ebook root folder) |
| Remote access | **Tailscale** (host install with subnet router) |
| NAS storage path | `/mnt/nas/Audiobooks` |
| User/group | `PUID=1000` / `PGID=1000` (matches existing stack) |
| Timezone | `America/New_York` |

## Working assumptions (flag if any are wrong)

- **Image source:** stick with `lscr.io/linuxserver/*` images where available, matching the existing stack. ABS does not have an lscr.io image — we'll use the upstream `ghcr.io/advplyr/audiobookshelf:latest`.
- **Readarr branch:** Readarr's `latest` tag has historically lagged behind `develop`. Plan uses `lscr.io/linuxserver/readarr:develop`. Worth revisiting if it proves flaky.
- **Host port allocation:** continue the `3808x` pattern from the existing *arr apps. Audiobookshelf gets its conventional `13378`.
- **Audible metadata:** use ABS's built-in providers, which call the public `audnex.us` API. No self-hosted metadata container. Revisit only if the public API proves unreliable.
- **Backups:** use ABS's built-in scheduled backup feature; write backups to the NAS at `/mnt/nas/Backups/audiobookshelf/` so they survive an SSD loss.
- **Tailscale install mode:** install on the **host** (not in a container) and enable subnet routing for `10.0.0.0/24`. This lets a phone on Tailscale reach Pi-hole, Plex's host-mode ports, and every container's published port via one tailnet identity.
- **No reverse proxy / no auth layer.** Tailscale is the auth boundary. Anything reachable on the tailnet is implicitly trusted. We can layer Authentik later if that changes.
- **No DNS conflict from Pi-hole:** Tailscale clients use MagicDNS (100.100.100.100) by default, so Pi-hole's port 53 binding is not an issue. We will *not* push Pi-hole as the tailnet DNS server in v1.
- **Tailscale ACLs:** default-open for v1 (any device on the tailnet can reach any other). Tighten later if needed.
- **SSH access:** `ssh mbergman@10.0.0.50` reaches the Beelink and can `sudo`.

## Workflow: local edits → server deploys

This repo lives on two machines:

- **Local PC** (this one): edits, commits, planning.
- **Beelink server** at `10.0.0.50`: repo checked out at `/opt/media-server/`, containers actually run here.

Substeps below carry a location marker so it's always clear where to run them:

- `[LOCAL]` — run on this PC
- `[SERVER]` — run on the Beelink (`ssh mbergman@10.0.0.50`)
- `[BROWSER]` — web UI clicks (any machine; from outside the LAN this needs Tailscale up)
- `[PHONE]` — iOS app

### Standard deploy cycle (for any compose / config change)

```bash
# [LOCAL]
git add <files>
git commit -m "<message>"
git push

# [SERVER]
ssh mbergman@10.0.0.50
cd /opt/media-server
git pull
docker compose up -d <service>       # only recreates the changed service
docker compose logs -f <service>     # Ctrl-C once startup settles
```

### If a deploy breaks the stack

The rest of the stack keeps running — `docker compose up -d <service>` only touches the named service, so the blast radius is whatever you just added. Roll back:

```bash
# [LOCAL]
git revert HEAD
git push

# [SERVER]
cd /opt/media-server && git pull && docker compose up -d
```

### Test gates

Each step ends with a **Test gate** checklist. **Do not start the next step until every box passes.** If a test fails, fix or roll back before moving on — the failure is cheaper to diagnose now than after layering more changes on top.

### Branch strategy

This work lives on the `AudioBookShelf` feature branch (already pushed to GitHub). All step commits go to that branch. After every test gate passes, we open a PR → `main`, merge with a **merge commit** (preserves per-step history, matches PR #1's style), and the server switches back to `main`.

#### Pre-flight (one-time, before Step 1)

The server needs to be on the same branch we're pushing to, otherwise `git pull` won't see the new commits.

```bash
# [SERVER]
ssh mbergman@10.0.0.50
cd /opt/media-server
git fetch
git checkout AudioBookShelf
git pull
```

#### Post-merge (after Step 9's test gate passes)

```bash
# [LOCAL]
# Open a PR AudioBookShelf → main on GitHub, merge via the GitHub UI

# [SERVER]
cd /opt/media-server
git checkout main
git pull
# No `docker compose up -d` needed — main now matches the branch tip,
# the server is already running the final state.

# [LOCAL]
git checkout main
git pull
git branch -d AudioBookShelf
git push origin --delete AudioBookShelf
```

## Port allocations

| Service | Host port | Container port | Notes |
|---------|-----------|----------------|-------|
| Readarr | 38083 | 8787 | New |
| Audiobookshelf | 13378 | 80 | New, ABS upstream convention |
| Tailscale | n/a | n/a | Host service, no port mapping |

## Storage layout

```
/mnt/nas/
├── Television/                  (existing)
├── Movies/                      (existing)
├── Music/                       (existing)
├── Audiobooks/                  (new)
└── Backups/
    └── audiobookshelf/          (new — ABS scheduled backups land here)

/opt/media-server/
├── config/
│   ├── readarr/                 (new)
│   ├── audiobookshelf/          (new — ABS config dir, holds the SQLite DB)
│   └── audiobookshelf-metadata/ (new — ABS metadata dir, kept separate so it's easy to back up just config)
└── downloads/
    └── audiobooks/              (new — SABnzbd category drop dir)
```

Bind-mount mapping:

- Readarr: `/mnt/nas/Audiobooks → /audiobooks`, `./downloads → /downloads`
- ABS: `/mnt/nas/Audiobooks → /audiobooks` (read-write — ABS writes metadata sidecar files), `./config/audiobookshelf → /config`, `./config/audiobookshelf-metadata → /metadata`, `/mnt/nas/Backups/audiobookshelf → /backups`

## Implementation steps

### Step 1 — Tailscale on the host

Goal: be able to reach LAN services from anywhere before we add new ones to test.

1. [SERVER] Install Tailscale:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   ```
2. [SERVER] Bring it up as a subnet router (will print a login URL):
   ```bash
   sudo tailscale up --advertise-routes=10.0.0.0/24 --accept-routes
   ```
   Open the printed URL in a browser, sign in / create the tailnet.
3. [BROWSER] Tailscale admin (`https://login.tailscale.com/admin/machines`):
   - Find the Beelink machine → **Edit route settings** → enable the `10.0.0.0/24` subnet route.
   - **Disable key expiry** for this machine (servers shouldn't re-auth).
4. [PHONE] Install Tailscale from the App Store, sign in to the same tailnet.
5. [LOCAL] Install Tailscale on the laptop, sign in.
6. [SERVER] Record the machine's Tailscale name for later (Prologue setup):
   ```bash
   tailscale status | head -1
   ```

**Test gate** (must pass before Step 2):

- [ ] `[SERVER] tailscale status` shows the machine online with no errors.
- [ ] Tailscale admin console shows the `10.0.0.0/24` subnet route approved.
- [ ] [PHONE] **on cellular (wifi off)**, browser loads `http://10.0.0.50:38080` (Sonarr). This proves remote access works end-to-end.

### Step 2 — Storage prep on the server

No file changes, no compose changes. Pure server-side directory creation.

1. [SERVER]:
   ```bash
   sudo mkdir -p /mnt/nas/Audiobooks /mnt/nas/Backups/audiobookshelf
   sudo chown -R 1000:1000 /mnt/nas/Audiobooks /mnt/nas/Backups
   mkdir -p /opt/media-server/config/{readarr,audiobookshelf,audiobookshelf-metadata}
   mkdir -p /opt/media-server/downloads/audiobooks
   ```

**Test gate** (must pass before Step 3):

- [ ] `[SERVER] ls -ld /mnt/nas/Audiobooks /mnt/nas/Backups/audiobookshelf` → both owned by `1000:1000`.
- [ ] `[SERVER] ls /opt/media-server/config/` includes `readarr`, `audiobookshelf`, `audiobookshelf-metadata`.
- [ ] `[SERVER] ls -d /opt/media-server/downloads/audiobooks` exists.

### Step 3 — Add Readarr (full deploy cycle)

1. [LOCAL] Edit `docker-compose.yml`. Add this block after the `prowlarr` service:

   ```yaml
     readarr:
       image: lscr.io/linuxserver/readarr:develop
       container_name: readarr
       environment:
         - PUID=1000
         - PGID=1000
         - TZ=America/New_York
       volumes:
         - ./config/readarr:/config
         - /mnt/nas/Audiobooks:/audiobooks
         - ./downloads:/downloads
       ports:
         - 38083:8787
       restart: unless-stopped
   ```

2. [LOCAL] Commit and push:
   ```bash
   git add docker-compose.yml
   git commit -m "add readarr service for audiobook automation"
   git push
   ```

3. [SERVER] Pull and bring Readarr up:
   ```bash
   ssh mbergman@10.0.0.50
   cd /opt/media-server
   git pull
   docker compose up -d readarr
   docker compose logs -f readarr   # Ctrl-C once you see "Listening on port 8787" or similar
   ```

**Test gate** (must pass before Step 4):

- [ ] `[SERVER] docker compose ps readarr` → status `Up`.
- [ ] `[SERVER] docker compose logs readarr | tail -30` → no error stack traces.
- [ ] [BROWSER] `http://10.0.0.50:38083` loads the Readarr setup screen.
- [ ] Readarr → System → Status shows no red warnings (a "new version available" notice is fine).

### Step 4 — Add Audiobookshelf (full deploy cycle)

1. [LOCAL] Edit `docker-compose.yml`. Add this block at the end of the `services:` section (before the top-level `volumes:` block):

   ```yaml
     audiobookshelf:
       image: ghcr.io/advplyr/audiobookshelf:latest
       container_name: audiobookshelf
       environment:
         - TZ=America/New_York
       volumes:
         - ./config/audiobookshelf:/config
         - ./config/audiobookshelf-metadata:/metadata
         - /mnt/nas/Audiobooks:/audiobooks
         - /mnt/nas/Backups/audiobookshelf:/backups
       ports:
         - 13378:80
       restart: unless-stopped
   ```

2. [LOCAL] Commit and push:
   ```bash
   git add docker-compose.yml
   git commit -m "add audiobookshelf service"
   git push
   ```

3. [SERVER]:
   ```bash
   cd /opt/media-server
   git pull
   docker compose up -d audiobookshelf
   docker compose logs -f audiobookshelf
   ```

**Test gate** (must pass before Step 5):

- [ ] `[SERVER] docker compose ps audiobookshelf` → status `Up`.
- [ ] `[SERVER] docker compose logs audiobookshelf | tail -30` → no errors; you should see ABS announce its listen port.
- [ ] [BROWSER] `http://10.0.0.50:13378` loads the ABS first-run setup page.

### Step 5 — Wire Readarr into the existing stack

All UI work, no file changes. Use container hostnames + **internal** ports for cross-service URLs (they run on the same Docker bridge network).

1. [BROWSER] **SABnzbd categories** at `http://10.0.0.50:8080`:
   - Config → Categories → add category `audiobooks`, folder `audiobooks` (relative — drops into `/downloads/audiobooks`). Save.
   - Config → General → copy the API key (needed in step 2).

2. [BROWSER] **Readarr → Download Clients** at `http://10.0.0.50:38083`:
   - Settings → Download Clients → `+` → SABnzbd.
   - Host: `sabnzbd`, Port: `8080`, Category: `audiobooks`, API key from step 1.
   - Click **Test** → must be green. Save.

3. [BROWSER] **Readarr → Root Folder**:
   - Settings → Media Management → Add Root Folder → `/audiobooks`. Save.

4. [BROWSER] **Prowlarr → Apps** at `http://10.0.0.50:9696`:
   - Settings → Apps → `+` → Readarr.
   - Prowlarr Server: `http://prowlarr:9696`
   - Readarr URL: `http://readarr:8787`
   - API key: from Readarr → Settings → General.
   - **Test** → green. Save.

5. [BROWSER] **Indexer audit** in Prowlarr:
   - Confirm at least one indexer has Audiobook categories (NZBGeek, drunkenslug, etc.). If none do, add one.
   - Indexers auto-sync to Readarr; verify in Readarr → Settings → Indexers.

**Test gate** (must pass before Step 6):

- [ ] Prowlarr → Apps shows Readarr with a green check.
- [ ] Readarr → Download Clients shows SABnzbd with a green check.
- [ ] Readarr → Indexers lists ≥1 indexer.
- [ ] Readarr → search a well-known author → returns results (don't grab yet).

### Step 6 — Configure Audiobookshelf

All UI work, no file changes.

1. [BROWSER] `http://10.0.0.50:13378` — finish first-run, create admin user.
2. Add library:
   - Name: `Audiobooks`
   - Type: `Audiobook`
   - Folder: `/audiobooks`
3. Confirm metadata providers (default is fine; Audible provider uses the public `audnex.us` API).
4. Settings → Backups:
   - Enable scheduled backups.
   - Path: `/backups`.
   - Schedule: daily at 03:00 (or whatever).
   - Retention: 14 backups.
   - Click **Backup now** to test it immediately.
5. Settings → Users → create an API token for Prologue. **Note it down** (needed in Step 7).

**Test gate** (must pass before Step 7):

- [ ] ABS sidebar shows the Audiobooks library.
- [ ] [SERVER] `ls /mnt/nas/Backups/audiobookshelf/` shows a `.audiobookshelf` (or similar) backup file from the manual "Backup now".
- [ ] API token captured for Step 7.

### Step 7 — Connect Prologue and run the end-to-end test

1. [PHONE] Tailscale on (works on cellular). Open Prologue.
2. [PHONE] Add server:
   - Type: Audiobookshelf
   - URL: `http://10.0.0.50:13378` (works because Tailscale subnet route covers `10.0.0.0/24`)
   - Auth: paste the API token from Step 6.
3. [BROWSER] Readarr: add a real book (small one for test) → grab.
4. Watch the pipeline:
   - SABnzbd shows the download.
   - On completion, Readarr imports to `/mnt/nas/Audiobooks/<Author>/<Book>/`.
   - ABS auto-scans (or trigger Library → Scan).

**Test gate** (must pass before Step 8):

- [ ] [SERVER] `ls /mnt/nas/Audiobooks/` shows the new book directory.
- [ ] ABS sees the book with metadata + cover.
- [ ] [PHONE] Prologue lists the book within ~5 minutes.
- [ ] Book plays with chapter navigation.
- [ ] Position sync: scrub to 5:00, close Prologue, reopen → position preserved; same position visible in ABS web UI.

### Step 8 — Documentation

[LOCAL] Edit `README.md`:
- Add Readarr (host 38083 / container 8787) and Audiobookshelf (13378 / 80) to the port table.
- Add `Audiobooks/` and `Backups/audiobookshelf/` to NAS Storage Paths.
- Add a **Remote Access** section pointing at Tailscale; remove the WireGuard line from "Future Enhancements".
- Add brief setup notes for ABS + Prologue.

[LOCAL] Edit `AGENTS.md`:
- Add Readarr and Audiobookshelf to the service inventory.
- Note the `Audiobooks/` and `Backups/audiobookshelf/` paths.
- Note Tailscale as the remote access mechanism (host install with subnet router).

[LOCAL] Move `plan.md` to `docs/` as a historical record (renamed with date prefix so future plans can sit alongside):
```bash
mkdir -p docs
git mv plan.md docs/2026-06-audiobook-plan.md
```

[LOCAL] Commit + push:
```bash
git add README.md AGENTS.md docs/2026-06-audiobook-plan.md
git commit -m "document audiobooks stack and tailscale remote access"
git push
```

[SERVER] (optional — docs aren't read by containers, but keeps the working tree in sync):
```bash
ssh mbergman@10.0.0.50 "cd /opt/media-server && git pull"
```

**Test gate** (final):

- [ ] README port table lists all current services and matches `docker-compose.yml`.
- [ ] AGENTS.md service inventory matches reality.
- [ ] End-to-end checklist below all green.

### Step 9 — Migrate legacy audiobooks into the new library

Once Readarr → SAB → ABS is verified working with a real download (Step 7), fold in any audiobooks already on the server but outside `/mnt/nas/Audiobooks/`. Doing this **last** means the destination is known-good before you start moving precious files into it, and you can mirror the exact folder/filename pattern Readarr produces.

#### ABS library layout conventions

Before moving anything, internalize what ABS expects:

- **One book per leaf folder.** ABS treats each leaf folder as one audiobook regardless of how many audio files are inside (one `.m4b`, or 24 chapter MP3s — both are "one book").
- **Author folder at the top level** of the library root: `/mnt/nas/Audiobooks/<Author>/<Book Title>/<audio files>`. Readarr produces this same shape by default.
- **No loose files at the library root.** Every audio file must live inside a book folder.
- **Format priority:** `.m4b` (with chapters) > `.m4a` > `.mp3`. Prefer `.m4b` when you have a choice — embedded chapter markers are the whole reason ABS + Prologue beat Plex for audiobooks.
- **Split chapter MP3s:** if a book is `01 - Intro.mp3`, `02 - Chapter 1.mp3`, etc., leave the file order intact. ABS sorts alphabetically inside a book folder and treats each file as a chapter.
- **Optional sidecars ABS will pick up:**
  - `cover.jpg` / `cover.png` — book cover.
  - `desc.txt`, `reader.txt` — fallback description and narrator.
  - `metadata.json` / `metadata.abs` — ABS-native metadata override. **Don't pre-create these**; ABS writes them itself when you edit a book in the UI.
- **Folder name spelling doesn't matter for metadata.** ABS overwrites everything from the Audible match. Folder names exist for your sanity and to keep things stable across rescans.

#### 9a. Capture Readarr's actual naming pattern

Before bulk-moving anything, sample what Readarr will produce going forward so the legacy library matches and you don't need a rename pass later:

1. [SERVER] After the Step 7 test download landed, look at the folder/filename Readarr actually created:
   ```bash
   find /mnt/nas/Audiobooks -maxdepth 4 -type f | head -10
   ```
2. Note the exact pattern (typically `<Author>/<Book Title>/<Book Title>.<ext>`). [BROWSER] You can also confirm/customize this in Readarr → Settings → Media Management → File Naming.
3. Use that pattern as the target shape for everything in step 9d.

#### 9b. Discover legacy audiobooks

1. [SERVER] Find candidate audiobook files anywhere outside the new library:
   ```bash
   find /mnt/nas /opt -type f \
     \( -iname "*.m4b" -o -iname "*.aax" -o -iname "*.aa" \) \
     -not -path "*/Audiobooks/*" \
     -not -path "*/Backups/*" 2>/dev/null
   ```
   `.m4b` / `.aax` / `.aa` are nearly always audiobooks. `.mp3` / `.m4a` are ambiguous (could be music) — don't blanket-search those.
2. [SERVER] If the previous Plex setup parked audiobooks under the Music library (common — a book treated as an "album" by an "artist"), scan there explicitly:
   ```bash
   ls /mnt/nas/Music/ | head -50
   ```
   Flag any "artist" entries that are obviously book authors.
3. Build a list: `<source path> → <Author>/<Book Title>/` for each, matching the Readarr pattern from 9a.

#### 9c. Reshape flat files into book folders

If any source is a loose file like `Author - Title.m4b` sitting in a directory with other loose files, move each into its own `Author/Title/` folder *before* pointing ABS at it. ABS scans flat dumps much less cleanly than properly-nested folders.

```bash
# [SERVER] example for a single book; repeat or script per file
sudo mkdir -p "/mnt/nas/Audiobooks/<Author>/<Book Title>"
sudo mv "<source>/Author - Title.m4b" "/mnt/nas/Audiobooks/<Author>/<Book Title>/<Book Title>.m4b"
```

#### 9d. Bulk copy (don't trust mv)

For each source → destination pair, use rsync with a dry-run first. Copy-then-verify-then-delete is safer than `mv`: if anything fails mid-transfer you still have the original.

1. [SERVER] Dry-run:
   ```bash
   rsync -avh --dry-run "<source>/" "/mnt/nas/Audiobooks/<Author>/<Book>/"
   ```
   Review the listed transfers before committing.
2. [SERVER] Real copy:
   ```bash
   sudo mkdir -p "/mnt/nas/Audiobooks/<Author>/<Book>"
   sudo rsync -avh --progress "<source>/" "/mnt/nas/Audiobooks/<Author>/<Book>/"
   sudo chown -R 1000:1000 "/mnt/nas/Audiobooks/<Author>"
   ```

#### 9e. Let ABS adopt them

1. [BROWSER] ABS → Libraries → Audiobooks → **Scan** (force a full rescan if needed).
2. For each new book:
   - Confirm cover art + metadata pulled from Audible. If not: Edit → **Match** → search Audible by title.
   - Confirm chapter list. `.m4b` with embedded chapters or single `.mp3` with chapter tags show real chapters; split MP3s show one chapter per file (correct).

#### 9f. Delete originals (only after ABS adopts each book)

For each migrated source, after the book is visible and playable in ABS:

1. [SERVER] Sanity-check destination matches source size:
   ```bash
   du -sh "<source>" "/mnt/nas/Audiobooks/<Author>/<Book>/"
   ```
2. [SERVER] Delete source:
   ```bash
   sudo rm -rf "<source>"
   ```
3. If the source lived in Plex's Music library: [BROWSER] Plex → Music library → either remove the specific items, or if the library was *only* audiobooks, delete the library entirely (Settings → Manage Libraries).

**Test gate** (final for Step 9):

- [ ] Every audiobook discovered in 9b is visible and playable in ABS.
- [ ] Every original source has been deleted (or intentionally retained for a reason you can name).
- [ ] `[SERVER] find /mnt/nas -type f -iname "*.m4b" -not -path "*/Audiobooks/*"` returns no results.
- [ ] Plex audiobook content (if any existed) is cleaned up or its library removed.

## End-to-end validation (final pass)

- [ ] Phone on cellular reaches Sonarr at `http://10.0.0.50:38080` via Tailscale.
- [ ] Readarr UI loads at `:38083`, talks to Prowlarr and SABnzbd.
- [ ] SABnzbd has an `audiobooks` category that drops into `./downloads/audiobooks`.
- [ ] Audiobook download flows: Readarr search → SAB download → import to `/mnt/nas/Audiobooks/`.
- [ ] ABS sees the imported book and pulls Audible metadata.
- [ ] Prologue on iOS plays the book with chapter markers; position syncs to ABS.
- [ ] ABS scheduled backup ran and a backup file exists in `/mnt/nas/Backups/audiobookshelf/`.
- [ ] No audiobook files remain outside `/mnt/nas/Audiobooks/` (legacy migration complete).

## Out of scope (intentionally)

- WireGuard self-hosted VPN (Tailscale replaces this).
- Ebook management (Readarr will not have an ebook root folder).
- Plex integration with the audiobook library (ABS is the sole frontend for audiobooks).
- Public exposure of any service (no Cloudflare Tunnel, no reverse proxy, no port forwarding).
- Authentik / Authelia SSO layer.
- Automated cloud backups (mentioned in README "Future Enhancements"; not addressed here).

## Status

All open questions resolved. Plan is ready to execute step by step starting at Step 1. Stop and verify the test gate after each step before moving on.
