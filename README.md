# Home Media Server

Docker-based home media server with Plex, automated downloads, and network services.

## Stack Overview

### Media Management
- **Plex** - Media server for streaming movies, TV shows, and music
- **Sonarr** - TV show automation and management
- **Radarr** - Movie automation and management
- **Lidarr** - Music automation and management
- **Prowlarr** - Indexer manager for all *arr apps

### Download Clients
- **SABnzbd** - Usenet downloader (primary)
- **qBittorrent** - Torrent client (backup)

### Network Services
- **Pi-hole** - Network-wide ad blocking via DNS
- **WireGuard VPN** - Secure remote access (future)

## Architecture

```
Internet → Modem → Orbi Router → Network Switch
                        ↓              ↓
                   WiFi Devices   Beelink Server
                                       ↓
                                  Buffalo NAS
                                  (Media Storage)
```

## Network Configuration

| Service | Host Port | Container Port | URL |
|---------|-----------|----------------|-----|
| Plex | 32400 | 32400 | http://10.0.0.50:32400/web |
| Sonarr | 38080 | 8989 | http://10.0.0.50:38080 |
| Radarr | 38081 | 7878 | http://10.0.0.50:38081 |
| Lidarr | 38082 | 8686 | http://10.0.0.50:38082 |
| SABnzbd | 8080 | 8080 | http://10.0.0.50:8080 |
| qBittorrent | 8081 | 8081 | http://10.0.0.50:8081 |
| Prowlarr | 9696 | 9696 | http://10.0.0.50:9696 |
| Pi-hole | 8053 | 80 | http://10.0.0.50:8053/admin |
| Pi-hole DNS | 53 (tcp+udp) | 53 | — |
| Portainer | 9000 / 9443 | 9000 / 9443 | http://10.0.0.50:9000 |

**Note on ports:** Use the **host port** column for browser/external access. Use the **container port** column when one service references another from inside Docker (e.g., Prowlarr → Sonarr is `http://sonarr:8989`, not `:38080`, because container-to-container traffic stays on the internal bridge network).

**Plex networking:** Plex runs with `network_mode: host`, so it binds all its ports (32400 plus discovery/DLNA ports) directly on the host with no Docker port mapping.

## Hardware

- **Server**: Beelink EQ14 Mini PC (Intel N150, 16GB RAM, 500GB SSD)
- **Storage**: Buffalo NAS (mounted at `/mnt/nas`)
- **Network**: Netgear Orbi RBR850 + JGS524 24-port switch

## Directory Structure

```
/opt/media-server/
├── docker-compose.yml        # Media stack: Plex, *arr, downloaders, Pi-hole, Portainer
├── backup-plex.sh            # Plex metadata backup utility
├── move-episodes.sh          # One-off migration helper (hardcoded filenames)
├── web-server/               # Independent nginx landing page stack
│   ├── docker-compose.yml    # Runs separately from the media stack
│   ├── nginx.conf
│   └── www/                  # Static HTML served on port 80
├── config/                   # Per-service state (gitignored)
│   ├── plex/
│   ├── sonarr/
│   ├── radarr/
│   ├── lidarr/
│   ├── sabnzbd/
│   ├── qbittorrent/
│   ├── prowlarr/
│   ├── pihole/
│   ├── dnsmasq.d/            # Pi-hole dnsmasq config
│   └── portainer/
├── downloads/                # Shared scratch space for SAB/qBit/*arr (gitignored)
└── plex-migration/           # Created by backup-plex.sh (gitignored)
```

**Note:** The repo contains **two independent Compose stacks**. The root `docker-compose.yml` runs the media services; `web-server/docker-compose.yml` is a standalone nginx instance with no shared network or volumes. Bring them up from their own directories.

**Script path caveat:** `backup-plex.sh` and `move-episodes.sh` hardcode `$HOME/media-server/` rather than `/opt/media-server/`. Run them from a shell where `$HOME/media-server` resolves to the deployment, or edit the paths before running.

## Storage Paths

- **Downloads** (local): `/opt/media-server/downloads/`
- **TV Shows** (NAS): `/mnt/nas/Television/`
- **Movies** (NAS): `/mnt/nas/Movies/`
- **Music** (NAS): `/mnt/nas/Music/`

## Prerequisites

### Server Requirements
- Ubuntu Server 24.04 LTS
- Docker and Docker Compose
- 16GB+ RAM recommended
- 100GB+ free space for downloads

### Network Requirements
- Static IP: 10.0.0.50
- NAS mounted at `/mnt/nas` via SMB
- Port forwarding configured (for remote access)

## Installation

### 1. Install Ubuntu Server

Install Ubuntu Server 24.04 LTS on the Beelink with these settings:
- Username: your choice
- Static IP: 10.0.0.50
- Enable SSH during installation

### 2. Install Docker

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose plugin
sudo apt install docker-compose-plugin

# Log out and back in for group changes
```

### 3. Mount NAS

```bash
# Install CIFS utilities
sudo apt install cifs-utils

# Create mount point
sudo mkdir -p /mnt/nas

# Create credentials file
sudo nano /root/.smbcredentials
```

Add to credentials file:
```
username=admin
password=YOUR_PASSWORD
```

Set permissions:
```bash
sudo chmod 600 /root/.smbcredentials
```

Add to `/etc/fstab`:
```bash
sudo nano /etc/fstab
```

Add this line:
```
//10.0.0.5/share /mnt/nas cifs credentials=/root/.smbcredentials,uid=1000,gid=1000,file_mode=0644,dir_mode=0755,iocharset=utf8,vers=1.0,_netdev 0 0
```

Mount:
```bash
sudo mount -a
```

Verify:
```bash
ls -la /mnt/nas
```

### 4. Clone Repository

```bash
cd /opt
sudo git clone https://github.com/YOUR_USERNAME/media-server.git
sudo chown -R $USER:$USER media-server
cd media-server
```

### 5. Create Required Directories

```bash
mkdir -p /opt/media-server/downloads
mkdir -p /opt/media-server/config/{plex,sonarr,radarr,lidarr,sabnzbd,qbittorrent,prowlarr,pihole,dnsmasq.d,portainer}
mkdir -p /mnt/nas/{Television,Movies,Music}
```

### 6. Configure Services

Edit `docker-compose.yml` and update:
- `PUID`/`PGID` (run `id $USER` to get values; defaults are 1000/1000)
- `TZ` (timezone, default `America/New_York`)
- Pi-hole admin password: set `FTLCONF_webserver_api_password` on the `pihole` service (currently empty, which lets Pi-hole auto-generate a random password printed to `docker compose logs pihole`)

### 7. Start Services

```bash
cd /opt/media-server
docker compose up -d                    # media stack

cd /opt/media-server/web-server
docker compose up -d                    # landing page (optional)
```

### 8. Verify Services

```bash
docker compose ps
```

All services should show "Up" status.

## Initial Configuration

### Plex
1. Go to http://10.0.0.50:32400/web
2. Sign in with Plex account
3. Add libraries:
   - TV Shows: `/tv`
   - Movies: `/movies`
   - Music: `/music`

### SABnzbd
1. Go to http://10.0.0.50:8080
2. Complete setup wizard
3. Add newsgroup server
4. Set download folder: `/downloads`
5. Copy API key from Settings → General

### qBittorrent
1. Go to http://10.0.0.50:8081
2. Login: `admin` / `adminadmin`
3. Change password immediately
4. Set default save path: `/downloads`

### Prowlarr
1. Go to http://10.0.0.50:9696
2. Add indexers (NZBGeek, etc.)
3. Settings → Apps → Add Applications. Use **container hostnames and internal ports** (Prowlarr talks over the Docker bridge network, not via host ports):
   - Sonarr: `http://sonarr:8989`
   - Radarr: `http://radarr:7878`
   - Lidarr: `http://lidarr:8686`

### Sonarr/Radarr/Lidarr
1. Open each app at its host URL: Sonarr `http://10.0.0.50:38080`, Radarr `http://10.0.0.50:38081`, Lidarr `http://10.0.0.50:38082`
2. Settings → Download Clients (use container hostnames and internal ports):
   - SABnzbd: host `sabnzbd`, port `8080`
   - qBittorrent: host `qbittorrent`, port `8081`
3. Settings → Media Management:
   - Enable "Rename Episodes/Movies"
   - Set root folder (`/tv`, `/movies`, or `/music`)
4. Copy API key for Prowlarr

### Pi-hole
1. Go to http://10.0.0.50:8053/admin
2. Login with the password set via `FTLCONF_webserver_api_password` in `docker-compose.yml`. If left blank, Pi-hole generates a random password on first start — grab it with `docker compose logs pihole | grep -i password`.
3. Settings → DNS:
   - Select upstream DNS (Cloudflare, Google, etc.)
   - Enable Conditional Forwarding:
     - Local network: `10.0.0.0/24`
     - Router IP: `10.0.0.1`

### Portainer
1. Go to http://10.0.0.50:9000 (or https://10.0.0.50:9443)
2. Create an admin account on first visit (must be done within a few minutes of the container starting, otherwise Portainer locks itself and you'll need to restart it: `docker compose restart portainer`)
3. Choose "Get Started" → manage the local Docker environment

### Web Server (optional landing page)
The `web-server/` directory contains a separate, standalone nginx stack that serves static HTML on host port 80. It's independent of the media stack — no shared network or volumes.

```bash
cd /opt/media-server/web-server
docker compose up -d
```

Edit files under `web-server/www/` to change what's served.

### Router Configuration
1. Login to Orbi router
2. Set DHCP DNS server to: `10.0.0.50`
3. This enables network-wide ad blocking via Pi-hole

## Migrating from Existing Server

### Prepare Plex Backup on Old Server

**Note:** Plex backups are stored separately from the Git repository due to their large size (typically 2-15GB).

```bash
cd ~/media-server
./backup-plex.sh

# This creates ~/media-server/plex-migration/
# Move it outside the git repo for transfer
mv ~/media-server/plex-migration ~/media-server-backup/

# Commit configuration changes
git add docker-compose.yml
git commit -m "Configuration updates"
git push
```

### Transfer Plex Backup to New Server

**Option 1: Direct Network Transfer (Recommended)**

Once the Beelink is set up with Ubuntu and network connectivity:

```bash
# From old Fedora server
scp -r ~/media-server-backup/plex-migration user@10.0.0.50:/tmp/

# Or use rsync for reliability
rsync -avz --progress ~/media-server-backup/plex-migration/ user@10.0.0.50:/tmp/plex-migration/
```

**Option 2: Via NAS (If Direct Transfer Unavailable)**

```bash
# On old server - copy to NAS
cp -r ~/media-server-backup/plex-migration /mnt/nas/plex-backup-temp/

# On new server - copy from NAS
cp -r /mnt/nas/plex-backup-temp /opt/media-server/plex-migration/
```

**Option 3: USB Drive**

```bash
# Copy to USB drive
cp -r ~/media-server-backup/plex-migration /media/usb-drive/

# Physically move USB to new server
# Copy from USB
cp -r /media/usb-drive/plex-migration /opt/media-server/
```

### Restore on New Server

```bash
cd /opt/media-server

# Make sure you have the plex-migration folder
ls -la plex-migration/

# Follow instructions in plex-migration/RESTORE_INSTRUCTIONS.md

# Quick restore:
docker compose up -d plex
docker compose stop plex

cd plex-migration/backup
PLEX_DATA="/opt/media-server/config/plex/Library/Application Support/Plex Media Server"

cp Preferences.xml "$PLEX_DATA/"
tar -xzf plugin-support.tar.gz -C "$PLEX_DATA/Plug-in Support/"
tar -xzf media.tar.gz -C "$PLEX_DATA/"
tar -xzf metadata.tar.gz -C "$PLEX_DATA/"

sudo chown -R 1000:1000 "$PLEX_DATA"
docker compose up -d plex
```

Your library, watch history, and metadata will be fully restored!

## Maintenance

### Update Containers

```bash
cd /opt/media-server
docker compose pull
docker compose up -d
```

### View Logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs plex
docker compose logs sonarr

# Follow logs in real-time
docker compose logs -f plex
```

### Restart Services

```bash
# All services
docker compose restart

# Specific service
docker compose restart plex
```

### Stop Services

```bash
# All services
docker compose down

# Keep data, remove containers only
docker compose down --remove-orphans
```

### Backup Configuration

```bash
# Backup all configs
tar -czf media-server-backup-$(date +%Y%m%d).tar.gz config/

# Backup Plex specifically
./backup-plex.sh
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker compose logs

# Check if ports are in use
sudo ss -tulpn | grep -E ':(32400|38080|38081|38082|8080|8081|9696|8053|53|9000|9443)'

# Restart Docker
sudo systemctl restart docker
docker compose up -d
```

### NAS Not Mounted

```bash
# Check mount
df -h | grep nas

# Remount
sudo umount /mnt/nas
sudo mount -a

# Check fstab
cat /etc/fstab | grep nas
```

### Downloads Not Importing

```bash
# Check permissions
ls -la /opt/media-server/downloads
ls -la /mnt/nas/Television

# Fix permissions
sudo chown -R 1000:1000 /opt/media-server/downloads
sudo chown -R 1000:1000 /mnt/nas/Television
sudo chown -R 1000:1000 /mnt/nas/Movies
sudo chown -R 1000:1000 /mnt/nas/Music

# Trigger import manually
# In Sonarr/Radarr: System → Tasks → Refresh Monitored Downloads
```

### Pi-hole Not Working

```bash
# Check if running
docker compose ps pihole

# Check port 53
sudo ss -tulpn | grep :53

# Restart Pi-hole
docker compose restart pihole

# Check logs
docker compose logs pihole
```

### Remote Access Not Working

**For Plex:**
1. Check if behind CGNAT (contact ISP)
2. Enable port forwarding: 32400 → 10.0.0.50
3. Plex → Settings → Remote Access → Enable

**For VPN (WireGuard):**
1. Port forward 51820 → 10.0.0.50
2. Configure WireGuard (see WireGuard docs)

## Utility Scripts

> Both scripts hardcode `$HOME/media-server/` as the working directory. If the repo is deployed at `/opt/media-server/`, run from a user whose `$HOME/media-server` symlinks/resolves there, or edit the path constants at the top of each script.

### backup-plex.sh
Stops Plex, tars `Preferences.xml`, `Plug-in Support/Databases/`, `Media/`, and `Metadata/` into `plex-migration/backup/`, writes `RESTORE_INSTRUCTIONS.md`, then restarts Plex. Lets you move libraries to a new server without a re-scan.

```bash
./backup-plex.sh
```

### move-episodes.sh
One-off migration helper with **hardcoded episode filenames** — not a general utility. Reads files out of `~/media-server/downloads/` and moves them to the correct `/mnt/nas/Television/...` season folders with retry logic, then fixes ownership to `1000:1000`. Read it before running; edit the filename list to match what you actually need to move.

```bash
./move-episodes.sh
```

## Performance Optimization

### Hardware Transcoding (Plex)
Intel N150 supports QuickSync hardware transcoding:
1. Plex → Settings → Transcoder
2. Enable "Use hardware acceleration when available"
3. Hardware transcoding device: Intel QuickSync

### Download Speed
- Use Ethernet connection (not WiFi)
- SABnzbd: Set max connections per server
- Monitor with: `docker stats`

### Storage Performance
- Keep downloads on local SSD (fast)
- Final media on NAS (large capacity)
- Downloads auto-clean after import

## Security Best Practices

1. **Change default passwords** (qBittorrent, Pi-hole)
2. **Use strong Plex password**
3. **Keep Docker updated**: `docker compose pull` regularly
4. **Use VPN for remote access** instead of exposing services
5. **Enable 2FA on Plex account**
6. **Restrict Pi-hole admin interface** to local network only

## Future Enhancements

- [ ] WireGuard VPN for secure remote access
- [ ] Automated backups to cloud storage
- [ ] VLAN segmentation for IoT devices
- [ ] Monitoring with Grafana/Prometheus
- [ ] Automated media requests (Overseerr/Ombi)
- [ ] pfSense for advanced firewall/routing

## Support & Resources

- **Plex**: https://support.plex.tv
- **Sonarr**: https://wiki.servarr.com/sonarr
- **Radarr**: https://wiki.servarr.com/radarr
- **Pi-hole**: https://docs.pi-hole.net
- **Docker**: https://docs.docker.com

## License

Personal use only.

## Author

mbergman
---

**Last Updated**: June 2026
