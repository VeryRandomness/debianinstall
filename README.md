# Debian Server Setup — OptiPlex 3040

## Hardware

|Component|Spec                                      |
|---------|------------------------------------------|
|CPU      |Intel Core i5-6500 (4 cores) @ 3GHz       |
|RAM      |16GB                                      |
|GPU      |Intel HD Graphics 530 (Quick Sync capable)|
|SSD      |250GB                                     |
|HDD      |500GB                                     |

## Planned Services

|Service            |Type                      |Notes                                                                            |
|-------------------|--------------------------|---------------------------------------------------------------------------------|
|Jellyfin           |Media server              |Native — official Debian repo, Quick Sync hardware transcoding                   |
|Streambert         |Desktop client app        |Native — Electron app, runs locally on the desktop only                          |
|Audiobookshelf     |Audiobook server          |Docker                                                                           |
|Stirling-PDF       |PDF tools                 |Docker                                                                           |
|HomeBox            |Inventory manager         |Docker                                                                           |
|Syncthing          |File sync (Obsidian vault)|Native — runs as a per-user daemon                                               |
|Minecraft (vanilla)|Game server               |Native — requires Java                                                           |
|Terraria           |Game server               |Native — Linux binary via SteamCMD                                               |
|playit.gg          |Tunnel agent              |Native — Linux binary, exposes game servers publicly                             |
|Tailscale          |VPN mesh                  |Native — official Debian repo                                                    |
|RustDesk           |Remote desktop            |Native — self-hosted hbbs + hbbr                                                 |
|Caddy              |Reverse proxy             |Native — official Debian repo                                                    |
|Uptime Kuma        |Monitoring                |Docker                                                                           |
|Brave              |Browser                   |Native — official apt repo                                                       |
|Paperless-ngx      |Document manager          |Docker                                                                           |
|Vaultwarden        |Password manager          |Docker — self-hosted Bitwarden                                                   |
|Homepage           |Dashboard                 |Docker — links to all services with live status                                  |
|Netdata            |System metrics            |Docker — real-time CPU, RAM, disk, network graphs                                |
|Linkding           |Bookmark manager          |Docker                                                                           |
|AMP                |Game server manager       |Native — web UI for Minecraft/Terraria, requires free licence from cubecoders.com|
|Dawarich           |Location history          |Docker — self-hosted Google Timeline replacement                                 |

## Disk Layout

### SSD (250GB) — OS + App Data

Format all partitions as **ext4** except EFI (use **FAT32**).

|Mount      |Size |Format|Purpose                                                                  |
|-----------|-----|------|-------------------------------------------------------------------------|
|`/boot/efi`|512MB|FAT32 |EFI boot partition                                                       |
|`/`        |50GB |ext4  |OS + installed applications                                              |
|`/var`     |150GB|ext4  |App data — Jellyfin metadata DB, ABS cache, logs (SSD speed matters here)|
|`swap`     |8GB  |swap  |Swap space                                                               |
|*(buffer)* |~35GB|—     |Leave unallocated, keeps SSD healthy                                     |

### HDD (500GB) — Media + User Data

Format all as **ext4**.

|Mount   |Size |Format|Purpose                                                 |
|--------|-----|------|--------------------------------------------------------|
|`/home` |200GB|ext4  |User files, dotfiles, Syncthing/Obsidian vault          |
|`/media`|300GB|ext4  |Jellyfin library, audiobooks — point all media apps here|

## Key Notes

- **Media libraries** for Jellyfin and Audiobookshelf must point to `/media`, not `/`
- **Jellyfin Quick Sync** — enable hardware transcoding in Jellyfin settings. Without it, software transcoding will bottleneck under multiple streams
- **Minecraft + Terraria** running simultaneously use ~3–4GB RAM combined — fine on 16GB
- **Use manual partitioning** during Debian install to set this layout up exactly
- **Set up services headlessly first** via SSH, then layer the desktop environment on top
- **Docker group** — after setup.sh runs, log out and back in before running docker commands without sudo

## Docker Services

All Docker services store data under `/media/<service>/` so they survive container updates and rebuilds.
Common commands (replace `<service>` with the folder name):

```bash
# Restart a service
docker compose -f /opt/<service>/docker-compose.yml restart
# Pull latest image and redeploy
docker compose -f /opt/<service>/docker-compose.yml pull
docker compose -f /opt/<service>/docker-compose.yml up -d
# View logs
docker compose -f /opt/<service>/docker-compose.yml logs -f
# Stop
docker compose -f /opt/<service>/docker-compose.yml down
```

Service compose file locations:

|Service       |Path                                    |
|--------------|----------------------------------------|
|Audiobookshelf|`/opt/audiobookshelf/docker-compose.yml`|
|Stirling-PDF  |`/opt/stirling-pdf/docker-compose.yml`  |
|HomeBox       |`/opt/homebox/docker-compose.yml`       |
|Uptime Kuma   |`/opt/uptime-kuma/docker-compose.yml`   |
|Paperless-ngx |`/opt/paperless/docker-compose.yml`     |
|Vaultwarden   |`/opt/vaultwarden/docker-compose.yml`   |
|Homepage      |`/opt/homepage/docker-compose.yml`      |
|Netdata       |`/opt/netdata/docker-compose.yml`       |
|Linkding      |`/opt/linkding/docker-compose.yml`      |
|Dawarich      |`/opt/dawarich/docker-compose.yml`      |

**AMP is not Docker-based.** After setup.sh runs, get a free personal licence at <https://manage.cubecoders.com/Login> then run:

```bash
sudo /opt/install-amp.sh
# When prompted, set the port to 8081 (8080 is taken by Stirling-PDF)
```

## Migration (from Arch)

Back up configs and data, not binaries. Reinstall apps fresh on Debian.

```bash
sudo tar -czvf /mnt/usb/server-backup.tar.gz \
  /var/lib/jellyfin \
  /etc/jellyfin \
  /etc/systemd/system/*.service \
  /home/christopher
```

Also export: `/etc/fstab`, `/etc/hosts`, `crontab -l`
Python venvs will need to be rebuilt — different glibc/Python version on Debian. Keep them for reference, reinstall with `pip install -r requirements.txt`.

## Paperless-ngx (Docker)

Runs via Docker Compose. All data lives under `/media/paperless/`.

```bash
# Create admin user (first time only)
docker compose -f /opt/paperless/docker-compose.yml exec webserver createsuperuser
```

Drop documents into `/media/paperless/consume/` and Paperless will automatically OCR and import them.

## RustDesk Setup

```bash
cat /opt/rustdesk/id_ed25519.pub
```

In the RustDesk client on every device: Settings → Network → enter your server IP and that public key. This locks your server so only your devices can connect.
RustDesk runs two services:

- **hbbs** — ID/rendezvous server (ports 21115, 21116 TCP+UDP, 21118)
- **hbbr** — relay server (ports 21117, 21119)

## Security

- **ufw** firewall enabled — only required ports are open
- **fail2ban** — SSH brute force protection, 5 attempts = 1 hour ban
- **SSH hardening** — password auth disabled, root login disabled. Ensure your key is in `~/.ssh/authorized_keys` before running setup.sh or you will lock yourself out
- **unattended-upgrades** — security patches applied automatically
- **Timeshift** — configure snapshots manually after install: `sudo timeshift-gtk`

## Uptime Kuma Monitor List

Go to <http://localhost:3001> and manually add these after setup:

|Name          |Type    |URL / Host:Port         |
|--------------|--------|------------------------|
|Jellyfin      |HTTP    |<http://localhost:8096> |
|Audiobookshelf|HTTP    |<http://localhost:13378>|
|Stirling-PDF  |HTTP    |<http://localhost:8080> |
|HomeBox       |HTTP    |<http://localhost:7745> |
|Syncthing     |HTTP    |<http://localhost:8384> |
|Paperless-ngx |HTTP    |<http://localhost:8000> |
|Minecraft     |TCP Port|localhost:25565         |
|Terraria      |TCP Port|localhost:7777          |
|RustDesk hbbs |TCP Port|localhost:21116         |
|RustDesk hbbr |TCP Port|localhost:21117         |
|Vaultwarden   |HTTP    |<http://localhost:8222> |
|Homepage      |HTTP    |<http://localhost:3000> |
|Netdata       |HTTP    |<http://localhost:19999>|
|Linkding      |HTTP    |<http://localhost:9090> |
|AMP           |HTTP    |<http://localhost:8081> |
|Dawarich      |HTTP    |<http://localhost:3030> |

## Email — Outbound Setup (msmtp)

Emails route through your Gmail account via msmtp. No mail server needed.
**Step 1 — Generate a Gmail App Password**

1. Go to <https://myaccount.google.com/apppasswords>
1. Name it "server" and generate
1. Copy the 16-character password

**Step 2 — Edit the config**

```bash
sudo nano /etc/msmtprc
```

Replace `YOUR_EMAIL@gmail.com` and `YOUR_APP_PASSWORD` with real values.

**Step 3 — Set the recipient in the status script**

```bash
sudo nano /opt/status-email.sh
# Change the TO= line at the top
```

**Test it**

```bash
sudo /opt/status-email.sh
echo "Test from server" | mail -s "Test" your@email.com
```

Logs go to `/var/log/msmtp.log` if something doesn't work.

## Daily Status Email

Runs at 8 AM via cron. Checks and reports:

- All systemd services — Jellyfin, Tailscale, Caddy, RustDesk, fail2ban, game servers
- All Docker containers — ABS, Stirling-PDF, HomeBox, Uptime Kuma, Paperless
- Disk usage on all partitions — warns if any hit 85%
- Memory usage — warns if above 90%
- Last backup log entry
- Failed SSH login attempts in the last 24 hours

Warnings appear at the top of the email. If everything is fine it just says ✔ All systems normal.

## iOS Scanning Pipeline (Paperless-ngx)

Scan a document on your iPhone → it lands in Paperless automatically with no manual steps.
**What you need:**

- **Möbius Sync** (iOS, $4 one-time) — Syncthing client for iPhone
- Any scanner app — the built-in iOS document scanner in the Files app works fine, or use Scanner Pro

**Setup:**

1. In Möbius Sync, create a new folder and note its local path on the phone
1. In Syncthing on the server, add a new shared folder pointing to `/media/paperless/consume/`
1. Share that folder with your iPhone's Möbius Sync device ID
1. Accept the share in Möbius Sync

Now scan a document → save it to the Möbius Sync folder → within minutes Paperless OCRs it, tags it, and archives it. The original file is deleted from the consume folder automatically.

## Vaultwarden First-Time Setup

1. Go to <http://localhost:8222> and create your account
1. Immediately disable open signups so no one else can register:
- Visit <http://localhost:8222/admin>
- The admin token is in `/media/vaultwarden/data/config.json`
- Under General Settings → disable Allow new signups
1. Install the Bitwarden browser extension or mobile app and point the server URL to your server IP:8222

## Backups

Rsync cron runs daily at 3 AM, logs to `/var/log/backup.log`. Backs up:

- `/var/lib/jellyfin` → `/media/backups/jellyfin`
- `/media/audiobookshelf` → `/media/backups/audiobookshelf`
- `/media/homebox` → `/media/backups/homebox`
- `/media/paperless` → `/media/backups/paperless`
- `/media/uptime-kuma` → `/media/backups/uptime-kuma`
- `/media/vaultwarden` → `/media/backups/vaultwarden`
- `/media/linkding` → `/media/backups/linkding`
- `/media/homepage` → `/media/backups/homepage`
- `/media/dawarich` → `/media/backups/dawarich`
- `/home` → `/media/backups/home`

## Dawarich Setup

Self-hosted Google Timeline replacement. Runs four containers: app, sidekiq (background jobs), Postgres, Redis.

**Default login:** `demo@dawarich.app` / `password` — change immediately at <http://localhost:3030>

**iOS tracking:** Dawarich has a native iOS app on the App Store. Point it at your server IP:3030. Alternatively use OwnTracks or Overland if you prefer open-source trackers.

**Import existing Google Timeline data:**

1. Go to Google Takeout → export Location History (JSON format)
1. In Dawarich → Settings → Imports → upload the zip
1. Dawarich will process it in the background via Sidekiq
