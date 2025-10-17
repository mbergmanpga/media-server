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

| Service | Port | URL |
|---------|------|-----|
| Plex | 32400 | http://10.0.0.50:32400/web |
| Sonarr | 8989 | http://10.0.0.50:8989 |
| Radarr | 7878 | http://10.0.0.50:7878 |
| Lidarr | 8686 | http://10.0.0.50:8686 |
| SABnzbd | 8080 | http://10.0.0.50:8080 |
| qBittorrent | 8081 | http://10.0.0.50:8081 |
| Prowlarr | 9696 | http://10.0.0.50:9696 |
| Pi-hole | 8053 | http://10.0.0.50:8053/admin |

## Hardware

- **Server**: Beelink EQ14 Mini PC (Intel N150, 16GB RAM, 500GB SSD)
- **Storage**: Buffalo NAS (mounted at `/mnt/nas`)
- **Network**: Netgear Orbi RBR850 + JGS524 24-port switch

## Directory Structure

```
/opt/media-server/
├── docker-compose.yml        # Service definitions
├── .gitignore               # Git ignore rules
├── config/                  # Application configs (not in git)
│   ├── plex/
│   ├── sonarr/
│   ├── radarr/
│   ├── lidarr/
│   ├── sabnzbd/
│   ├── qbittorrent/
│   ├── prowlarr/
│   └── pihole/
├── downloads/               # Temporary downloads (not in git)
├── plex-migration/          # Plex backup for migration
└── scripts/                 # Utility scripts
    ├── backup-plex.sh
    └── import-stuck-files.sh
```

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
mkdir -p /opt/media-server/config/{plex,sonarr,radarr,lidarr,sabnzbd,qbittorrent,prowlarr,pihole,dnsmasq.d}
mkdir -p /mnt/nas/{Television,Movies,Music}
```

### 6. Configure Services

Edit `docker-compose.yml` and update:
- PUID/PGID (run `id $USER` to get values)
- Timezone (TZ)
- Pi-hole web password (WEBPASSWORD)

### 7. Start Services

```bash
cd /opt/media-server
docker compose up -d
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
3. Settings → Apps → Add Applications:
   - Add Sonarr (http://sonarr:8989)
   - Add Radarr (http://radarr:7878)
   - Add Lidarr (http://lidarr:8686)

### Sonarr/Radarr/Lidarr
1. Go to each app's web interface
2. Settings → Download Clients:
   - Add SABnzbd (host: `sabnzbd`, port: 8080)
   - Add qBittorrent (host: `qbittorrent`, port: 8081)
3. Settings → Media Management:
   - Enable "Rename Episodes/Movies"
   - Set root folder (`/tv`, `/movies`, or `/music`)
4. Copy API key for Prowlarr

### Pi-hole
1. Go to http://10.0.0.50:8053/admin
2. Login with password from docker-compose
3. Settings → DNS:
   - Select upstream DNS (Cloudflare, Google, etc.)
   - Enable Conditional Forwarding:
     - Local network: `10.0.0.0/24`
     - Router IP: `10.0.0.1`

### Router Configuration
1. Login to Orbi router
2. Set DHCP DNS server to: `10.0.0.50`
3. This enables network-wide ad blocking via Pi-hole

## Migrating from Existing Server

### On Old Server

```bash
cd ~/media-server
./backup-plex.sh
git add plex-migration/
git commit -m "Plex backup for migration"
git push
```

### On New Server

```bash
cd /opt/media-server
git pull

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
sudo ss -tulpn | grep -E ':(32400|8989|7878|8686|8080|8081|9696|53)'

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

### backup-plex.sh
Backs up Plex metadata for migration without re-scanning library.

```bash
./backup-plex.sh
```

### import-stuck-files.sh
Triggers all *arr apps to check for completed downloads and import them.

```bash
./import-stuck-files.sh
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

Your Name

---

**Last Updated**: October 2025
