#!/bin/bash

# Script to move downloaded TV episodes to proper folders
# With retry logic and error handling

MAX_RETRIES=3
RETRY_DELAY=2

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to move file with retry logic
move_with_retry() {
    local source="$1"
    local dest="$2"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if [ ! -f "$source" ] && [ ! -d "$source" ]; then
            echo -e "${YELLOW}⚠ Source not found (may have already moved): $source${NC}"
            return 0
        fi
        
        echo "Attempting to move: $(basename "$source")"
        if timeout 30 sudo mv "$source" "$dest" 2>/dev/null; then
            echo -e "${GREEN}✓ Successfully moved${NC}"
            return 0
        else
            retries=$((retries + 1))
            if [ $retries -lt $MAX_RETRIES ]; then
                echo -e "${YELLOW}⚠ Move failed, retry $retries/$MAX_RETRIES in ${RETRY_DELAY}s...${NC}"
                sleep $RETRY_DELAY
            else
                echo -e "${RED}✗ Failed after $MAX_RETRIES attempts: $(basename "$source")${NC}"
                echo "  Source: $source"
                echo "  Dest: $dest"
                return 1
            fi
        fi
    done
}

# Function to create directory with error handling
create_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        if ! sudo mkdir -p "$dir" 2>/dev/null; then
            echo -e "${RED}✗ Failed to create directory: $dir${NC}"
            return 1
        fi
    fi
    return 0
}

echo "========================================="
echo "TV Episode Migration Script"
echo "========================================="
echo ""

# Check if NAS is mounted
if [ ! -d "/mnt/nas/Television" ]; then
    echo -e "${RED}✗ ERROR: NAS not mounted at /mnt/nas/Television${NC}"
    echo "Please mount the NAS first and try again."
    exit 1
fi

# Check if downloads folder exists
if [ ! -d "$HOME/media-server/downloads" ]; then
    echo -e "${RED}✗ ERROR: Downloads folder not found${NC}"
    exit 1
fi

echo "Creating season folders..."
echo ""

# Create all season folders
create_dir "/mnt/nas/Television/Evil/Season 04" || exit 1
create_dir "/mnt/nas/Television/Invasion (2021)/Season 03" || exit 1
create_dir "/mnt/nas/Television/Slow Horses/Season 05" || exit 1
create_dir "/mnt/nas/Television/Foundation (2021)/Season 03" || exit 1
create_dir "/mnt/nas/Television/Game of Thrones/Season 03" || exit 1
create_dir "/mnt/nas/Television/Game of Thrones/Season 04" || exit 1
create_dir "/mnt/nas/Television/The Morning Show/Season 04" || exit 1

echo ""
echo "Moving files..."
echo "========================================="
echo ""

FAILED_COUNT=0

# Evil S04E13
echo "Evil S04E13..."
move_with_retry \
  "$HOME/media-server/downloads/Evil.S04E13.REPACK.MULTi.1080p.WEB.H264-AMB3R[EZTVx.to].mkv" \
  "/mnt/nas/Television/Evil/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

# Invasion S03E07
echo "Invasion S03E07..."
move_with_retry \
  "$HOME/media-server/downloads/Invasion 2021 S03E07 Outpost 17 1080p ATVP WEB-DL DDP5 1 Atmos H 264-FLUX[EZTVx.to].mkv" \
  "/mnt/nas/Television/Invasion (2021)/Season 03/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

# Slow Horses S05E02
echo "Slow Horses S05E02..."
move_with_retry \
  "$HOME/media-server/downloads/Slow.Horses.S05E02.1080p.WEB.h264-ETHEL[EZTVx.to].mkv" \
  "/mnt/nas/Television/Slow Horses/Season 05/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

# Slow Horses S05E03
echo "Slow Horses S05E03..."
move_with_retry \
  "$HOME/media-server/downloads/Slow.Horses.S05E03.1080p.WEB.h264-ETHEL[EZTVx.to].mkv" \
  "/mnt/nas/Television/Slow Horses/Season 05/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

# Foundation S03E07
echo "Foundation S03E07..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Foundation 2021 S03E07 Foundations End REPACK 1080p ATVP WEB-DL DDP5 1 Atmos H 264-FLUX/Foundation 2021 S03E07 Foundations End REPACK 1080p ATVP WEB-DL DDP5 1 Atmos H 264-FLUX.mkv" \
  "/mnt/nas/Television/Foundation (2021)/Season 03/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

# Game of Thrones episodes
echo "Game of Thrones S03E01..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S03E01 Valar Dohaeris 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S03E01 Valar Dohaeris 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 03/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S03E03..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S03E03 Walk of Punishment 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S03E03 Walk of Punishment 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 03/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S03E05..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S03E05 Kissed by Fire 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S03E05 Kissed by Fire 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 03/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S03E07..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S03E07 The Bear and the Maiden Fair 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S03E07 The Bear and the Maiden Fair 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 03/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S04E05..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S04E05 First of His Name 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S04E05 First of His Name 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S04E06..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S04E06 The Laws of Gods and Men 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S04E06 The Laws of Gods and Men 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S04E07..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S04E07 Mockingbird 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S04E07 Mockingbird 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S04E08..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S04E08 The Mountain and the Viper 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S04E08 The Mountain and the Viper 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S04E09..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S04E09 The Watchers on the Wall 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S04E09 The Watchers on the Wall 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "Game of Thrones S04E10..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    Game of Thrones S04E10 The Children 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune/Game of Thrones S04E10 The Children 1080p MAX WEB-DL DDP5 1 Atmos DV HDR H 265-Kitsune.mkv" \
  "/mnt/nas/Television/Game of Thrones/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

# The Morning Show S04E04
echo "The Morning Show S04E04..."
move_with_retry \
  "$HOME/media-server/downloads/www.UIndex.org    -    The.Morning.Show.2019.S04E04.1080p.WEB.h264-ETHEL/The.Morning.Show.2019.S04E04.1080p.WEB.h264-ETHEL.mkv" \
  "/mnt/nas/Television/The Morning Show/Season 04/" || FAILED_COUNT=$((FAILED_COUNT + 1))
echo ""

echo "========================================="
echo "Fixing permissions..."
echo "========================================="

sudo chown -R 1000:1000 "/mnt/nas/Television/Evil/Season 04/" 2>/dev/null
sudo chown -R 1000:1000 "/mnt/nas/Television/Invasion (2021)/Season 03/" 2>/dev/null
sudo chown -R 1000:1000 "/mnt/nas/Television/Slow Horses/Season 05/" 2>/dev/null
sudo chown -R 1000:1000 "/mnt/nas/Television/Foundation (2021)/Season 03/" 2>/dev/null
sudo chown -R 1000:1000 "/mnt/nas/Television/Game of Thrones/Season 03/" 2>/dev/null
sudo chown -R 1000:1000 "/mnt/nas/Television/Game of Thrones/Season 04/" 2>/dev/null
sudo chown -R 1000:1000 "/mnt/nas/Television/The Morning Show/Season 04/" 2>/dev/null

echo ""
echo "Cleaning up empty download folders..."
sudo rm -rf "$HOME/media-server/downloads/www.UIndex.org"* 2>/dev/null

echo ""
echo "========================================="
echo "Migration Complete!"
echo "========================================="
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All files moved successfully!${NC}"
else
    echo -e "${YELLOW}⚠ $FAILED_COUNT file(s) failed to move${NC}"
    echo "Check the output above for details."
fi

echo ""
echo "Next steps:"
echo "1. Go to Sonarr web interface"
echo "2. System -> Tasks -> 'Refresh Series' (play button)"
echo "3. Or refresh each show individually"
echo "4. Wait 2-3 minutes for Plex to scan and add episodes"
echo ""
