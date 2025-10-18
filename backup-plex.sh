#!/bin/bash

# Plex Metadata Backup Script
# Backs up only the essential Plex files needed to restore your library

PLEX_CONFIG="$HOME/media-server/config/plex"
BACKUP_DIR="$HOME/media-server/plex-migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "========================================="
echo "Plex Metadata Backup Script"
echo "========================================="
echo ""

# Stop Plex for consistent backup
echo "Stopping Plex container..."
cd ~/media-server
docker compose stop plex

echo "Creating backup directory..."
mkdir -p "$BACKUP_DIR"

echo ""
echo "Backing up essential Plex files..."
echo "This may take a few minutes..."
echo ""

# Create backup directory structure
mkdir -p "$BACKUP_DIR/backup"

# The most important files for Plex library
PLEX_DATA="$PLEX_CONFIG/Library/Application Support/Plex Media Server"

echo "1. Backing up Preferences.xml (server settings)..."
cp "$PLEX_DATA/Preferences.xml" "$BACKUP_DIR/backup/" 2>/dev/null

echo "2. Backing up Plug-in Support (databases - this is the big one)..."
tar -czf "$BACKUP_DIR/backup/plugin-support.tar.gz" \
  -C "$PLEX_DATA/Plug-in Support" \
  Databases/ \
  2>/dev/null

echo "3. Backing up Media folder (watch history, metadata)..."
tar -czf "$BACKUP_DIR/backup/media.tar.gz" \
  -C "$PLEX_DATA" \
  Media/ \
  2>/dev/null

echo "4. Backing up Metadata folder (posters, artwork - optional but recommended)..."
tar -czf "$BACKUP_DIR/backup/metadata.tar.gz" \
  -C "$PLEX_DATA" \
  Metadata/ \
  2>/dev/null

echo ""
echo "========================================="
echo "Creating migration instructions..."
echo "========================================="

# Create README for restoration
cat > "$BACKUP_DIR/RESTORE_INSTRUCTIONS.md" << 'EOF'
# Plex Migration Instructions

## On New Beelink Server:

### 1. Install Plex via Docker Compose
Start Plex once to create directory structure:
```bash
cd /opt/media-server
docker compose up -d plex
docker compose stop plex
```

### 2. Restore Backup Files

```bash
# Copy backup to new server first, then:
PLEX_DATA="/opt/media-server/config/plex/Library/Application Support/Plex Media Server"

# Restore preferences
cp backup/Preferences.xml "$PLEX_DATA/"

# Restore databases
tar -xzf backup/plugin-support.tar.gz -C "$PLEX_DATA/Plug-in Support/"

# Restore media metadata
tar -xzf backup/media.tar.gz -C "$PLEX_DATA/"

# Restore artwork/posters
tar -xzf backup/metadata.tar.gz -C "$PLEX_DATA/"

# Fix permissions
sudo chown -R 1000:1000 "$PLEX_DATA"
```

### 3. Update Preferences.xml

Edit `Preferences.xml` and update these values:
- Local IP address (change to 10.0.0.50)
- Any old paths that reference old server

### 4. Start Plex
```bash
docker compose up -d plex
```

### 5. Sign In
- Go to http://10.0.0.50:32400/web
- Sign in with same Plex account
- Your libraries, watch history, and metadata should all be there!

## What Gets Restored:
- ✅ All library metadata
- ✅ Watch history and progress
- ✅ Poster/artwork selections
- ✅ Collections
- ✅ Server settings
- ✅ User accounts and permissions

## What Doesn't Transfer:
- ❌ Plex Pass (will need to re-authenticate)
- ❌ Hardware transcoding settings (may need reconfiguration)
- ❌ Remote access (will need to re-enable)

## Important:
Make sure your media paths on the new server match!
- Old: /mnt/nas/Television → New: /mnt/nas/Television
- Old: /mnt/nas/Movies → New: /mnt/nas/Movies
- Old: /mnt/nas/Music → New: /mnt/nas/Music
EOF

echo ""
echo "Backup complete!"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Backup contents:"
ls -lh "$BACKUP_DIR/backup/"
echo ""
echo "Total backup size:"
du -sh "$BACKUP_DIR"
echo ""

# Restart Plex
echo "Restarting Plex container..."
docker compose start plex

echo ""
echo "========================================="
echo "Next Steps:"
echo "========================================="
echo ""
echo "1. Copy the entire plex-migration folder to the new Beelink"
echo "2. Follow instructions in RESTORE_INSTRUCTIONS.md"
echo "3. Your library will be fully restored without re-scanning!"
echo ""
echo "To copy to new server:"
echo "  scp -r $BACKUP_DIR user@10.0.0.50:/opt/media-server/"
echo ""
