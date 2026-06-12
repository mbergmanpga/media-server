# Ebooks + Kindle Delivery Plan

## Goals

1. Add a self-hosted ebook library with **one interface for all ebooks**, kept fully separate from the audiobook stack.
2. Make ebooks readable in a browser / on phones, and **deliverable to family Kindles** with minimal friction.
3. Reuse the existing acquisition pipeline (Prowlarr → SABnzbd → Livrarr) so ebooks fetch the same way audiobooks do.
4. Consolidate the ebooks currently scattered across the NAS into the new managed library so there is a single source of truth.

## The architecture in one picture

This mirrors the audiobook stack exactly — an acquirer feeds an interface:

```
Audiobooks:  Livrarr (acquire) → /mnt/nas/Audiobooks → Audiobookshelf (read / Prologue app)
Ebooks:      Livrarr (acquire) → ingest folder → Calibre-Web-Automated (read / Send to Kindle)
```

- **Livrarr** searches indexers and downloads via SAB, then drops finished files into CWA's watched **ingest folder**. It does *not* manage the final library.
- **Calibre-Web-Automated (CWA)** owns the canonical Calibre library at `/mnt/nas/Ebooks`. It auto-imports from the ingest folder, converts to EPUB, fetches metadata/covers, files everything into a clean `Author/Title/` structure, and provides the web reader, OPDS feed, and **Send to Kindle** button.
- **Audiobookshelf is not involved.** Ebooks and audiobooks stay separate tools, separate libraries, separate NAS paths. (This is *why* CWA instead of an ABS ebook library — it avoids two tools fighting over one file tree.)
- **Prologue is not involved** — it's an audiobook player and cannot read ebooks. Reading happens in CWA's web reader, via OPDS-capable apps, or on a Kindle.

## Decisions (locked in)

| Area | Choice |
|------|--------|
| Ebook server / interface | **Calibre-Web-Automated** (CWA) |
| Acquisition manager | **Livrarr** (reuse the existing *arr pipeline; feeds CWA's ingest folder) |
| Kindle delivery | **Send to Kindle** (email), one-click from CWA |
| Canonical stored format | **EPUB** (CWA auto-converts on import; Amazon converts EPUB for Kindle) |
| Library separation | Ebooks fully separate from audiobooks — own tool, library, and NAS path |
| Existing Windows Calibre library | **Ignored** — never an organized library, just a conversion scratchpad. Start the CWA library fresh. |
| NAS storage path | `/mnt/nas/Ebooks` (CWA owns this tree, including `metadata.db`) |
| Remote access | **Tailscale** (existing host subnet router) — same boundary as the rest of the stack |
| User/group | PUID/PGID 1000:1000 (CWA honors `PUID`/`PGID`, matching the linuxserver convention) |
| Timezone | `America/New_York` |
| Host port | `38084` (continues the `3808x` pattern; CWA serves on container port 8083) |

## Working assumptions (flag if any are wrong)

- **CWA image:** `crocodilestick/calibre-web-automated:latest`. It bundles the Calibre binaries for conversion (no Calibre desktop needed) and honors `PUID`/`PGID`/`TZ`.
- **CWA mount points (their convention):** `/config` (app settings + user DB), `/calibre-library` (the Calibre library + `metadata.db`), `/cwa-book-ingest` (watched ingest folder). If `/calibre-library` is empty on first run, CWA initializes a new empty Calibre library there.
- **RESOLVED (Step 3): the Calibre library lives on a CIFS mount and that breaks SQLite locking.** `/mnt/nas` is a CIFS/SMB share (`//10.0.0.58/share`). `metadata.db` creation works, but `calibredb add` fails with `apsw.BusyError: database is locked` because CIFS can't honor SQLite's byte-range locks. Fix: add **`nobrl`** to the `/mnt/nas` options in `/etc/fstab` (`…,vers=1.0,nobrl,_netdev …`) and remount. After that, imports succeed and `metadata.db-wal`/`-shm` appear (WAL mode working). Symptom of the bug is an ingest loop: the kindle-epub-fixer rewrites the file in place, re-firing inotify, so a failing import retries forever — pull the file out of ingest while fixing. (Side note: the share is SMBv1/`vers=1.0`; bumping to `vers=3.0` is a separate hardening task, only if the Buffalo NAS supports it.)
- **Livrarr → CWA handoff is the riskiest, least-proven link.** Livrarr is alpha and its ebook side is untested in this stack. The intended flow is: Livrarr imports a finished download into the ingest folder → CWA imports it into the library and deletes it from ingest. Because CWA empties the ingest folder, **Livrarr may subsequently consider the book "missing" and try to re-grab.** This must be watched in the Step 6 test gate. Fallbacks, in order of preference: (a) point CWA's ingest at SAB's completed-ebooks dir and use Livrarr only for search/grab; (b) add `calibre-web-automated-book-downloader` (Anna's Archive sourcing) as the acquirer instead; (c) grab manually via SAB. Same risk posture as the Readarr → Livrarr pivot in the audiobook plan.
- **Send to Kindle uses SMTP.** Plan to use Gmail SMTP (`smtp.gmail.com:465`, SSL) with an **app password** — this requires 2-Step Verification enabled on the Google account (`mbergmanpga@gmail.com`). The sender address must be added to Amazon's **Approved Personal Document E-mail List**.
- **Kindle delivery is network-independent.** Amazon's cloud delivers to the device over its own wifi/Whispernet. A family member's Kindle does **not** need Tailscale or LAN access — only CWA's server needs outbound SMTP. (Tailscale/LAN only matters for *browsing* the CWA web UI; see Step 7.)
- **EPUB is the canonical format.** CWA auto-converts ingested files to EPUB. Send to Kindle sends EPUB and lets Amazon convert; modern Kindles handle this fine. (MOBI is deprecated by Amazon; don't target it.)
- **Indexers:** at least one Prowlarr indexer must have ebook categories enabled. Many Usenet indexers carry ebooks; verify in Step 5.
- **CWA has its own user system,** separate from Audiobookshelf. Family access mirrors the README "Family / multi-user access" model (Tailscale for remote, LAN for at-home), with the added per-user "Send to Kindle E-mail" field.
- **No reverse proxy / no auth layer beyond Tailscale + each app's own login** — consistent with the rest of the stack.
- **PDFs and comics (CBZ/CBR) are out of scope for the initial migration** — PDFs are ambiguous (could be non-books) and comics are a different media type. Ebook formats targeted: `.epub`, `.mobi`, `.azw`, `.azw3`, `.fb2`.

## Workflow: local edits → server deploys

Same two-machine model as the audiobook plan:

- **Local PC**: edits, commits, planning.
- **Beelink server** at `10.0.0.50`: repo at `/opt/media-server/`, containers run here.

Location markers on each substep:

- `[LOCAL]` — this PC
- `[SERVER]` — the Beelink (`ssh mbergman@10.0.0.50`)
- `[BROWSER]` — web UI clicks (Tailscale up if off-LAN)
- `[KINDLE]` — on a Kindle / in the Amazon account

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

```bash
# [LOCAL]
git revert HEAD
git push
# [SERVER]
cd /opt/media-server && git pull && docker compose up -d
```

The blast radius is just the named service; the rest of the stack keeps running.

### Test gates

Each step ends with a **Test gate**. Do not start the next step until every box passes.

### Branch strategy

Work on a feature branch `Ebooks`, push to GitHub, open a PR → `main`, merge with a **merge commit** (matches the AudioBookShelf PR style). The server tracks the branch during the work, then switches back to `main` after merge.

```bash
# Pre-flight (one-time) [SERVER]
ssh mbergman@10.0.0.50
cd /opt/media-server
git fetch && git checkout Ebooks && git pull
```

## Port allocation

| Service | Host port | Container port | Notes |
|---------|-----------|----------------|-------|
| Calibre-Web-Automated | 38084 | 8083 | New (continues the `3808x` pattern) |

## Storage layout

```
/mnt/nas/
├── Audiobooks/                 (existing)
├── Ebooks/                     (new — Calibre library; CWA owns this tree + metadata.db)
└── Backups/
    └── calibre-web-automated/  (new — periodic copy of CWA /config)

/opt/media-server/
├── config/
│   └── calibre-web-automated/  (new — CWA app settings + user DB)
└── downloads/
    ├── ebooks/                 (new — SABnzbd "ebooks" category drop dir)
    └── ebook-ingest/           (new — Livrarr import target; CWA watches & ingests from here)
```

Bind-mount mapping for CWA:

- `/mnt/nas/Ebooks → /calibre-library` (the Calibre library)
- `./downloads/ebook-ingest → /cwa-book-ingest` (watched ingest folder)
- `./config/calibre-web-automated → /config`

Livrarr needs **no new mount** — it already mounts `./downloads → /downloads`, so its ebook root folder is set to `/downloads/ebook-ingest` (the same dir CWA watches).

## Implementation steps

### Step 1 — Storage prep on the server

No compose changes. Pure directory creation.

```bash
# [SERVER]
sudo mkdir -p /mnt/nas/Ebooks /mnt/nas/Backups/calibre-web-automated
sudo chown -R 1000:1000 /mnt/nas/Ebooks /mnt/nas/Backups/calibre-web-automated
mkdir -p /opt/media-server/config/calibre-web-automated
mkdir -p /opt/media-server/downloads/ebooks /opt/media-server/downloads/ebook-ingest
```

**Test gate:**

- [ ] `[SERVER] ls -ld /mnt/nas/Ebooks` → owned by `1000:1000`.
- [ ] `[SERVER] ls /opt/media-server/config/` includes `calibre-web-automated`.
- [ ] `[SERVER] ls -d /opt/media-server/downloads/{ebooks,ebook-ingest}` both exist.

### Step 2 — Add Calibre-Web-Automated (full deploy cycle)

1. [LOCAL] Edit `docker-compose.yml`. Add this block (after `audiobookshelf`, before the top-level `volumes:`):

   ```yaml
     calibre-web-automated:
       image: crocodilestick/calibre-web-automated:latest
       container_name: calibre-web-automated
       environment:
         - PUID=1000
         - PGID=1000
         - TZ=America/New_York
       volumes:
         - ./config/calibre-web-automated:/config
         - /mnt/nas/Ebooks:/calibre-library
         - ./downloads/ebook-ingest:/cwa-book-ingest
       ports:
         - 38084:8083
       restart: unless-stopped
   ```

2. [LOCAL] Commit + push:
   ```bash
   git add docker-compose.yml
   git commit -m "add calibre-web-automated for ebook management"
   git push
   ```

3. [SERVER]:
   ```bash
   cd /opt/media-server
   git pull
   docker compose up -d calibre-web-automated
   docker compose logs -f calibre-web-automated   # Ctrl-C once it announces its listen port
   ```

4. [BROWSER] `http://10.0.0.50:38084` → log in with the CWA default admin (`admin` / `admin123`), then **immediately change the admin password**. If prompted for a library location, point it at `/calibre-library` (CWA initializes an empty library there if none exists).

**Test gate:**

- [ ] `[SERVER] docker compose ps calibre-web-automated` → `Up`.
- [ ] `[SERVER] docker compose logs calibre-web-automated | tail -30` → no error stack traces.
- [ ] [BROWSER] CWA UI loads and admin login works (password changed).
- [ ] `[SERVER] ls /mnt/nas/Ebooks` shows a `metadata.db` (library initialized).

### Step 3 — Configure CWA

All UI work.

1. [BROWSER] **Admin → Settings**:
   - **Auto-convert** ingested books → target format **EPUB**. (Optionally keep the original format too.)
   - Confirm the **ingest folder** is `/cwa-book-ingest` and the **library** is `/calibre-library`.
   - Metadata providers: leave defaults (Google Books / Amazon scrapers) enabled.
2. [BROWSER] **Smoke-test ingest**: drop one known EPUB into `/opt/media-server/downloads/ebook-ingest` (`[SERVER]` copy a test file in). Within a minute CWA should import it, convert if needed, fetch a cover, and file it under `/mnt/nas/Ebooks/<Author>/<Title>/`, then empty the ingest folder.

**Test gate:**

- [ ] Auto-convert target is EPUB.
- [ ] Test EPUB appears in the CWA library with a cover + metadata.
- [ ] `[SERVER] ls /opt/media-server/downloads/ebook-ingest` is empty after import (CWA consumed it).
- [ ] [BROWSER] The book opens in CWA's web reader.

### Step 4 — Wire Livrarr to fetch ebooks into the ingest folder

All UI work, no file changes.

1. [BROWSER] **SABnzbd** (`http://10.0.0.50:8080`) → Config → Categories → add category `ebooks`, folder `ebooks` (drops into `/downloads/ebooks`). Save.
2. [BROWSER] **Livrarr** (`http://10.0.0.50:38083`):
   - Download Clients → add/confirm SABnzbd: host `sabnzbd`, port `8080`, category `ebooks`, API key.
   - Root Folder → add `/downloads/ebook-ingest` (this is the CWA ingest dir, reachable via Livrarr's existing `/downloads` mount).
3. [BROWSER] **Indexers**:
   - Ensure Livrarr is pointed at Prowlarr (or has indexers added directly) with **ebook categories** enabled.

**Test gate:**

- [ ] Livrarr → Download Clients shows SABnzbd healthy with category `ebooks`.
- [ ] Livrarr lists ≥1 indexer with ebook categories.
- [ ] Livrarr search for a known ebook title returns results (don't grab yet).

### Step 5 — Set up Send to Kindle

1. [BROWSER] **CWA → Admin → Edit E-mail Server Settings**: SMTP `smtp.gmail.com`, port `465`, SSL, sender `mbergmanpga@gmail.com`, password = a **Google app password** (create at the Google account security page; requires 2-Step Verification). Save and use CWA's **Send test email** button.
2. [KINDLE] In the Amazon account → **Manage Your Content and Devices → Preferences → Personal Document Settings**:
   - Note each Kindle's `@kindle.com` address.
   - Add `mbergmanpga@gmail.com` to the **Approved Personal Document E-mail List**.
3. [BROWSER] **CWA → user profile** (admin first): set **Send to Kindle E-mail** = the target Kindle's `@kindle.com` address.

**Test gate:**

- [ ] CWA "Send test email" succeeds (no SMTP auth error).
- [ ] [BROWSER] Open the test book from Step 3 → **Send to Kindle**.
- [ ] [KINDLE] The book arrives on the Kindle within a few minutes and opens correctly.

### Step 6 — End-to-end acquisition test

1. [BROWSER] Livrarr → add a real (small) ebook → grab.
2. Watch the pipeline:
   - SABnzbd shows the download → completes into `/downloads/ebooks`.
   - Livrarr imports it into `/downloads/ebook-ingest`.
   - CWA ingests → converts to EPUB → files into `/mnt/nas/Ebooks/<Author>/<Title>/` → empties ingest.
   - Book appears in CWA.
3. **Watch for the known risk:** after CWA empties the ingest folder, confirm Livrarr does **not** flag the book missing and re-grab in a loop. If it does, switch to a fallback from Working Assumptions (point CWA ingest at SAB's `/downloads/ebooks` and use Livrarr for search/grab only, or swap in `calibre-web-automated-book-downloader`).

**Test gate:**

- [ ] Book flows end-to-end and is readable in CWA.
- [ ] No Livrarr re-grab loop after CWA consumes the file.
- [ ] Send to Kindle works for the newly acquired book.

### Step 7 — Family / multi-user access

Mirrors the README "Family / multi-user access" section, plus a Kindle field.

1. [BROWSER] **CWA → Admin → Add User** per family member:
   - Username + password.
   - Library access (single shared ebook library for now; a separate kids' shelf can come later via tags/custom columns).
   - **Send to Kindle E-mail** = that person's Kindle address.
   - Permissions: enable download / Send-to-Kindle; leave admin off.
2. Access path per person:
   - **Remote browsing** → Tailscale invite (existing tailnet), then `http://10.0.0.50:38084`.
   - **LAN-only browsing** → no Tailscale; same URL on home wifi.
   - **Kindle delivery** → works regardless of network (Amazon cloud delivers); just add each Kindle's address to the Amazon approved list and the user's CWA profile.

**Test gate:**

- [ ] A second user logs into CWA and can read + Send to Kindle to their own device.
- [ ] That user cannot see admin settings.

### Step 8 — Migrate the scattered ebook mess

Do this **last**, once the ingest pipeline is known-good. CWA's ingest folder converts + organizes whatever it's given, so migration is "discover → stage → let CWA adopt → verify → delete originals."

#### 8a. Discover scattered ebooks

```bash
# [SERVER]
find /mnt/nas /opt -type f \
  \( -iname "*.epub" -o -iname "*.mobi" -o -iname "*.azw" -o -iname "*.azw3" -o -iname "*.fb2" \) \
  -not -path "*/Ebooks/*" -not -path "*/Backups/*" 2>/dev/null
```

Review the list. (PDFs and CBZ/CBR are intentionally excluded — handle separately if wanted.)

#### 8b. Stage into the ingest folder in batches

Copy (don't move) a manageable batch into the ingest folder so CWA imports them. Copy-then-verify-then-delete is safer than `mv`.

```bash
# [SERVER] example — repeat per batch
sudo rsync -avh --progress "<source dir or files>" /opt/media-server/downloads/ebook-ingest/
sudo chown -R 1000:1000 /opt/media-server/downloads/ebook-ingest/
```

CWA imports, converts to EPUB, fetches metadata/covers, files into `/mnt/nas/Ebooks/`, and empties the ingest folder. Work in batches so duplicates and bad metadata are easy to spot.

#### 8c. Let CWA adopt + fix metadata

[BROWSER] In CWA, for each imported book confirm cover + metadata. Where wrong, edit metadata / re-fetch. Duplicates: CWA flags or you merge/delete in the UI.

#### 8d. Delete originals (only after CWA has adopted each)

```bash
# [SERVER] after confirming the book is in CWA and readable
sudo rm -f "<original source file>"
```

**Test gate (final for Step 8):**

- [ ] Every ebook found in 8a is present and readable in CWA (or intentionally skipped for a nameable reason).
- [ ] `[SERVER] find /mnt/nas -type f \( -iname "*.epub" -o -iname "*.mobi" -o -iname "*.azw3" \) -not -path "*/Ebooks/*"` returns nothing.

### Step 9 — Documentation

[LOCAL] Edit `README.md`:
- Add Calibre-Web-Automated (host 38084 / container 8083) to the port table and the service list.
- Add `Ebooks/` and `Backups/calibre-web-automated/` to NAS storage paths.
- Add a setup section: CWA library/ingest config, Livrarr ebook wiring, Send to Kindle (SMTP + Amazon approved sender), and the multi-user/Kindle access path.
- Note ebooks are separate from audiobooks (CWA vs ABS) and that Prologue does not read ebooks.

[LOCAL] Edit `AGENTS.md`:
- Add CWA to the service inventory; note `/mnt/nas/Ebooks` path and the Livrarr→CWA ingest pipeline.

[LOCAL] Commit + push, open PR `Ebooks` → `main`, merge with a merge commit. Then `[SERVER] git checkout main && git pull`.

**Test gate (final):**

- [ ] README port table + storage paths match `docker-compose.yml`.
- [ ] End-to-end validation below all green.

## End-to-end validation (final pass)

- [ ] CWA UI loads at `:38084`; admin password changed from default.
- [ ] Livrarr search → SAB download → import to ingest → CWA library, with no re-grab loop.
- [ ] CWA stores EPUB, organized under `/mnt/nas/Ebooks/<Author>/<Title>/`.
- [ ] Book reads in CWA's web reader.
- [ ] Send to Kindle delivers to a real Kindle (works off-LAN, no Tailscale on the Kindle).
- [ ] A second family user can read + Send to Kindle to their own device.
- [ ] No stray ebook files left outside `/mnt/nas/Ebooks/` (legacy migration complete).
- [ ] CWA `/config` included in a periodic backup to `/mnt/nas/Backups/calibre-web-automated/`.

## Out of scope (intentionally)

- Audiobookshelf ebook library (CWA is the sole ebook frontend; ABS stays audiobook-only).
- Prologue ebook reading (Prologue is audiobook-only by design).
- PDFs and comics (CBZ/CBR) — different media types; revisit separately if wanted.
- `calibre-web-automated-book-downloader` — kept as a documented fallback only; Livrarr is the chosen acquirer.
- Public exposure / reverse proxy / SSO (Tailscale remains the remote-access boundary).
- Migrating the Windows Calibre install (no organized library to preserve).

## Status

Decisions resolved. Ready to execute step by step starting at Step 1. Stop and verify the test gate after each step before moving on. The Livrarr → CWA ingest handoff (Step 6) is the highest-risk link — validate it before the bulk migration in Step 8.
