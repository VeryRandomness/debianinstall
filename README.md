# Debian Server Setup — OptiPlex 3040

## Before Running setup.sh

Complete every step here before executing the script. Most of these can't be fixed mid-run without starting over.

### 1. Fresh Debian Install

- Use **manual partitioning** during install to match the disk layout in the Disk Layout section below
- Set your hostname during install (e.g. `optiplex`)
- Create a non-root user — the script uses `$SUDO_USER` to set up Syncthing and other per-user services
- Do **not** install a desktop environment yet — set up all services headlessly first, then add a DE on top

### 2. Add Your SSH Public Key

The script disables SSH password authentication. If your key is not in place first, you will be locked out the moment the script runs that step.

On your **local machine**, run:

```bash
ssh-copy-id christopher@<server-ip>
```

Or manually — on the **server**:

```bash
mkdir -p ~/.ssh
echo 'ssh-ed25519 AAAA... your-key-here' >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Verify it works before proceeding:

```bash
# From your local machine — should log in without a password prompt
ssh christopher@<server-ip>
```

Do not continue until passwordless SSH works.

### 3. Verify Internet Access

The script pulls from ~15 external sources. Check connectivity and DNS:

```bash
curl -I https://get.docker.com
curl -I https://repo.jellyfin.org
```

### 4. Check Available Disk Space

- `/` needs at least 10GB free before starting
- `/var` needs at least 20GB free (Docker images, Jellyfin DB)
- `/media` needs space for Docker volumes and media libraries

```bash
df -h
```

### 5. Note Your Non-Root Username

The script reads `$SUDO_USER` to configure per-user services. Run it with `sudo`, not as root directly:

```bash
# Correct
sudo bash setup.sh

# Wrong — $SUDO_USER will be empty and Syncthing setup will fail
su -
bash setup.sh
```

### 6. Accept the Minecraft EULA

The script sets `eula=true` automatically. By running setup.sh you are agreeing to the Minecraft End User Licence Agreement at <https://aka.ms/MinecraftEULA>. Read it first if you haven't.

### 7. Get an AMP Licence Ready

AMP (game server manager) requires a free personal licence from CubeCo before its installer will run. Register at <https://manage.cubecoders.com/Login> before you start — the AMP step will block waiting for it if you haven't.

### 8. Run the Script

Once all of the above is done:

```bash
sudo bash setup.sh
```

The script prints colour-coded status as it goes. Errors appear in red and stop execution. Warnings in yellow are non-fatal but note things needing manual follow-up after the run.

---

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
- **hostname.local** — Avahi mDNS is installed by setup.sh so the server is reachable as `<hostname>.local` (e.g. `optiplex.local`) from any device on the same network without needing a static IP

## Connecting from Windows PC

### SSH Access

Windows 10 and 11 include a built-in SSH client and SSH key tools.

**Generate a key (if you don't already have one) — run in PowerShell:**

```powershell
ssh-keygen -t ed25519 -C "windows-pc"
# Accept the default path: C:\Users\<you>\.ssh\id_ed25519
# Set a passphrase when prompted
```

**Copy the public key to the server:**

```powershell
# Replace with your server's local IP or hostname.local
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh christopher@optiplex.local "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

After this, `ssh christopher@optiplex.local` should log in without a password.

### Tailscale (remote access from anywhere)

1. Download and install Tailscale from <https://tailscale.com/download/windows>
2. Sign in with the same account used when running `tailscale up` on the server
3. The server appears in the Tailscale dashboard with a `100.x.x.x` IP
4. You can now SSH, open browser services, and use Syncthing remotely over the Tailscale IP

### Syncthing

1. Download Syncthing from <https://syncthing.net/downloads/> (use the Windows installer)
2. Open the Syncthing web UI at <http://127.0.0.1:8384> on the Windows machine
3. Copy the **Device ID** from Actions → Show ID
4. On the server, go to <http://optiplex.local:8384> → Add Remote Device → paste the Windows Device ID
5. Share the desired folder (e.g. your Obsidian vault) from the server to the Windows device
6. Accept the share in the Windows Syncthing UI

### Bitwarden / Vaultwarden

1. Install the Bitwarden browser extension (Chrome, Firefox, Edge — all supported)
2. Click the extension → Settings → **Server URL** → enter `http://optiplex.local:8222`
3. Log in with your Vaultwarden account

### RustDesk (remote desktop into the server)

1. Download RustDesk client from <https://rustdesk.com/> and install
2. Open RustDesk → Settings → Network → **ID/Relay Server**
3. Set **ID Server** and **Relay Server** both to `optiplex.local` (or the Tailscale IP for remote access)
4. Set **Key** to the contents of `/opt/rustdesk/id_ed25519.pub` on the server
5. The server's RustDesk ID appears in the main window — enter it to connect

### Accessing Services from Windows

On the local network, use `http://optiplex.local:<port>` for any service.
Over Tailscale (remote), replace `optiplex.local` with the server's Tailscale IP (`100.x.x.x`).

---

## Connecting from iPhone

### Tailscale (remote access from anywhere)

1. Install **Tailscale** from the App Store
2. Sign in with the same account used on the server
3. Enable the VPN — the server and all its services are now reachable remotely via its Tailscale IP

### Syncthing — Möbius Sync

1. Install **Möbius Sync** ($4 one-time) from the App Store
2. Create a new folder in Möbius Sync and note the device ID (Settings → Device ID)
3. On the server at <http://optiplex.local:8384>, add a remote device with that ID
4. Share the folder from the server to the iPhone and accept it in Möbius Sync
5. The folder syncs over the local network and automatically via Tailscale when remote

### Bitwarden / Vaultwarden

1. Install **Bitwarden** from the App Store
2. Tap **Log In** → **Self-hosted** → enter `http://optiplex.local:8222` (or Tailscale IP)
3. Log in with your Vaultwarden account

### RustDesk (remote desktop into the server)

1. Install **RustDesk** from the App Store
2. Tap the menu → **ID/Relay Server** → set both to `optiplex.local` or the Tailscale IP
3. Set the **Key** to the contents of `/opt/rustdesk/id_ed25519.pub`
4. Enter the server's RustDesk ID to connect

### Jellyfin

1. Install **Jellyfin** from the App Store (official client)
2. Add server: `http://optiplex.local:8096` on local network, or Tailscale IP remotely
3. Enable hardware transcoding in Jellyfin server settings (Dashboard → Playback → Intel QuickSync) so the i5-6500's Quick Sync GPU handles transcoding instead of the CPU

### Audiobookshelf

1. Install **Audiobookshelf** from the App Store (official client)
2. Server URL: `http://optiplex.local:13378`

### Dawarich (location tracking)

1. Install **Dawarich** from the App Store
2. Server URL: `http://optiplex.local:3030` (local) or Tailscale IP (remote)
3. Log in and the app will begin sending location updates to your self-hosted instance

### Accessing Services from iPhone

Safari and other iOS browsers support mDNS — `http://optiplex.local:<port>` works directly on the local network. Use the Tailscale IP when away from home.

---

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
