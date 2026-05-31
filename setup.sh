#!/bin/bash
# ============================================================
# Debian Server Setup — OptiPlex 3040
# Run: sudo bash setup.sh
# ============================================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step()  { echo -e "\n${CYAN}==>${NC} ${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fatal() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Root check ────────────────────────────────────────────────
[ "$EUID" -ne 0 ] && fatal "Run as root: sudo bash setup.sh"
REAL_USER="${SUDO_USER:-$USER}"

# ── System update + base deps ─────────────────────────────────
step "Updating system and installing base dependencies..."
apt update && apt upgrade -y
apt install -y \
    curl wget git gnupg lsb-release \
    apt-transport-https ca-certificates \
    software-properties-common \
    lib32gcc-s1 \
    python3 \
    rsync \
    unzip

# ── Jellyfin ──────────────────────────────────────────────────
step "Installing Jellyfin..."
curl -fsSL https://repo.jellyfin.org/install-debuntu.sh | bash

# Quick Sync support
step "Configuring Jellyfin hardware transcoding (Quick Sync)..."
apt install -y i965-va-driver vainfo
usermod -aG video,render jellyfin

# ── Docker ────────────────────────────────────────────────────
step "Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker "$REAL_USER"
systemctl enable --now docker

# ── Audiobookshelf (Docker) ───────────────────────────────────
step "Installing Audiobookshelf..."
mkdir -p /opt/audiobookshelf
mkdir -p /media/audiobooks /media/podcasts /media/audiobookshelf/{config,metadata}

cat > /opt/audiobookshelf/docker-compose.yml <<EOF
version: "3.8"
services:
  audiobookshelf:
    image: ghcr.io/advplyr/audiobookshelf:latest
    container_name: audiobookshelf
    ports:
      - "13378:80"
    volumes:
      - /media/audiobooks:/audiobooks
      - /media/podcasts:/podcasts
      - /media/audiobookshelf/config:/config
      - /media/audiobookshelf/metadata:/metadata
    restart: unless-stopped
EOF

cd /opt/audiobookshelf && docker compose pull && docker compose up -d

# ── Stirling-PDF (Docker) ─────────────────────────────────────
step "Installing Stirling-PDF..."
mkdir -p /opt/stirling-pdf
mkdir -p /media/stirling-pdf/{trainingData,extraConfigs,customFiles,logs}

cat > /opt/stirling-pdf/docker-compose.yml <<EOF
version: "3.8"
services:
  stirling-pdf:
    image: stirlingtools/stirling-pdf:latest
    container_name: stirling-pdf
    ports:
      - "8080:8080"
    volumes:
      - /media/stirling-pdf/trainingData:/usr/share/tessdata
      - /media/stirling-pdf/extraConfigs:/configs
      - /media/stirling-pdf/customFiles:/customFiles
      - /media/stirling-pdf/logs:/logs
    environment:
      - DOCKER_ENABLE_SECURITY=false
    restart: unless-stopped
EOF

cd /opt/stirling-pdf && docker compose pull && docker compose up -d

# ── HomeBox (Docker) ──────────────────────────────────────────
step "Installing HomeBox..."
mkdir -p /opt/homebox /media/homebox/data

cat > /opt/homebox/docker-compose.yml <<EOF
version: "3.8"
services:
  homebox:
    image: ghcr.io/sysadminsmedia/homebox:latest
    container_name: homebox
    ports:
      - "7745:7745"
    volumes:
      - /media/homebox/data:/data
    environment:
      - HBOX_LOG_LEVEL=info
      - HBOX_LOG_FORMAT=text
    restart: unless-stopped
EOF

cd /opt/homebox && docker compose pull && docker compose up -d

# ── Syncthing ─────────────────────────────────────────────────
step "Installing Syncthing..."
curl -fsSL https://syncthing.net/release-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] \
https://apt.syncthing.net/ syncthing stable" \
    > /etc/apt/sources.list.d/syncthing.list
apt update
apt install -y syncthing

# ── Tailscale ─────────────────────────────────────────────────
step "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

# ── playit.gg ─────────────────────────────────────────────────
step "Installing playit.gg..."
curl -SsL https://playit-cloud.github.io/ppa/key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/playit-cloud.gpg
echo "deb [signed-by=/usr/share/keyrings/playit-cloud.gpg] \
https://playit-cloud.github.io/ppa/v0 main" \
    > /etc/apt/sources.list.d/playit-cloud.list
apt update
apt install -y playit

# ── Minecraft (vanilla) ───────────────────────────────────────
step "Installing Minecraft server..."
useradd -r -m -d /opt/minecraft minecraft 2>/dev/null || true
mkdir -p /opt/minecraft

MANIFEST=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
LATEST_MC=$(echo "$MANIFEST" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['latest']['release'])")
VERSION_URL=$(echo "$MANIFEST" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); v=d['latest']['release']; \
    print(next(x['url'] for x in d['versions'] if x['id']==v))")
SERVER_URL=$(curl -s "$VERSION_URL" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d['downloads']['server']['url'])")

wget -q -O /opt/minecraft/server.jar "$SERVER_URL"
echo "eula=true" > /opt/minecraft/eula.txt
chown -R minecraft:minecraft /opt/minecraft

cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=minecraft
# Adjust -Xmx to control max RAM. 2G is a safe default on 16GB.
ExecStart=/usr/bin/java -Xmx2G -Xms1G -jar /opt/minecraft/server.jar nogui
WorkingDirectory=/opt/minecraft
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ── Terraria (via SteamCMD) ───────────────────────────────────
step "Installing SteamCMD and Terraria server..."
mkdir -p /opt/steamcmd /opt/terraria
cd /opt/steamcmd
wget -q https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzf steamcmd_linux.tar.gz
./steamcmd.sh \
    +force_install_dir /opt/terraria \
    +login anonymous \
    +app_update 105600 validate \
    +quit

cat > /etc/systemd/system/terraria.service <<EOF
[Unit]
Description=Terraria Server
After=network.target

[Service]
Type=simple
# Edit serverconfig.txt in /opt/terraria before starting
ExecStart=/opt/terraria/TerrariaServer -config /opt/terraria/serverconfig.txt
WorkingDirectory=/opt/terraria
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ── Streambert (desktop app) ──────────────────────────────────
step "Installing Streambert..."
STREAMBERT_VER=$(curl -s https://api.github.com/repos/truelockmc/streambert/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
wget -q -O /tmp/streambert.deb \
    "https://github.com/truelockmc/streambert/releases/download/${STREAMBERT_VER}/Streambert_${STREAMBERT_VER}_amd64.deb"
dpkg -i /tmp/streambert.deb || apt-get install -f -y

# ── RustDesk Server ───────────────────────────────────────────
step "Installing RustDesk server..."
mkdir -p /opt/rustdesk
RUSTDESK_VER=$(curl -s https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
wget -q -O /tmp/rustdesk-server.zip \
    "https://github.com/rustdesk/rustdesk-server/releases/download/${RUSTDESK_VER}/rustdesk-server-linux-amd64.zip"
apt install -y unzip
unzip -q /tmp/rustdesk-server.zip -d /opt/rustdesk
chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr

# hbbs = ID/rendezvous server  (ports 21115, 21116 TCP+UDP, 21118)
cat > /etc/systemd/system/rustdesk-hbbs.service <<EOF
[Unit]
Description=RustDesk ID/Rendezvous Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/rustdesk/hbbs
WorkingDirectory=/opt/rustdesk
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# hbbr = relay server  (ports 21117, 21119)
cat > /etc/systemd/system/rustdesk-hbbr.service <<EOF
[Unit]
Description=RustDesk Relay Server
After=network.target

[Service]
Type=simple
ExecStart=/opt/rustdesk/hbbr
WorkingDirectory=/opt/rustdesk
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ── Paperless-ngx (Docker) ────────────────────────────────────
step "Installing Paperless-ngx via Docker..."
mkdir -p /opt/paperless
mkdir -p /media/paperless/{consume,data,media,export}

cat > /opt/paperless/docker-compose.yml <<EOF
version: "3.4"
services:
  broker:
    image: docker.io/library/redis:7
    restart: unless-stopped
    volumes:
      - /media/paperless/redisdata:/data

  db:
    image: docker.io/library/postgres:16
    restart: unless-stopped
    volumes:
      - /media/paperless/pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: paperless
      POSTGRES_USER: paperless
      POSTGRES_PASSWORD: paperless

  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    restart: unless-stopped
    depends_on:
      - db
      - broker
    ports:
      - "8000:8000"
    volumes:
      - /media/paperless/data:/usr/src/paperless/data
      - /media/paperless/media:/usr/src/paperless/media
      - /media/paperless/export:/usr/src/paperless/export
      - /media/paperless/consume:/usr/src/paperless/consume
    environment:
      PAPERLESS_REDIS: redis://broker:6379
      PAPERLESS_DBHOST: db
      PAPERLESS_DBNAME: paperless
      PAPERLESS_DBUSER: paperless
      PAPERLESS_DBPASS: paperless
      PAPERLESS_URL: http://localhost:8000
      PAPERLESS_SECRET_KEY: $(openssl rand -hex 32)
      PAPERLESS_TIME_ZONE: America/Chicago
      PAPERLESS_OCR_LANGUAGE: eng
      USERMAP_UID: 1000
      USERMAP_GID: 1000
EOF

cd /opt/paperless
docker compose pull
docker compose up -d

warn "Create your Paperless admin user:"
warn "  docker compose -f /opt/paperless/docker-compose.yml exec webserver createsuperuser"

# ── Brave Browser ─────────────────────────────────────────────
step "Installing Brave browser..."
curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    | gpg --dearmor -o /usr/share/keyrings/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] \
https://brave-browser-apt-release.s3.brave.com/ stable main" \
    | tee /etc/apt/sources.list.d/brave-browser-release.list
apt update
apt install -y brave-browser

# ── Caddy (reverse proxy) ─────────────────────────────────────
step "Installing Caddy..."
apt install -y debian-keyring debian-archive-keyring
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# Write a starter Caddyfile — edit hostnames as needed
cat > /etc/caddy/Caddyfile <<EOF
# Replace these with your actual local hostnames or Tailscale IPs
# Run 'caddy reload' after editing

jellyfin.local {
    reverse_proxy localhost:8096
}

abs.local {
    reverse_proxy localhost:13378
}

pdf.local {
    reverse_proxy localhost:8080
}

homebox.local {
    reverse_proxy localhost:7745
}

status.local {
    reverse_proxy localhost:3001
}

rustdesk.local {
    reverse_proxy localhost:21114
}

vault.local {
    reverse_proxy localhost:8222
}

home.local {
    reverse_proxy localhost:3000
}

metrics.local {
    reverse_proxy localhost:19999
}

links.local {
    reverse_proxy localhost:9090
}

amp.local {
    reverse_proxy localhost:8081
}

dawarich.local {
    reverse_proxy localhost:3030
}
EOF

# ── Uptime Kuma (Docker) ──────────────────────────────────────
step "Installing Uptime Kuma..."
mkdir -p /opt/uptime-kuma /media/uptime-kuma/data

cat > /opt/uptime-kuma/docker-compose.yml <<EOF
version: "3.8"
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    ports:
      - "3001:3001"
    volumes:
      - /media/uptime-kuma/data:/app/data
    restart: unless-stopped
EOF

cd /opt/uptime-kuma && docker compose pull && docker compose up -d

# ── Vaultwarden (Docker) ──────────────────────────────────────
step "Installing Vaultwarden..."
mkdir -p /opt/vaultwarden /media/vaultwarden/data

cat > /opt/vaultwarden/docker-compose.yml <<EOF
version: "3.8"
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    ports:
      - "8222:80"
    volumes:
      - /media/vaultwarden/data:/data
    environment:
      - WEBSOCKET_ENABLED=true
      - SIGNUPS_ALLOWED=true
    restart: unless-stopped
EOF

cd /opt/vaultwarden && docker compose pull && docker compose up -d
warn "After setup, disable open signups in Vaultwarden admin panel: http://localhost:8222/admin"

# ── Homepage (Docker) ─────────────────────────────────────────
step "Installing Homepage dashboard..."
mkdir -p /opt/homepage
mkdir -p /media/homepage/{config,icons,images}

cat > /opt/homepage/docker-compose.yml <<EOF
version: "3.8"
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    ports:
      - "3000:3000"
    volumes:
      - /media/homepage/config:/app/config
      - /media/homepage/icons:/app/public/icons
      - /media/homepage/images:/app/public/images
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
EOF

# Write a starter services config for Homepage
mkdir -p /media/homepage/config
cat > /media/homepage/config/services.yaml <<'EOF'
- Media:
    - Jellyfin:
        href: http://localhost:8096
        description: Media server
        icon: jellyfin.png
    - Audiobookshelf:
        href: http://localhost:13378
        description: Audiobooks & podcasts
        icon: audiobookshelf.png

- Documents:
    - Paperless-ngx:
        href: http://localhost:8000
        description: Document archive
        icon: paperless.png
    - Stirling-PDF:
        href: http://localhost:8080
        description: PDF tools
        icon: stirling-pdf.png

- Productivity:
    - Vaultwarden:
        href: http://localhost:8222
        description: Password manager
        icon: vaultwarden.png
    - HomeBox:
        href: http://localhost:7745
        description: Inventory
        icon: homebox.png
    - Linkding:
        href: http://localhost:9090
        description: Bookmarks
        icon: linkding.png
    - Dawarich:
        href: http://localhost:3030
        description: Location history
        icon: dawarich.png

- Infrastructure:
    - Syncthing:
        href: http://localhost:8384
        description: File sync
        icon: syncthing.png
    - Uptime Kuma:
        href: http://localhost:3001
        description: Monitoring
        icon: uptime-kuma.png
    - Netdata:
        href: http://localhost:19999
        description: System metrics
        icon: netdata.png
    - AMP:
        href: http://localhost:8081
        description: Game server management
        icon: amp.png
EOF

cat > /media/homepage/config/settings.yaml <<'EOF'
title: Home Server
theme: dark
color: slate
EOF

cd /opt/homepage && docker compose pull && docker compose up -d

# ── Netdata (Docker) ──────────────────────────────────────────
step "Installing Netdata..."
mkdir -p /opt/netdata

cat > /opt/netdata/docker-compose.yml <<EOF
version: "3.8"
services:
  netdata:
    image: netdata/netdata:latest
    container_name: netdata
    ports:
      - "19999:19999"
    cap_add:
      - SYS_PTRACE
    security_opt:
      - apparmor:unconfined
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
EOF

cd /opt/netdata && docker compose pull && docker compose up -d

# ── Linkding (Docker) ─────────────────────────────────────────
step "Installing Linkding..."
mkdir -p /opt/linkding /media/linkding/data

cat > /opt/linkding/docker-compose.yml <<EOF
version: "3.8"
services:
  linkding:
    image: sissbruecker/linkding:latest
    container_name: linkding
    ports:
      - "9090:9090"
    volumes:
      - /media/linkding/data:/etc/linkding/data
    restart: unless-stopped
EOF

cd /opt/linkding && docker compose pull && docker compose up -d
warn "Create your Linkding admin user:"
warn "  docker exec -it linkding python manage.py createsuperuser --username=admin"

# ── AMP (Game Server Manager) ─────────────────────────────────
step "Installing AMP prerequisites..."
# AMP requires Java and a free licence from cubecoders.com
# The installer is interactive so we install deps and leave a helper script
apt install -y default-jre-headless

cat > /opt/install-amp.sh <<'EOF'
#!/bin/bash
# Run this manually after getting your free AMP licence from:
# https://manage.cubecoders.com/Login
# AMP is free for personal use — create an account and get a licence key
echo "Starting AMP installer..."
bash <(wget -qO- getamp.sh)
# AMP will run on port 8080 by default — it will conflict with Stirling-PDF
# During the AMP setup wizard, change the port to 8081
EOF
chmod +x /opt/install-amp.sh
warn "AMP requires a free licence key from cubecoders.com"
warn "After getting your key, run: sudo /opt/install-amp.sh"
warn "During AMP setup, set the port to 8081 (Stirling-PDF uses 8080)"

# ── Dawarich (Docker) ─────────────────────────────────────────
step "Installing Dawarich (location history)..."
mkdir -p /opt/dawarich
mkdir -p /media/dawarich/{db,gem-cache,public,watched,exports}

cat > /opt/dawarich/docker-compose.yml <<EOF
version: "3.8"
services:
  dawarich_db:
    image: postgres:17
    container_name: dawarich_db
    restart: unless-stopped
    volumes:
      - /media/dawarich/db:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: dawarich
      POSTGRES_PASSWORD: dawarich
      POSTGRES_DB: dawarich_production
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dawarich -d dawarich_production"]
      interval: 10s
      timeout: 5s
      retries: 5

  dawarich_redis:
    image: redis:7
    container_name: dawarich_redis
    restart: unless-stopped
    command: redis-server --appendonly yes

  dawarich_app:
    image: freikin/dawarich:latest
    container_name: dawarich_app
    depends_on:
      dawarich_db:
        condition: service_healthy
      dawarich_redis:
        condition: service_started
    ports:
      - "3030:3000"
    volumes:
      - /media/dawarich/gem-cache:/usr/local/bundle/gems
      - /media/dawarich/public:/var/app/public
      - /media/dawarich/watched:/var/app/tmp/imports/watched
      - /media/dawarich/exports:/var/app/public/exports
    environment:
      RAILS_ENV: production
      DATABASE_HOST: dawarich_db
      DATABASE_PORT: 5432
      DATABASE_NAME: dawarich_production
      DATABASE_USERNAME: dawarich
      DATABASE_PASSWORD: dawarich
      REDIS_URL: redis://dawarich_redis:6379/0
      APPLICATION_HOSTS: localhost,127.0.0.1
      APPLICATION_PROTOCOL: http
      SECRET_KEY_BASE: $(openssl rand -hex 64)
      MIN_MINUTES_SPENT_IN_CITY: 60
      TIME_ZONE: America/Chicago
    restart: unless-stopped

  dawarich_sidekiq:
    image: freikin/dawarich:latest
    container_name: dawarich_sidekiq
    command: sidekiq
    depends_on:
      dawarich_db:
        condition: service_healthy
      dawarich_redis:
        condition: service_started
    volumes:
      - /media/dawarich/gem-cache:/usr/local/bundle/gems
      - /media/dawarich/public:/var/app/public
      - /media/dawarich/watched:/var/app/tmp/imports/watched
    environment:
      RAILS_ENV: production
      DATABASE_HOST: dawarich_db
      DATABASE_PORT: 5432
      DATABASE_NAME: dawarich_production
      DATABASE_USERNAME: dawarich
      DATABASE_PASSWORD: dawarich
      REDIS_URL: redis://dawarich_redis:6379/0
      APPLICATION_HOSTS: localhost,127.0.0.1
      APPLICATION_PROTOCOL: http
      SECRET_KEY_BASE: $(openssl rand -hex 64)
    restart: unless-stopped
EOF

cd /opt/dawarich && docker compose pull && docker compose up -d
warn "Dawarich default login: demo@dawarich.app / password — change immediately at http://localhost:3030"


apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh           # 22
ufw allow 80/tcp        # Caddy HTTP
ufw allow 443/tcp       # Caddy HTTPS
ufw allow 8096/tcp      # Jellyfin (direct)
ufw allow 13378/tcp     # Audiobookshelf (direct)
ufw allow 8080/tcp      # Stirling-PDF (direct)
ufw allow 7745/tcp      # HomeBox (direct)
ufw allow 8384/tcp      # Syncthing
ufw allow 3001/tcp      # Uptime Kuma (direct)
ufw allow 8000/tcp      # Paperless-ngx
ufw allow 8222/tcp      # Vaultwarden
ufw allow 3000/tcp      # Homepage
ufw allow 19999/tcp     # Netdata
ufw allow 9090/tcp      # Linkding
ufw allow 8081/tcp      # AMP
ufw allow 3030/tcp      # Dawarich
ufw allow 25565/tcp     # Minecraft
ufw allow 7777/tcp      # Terraria
ufw allow 21115/tcp     # RustDesk hbbs
ufw allow 21116/tcp     # RustDesk hbbs
ufw allow 21116/udp     # RustDesk hbbs
ufw allow 21117/tcp     # RustDesk hbbr
ufw allow 21118/tcp     # RustDesk hbbs (web)
ufw allow 21119/tcp     # RustDesk hbbr (web)
ufw --force enable

# ── Security: fail2ban ────────────────────────────────────────
step "Installing fail2ban..."
apt install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF

systemctl enable --now fail2ban

# ── Security: SSH hardening ───────────────────────────────────
step "Hardening SSH..."
warn "Password auth will be DISABLED. Make sure your SSH key is already in ~/.ssh/authorized_keys before rebooting."
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl reload sshd

# ── Auto security updates ─────────────────────────────────────
step "Enabling unattended security upgrades..."
apt install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
dpkg-reconfigure -f noninteractive unattended-upgrades

# ── Timeshift (system snapshots) ──────────────────────────────
step "Installing Timeshift..."
apt install -y timeshift
warn "Configure Timeshift manually after install — set snapshot location and schedule via: sudo timeshift-gtk"

# ── Backups (rsync cron) ──────────────────────────────────────
step "Setting up backup script..."
mkdir -p /media/backups

cat > /opt/backup.sh <<EOF
#!/bin/bash
# Daily backup — runs at 3:00 AM
# Adjust paths if your media drive mount point differs
TIMESTAMP=\$(date +"%Y-%m-%d")
LOG="/var/log/backup.log"

echo "[\$TIMESTAMP] Starting backup..." >> \$LOG

rsync -av --delete /var/lib/jellyfin/         /media/backups/jellyfin/         >> \$LOG 2>&1
rsync -av --delete /media/audiobookshelf/     /media/backups/audiobookshelf/   >> \$LOG 2>&1
rsync -av --delete /media/homebox/            /media/backups/homebox/          >> \$LOG 2>&1
rsync -av --delete /media/paperless/          /media/backups/paperless/        >> \$LOG 2>&1
rsync -av --delete /media/uptime-kuma/        /media/backups/uptime-kuma/      >> \$LOG 2>&1
rsync -av --delete /media/vaultwarden/        /media/backups/vaultwarden/      >> \$LOG 2>&1
rsync -av --delete /media/linkding/           /media/backups/linkding/         >> \$LOG 2>&1
rsync -av --delete /media/dawarich/           /media/backups/dawarich/         >> \$LOG 2>&1
rsync -av --delete /media/homepage/           /media/backups/homepage/         >> \$LOG 2>&1
rsync -av --delete /home/                     /media/backups/home/             >> \$LOG 2>&1

echo "[\$TIMESTAMP] Backup complete." >> \$LOG
EOF
chmod +x /opt/backup.sh

# Add to root crontab — daily at 3 AM
(crontab -l 2>/dev/null; echo "0 3 * * * /opt/backup.sh") | crontab -

# ── Email relay (msmtp) ───────────────────────────────────────
step "Installing msmtp for outbound email..."
apt install -y msmtp msmtp-mta mailutils

# Write config template — user fills in credentials after install
cat > /etc/msmtprc <<'EOF'
# Global defaults
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

# Gmail account — replace with your credentials
# For Gmail: use an App Password, not your real password
# Generate one at: https://myaccount.google.com/apppasswords
account        gmail
host           smtp.gmail.com
port           587
from           YOUR_EMAIL@gmail.com
user           YOUR_EMAIL@gmail.com
password       YOUR_APP_PASSWORD

# Set gmail as default
account default : gmail
EOF
chmod 600 /etc/msmtprc

warn "Edit /etc/msmtprc and fill in your Gmail address and App Password before the status emails will work."
warn "Generate an App Password at: https://myaccount.google.com/apppasswords"

# ── Daily status email script ─────────────────────────────────
step "Setting up daily status email..."

cat > /opt/status-email.sh <<'STATUSEOF'
#!/bin/bash
# Daily server status report — runs at 8:00 AM
TO="YOUR_EMAIL@gmail.com"
SUBJECT="[Server] Morning Status Report — $(date '+%A %b %d')"
HOSTNAME=$(hostname)
WARNINGS=()
BODY=""

divider() { echo "────────────────────────────────────"; }

# ── Systemd services ──────────────────────────────────────────
WATCHED_SERVICES=(
    jellyfin
    tailscaled
    caddy
    rustdesk-hbbs
    rustdesk-hbbr
    fail2ban
    minecraft
    terraria
)

svc_status=""
for svc in "${WATCHED_SERVICES[@]}"; do
    state=$(systemctl is-active "$svc" 2>/dev/null)
    if [ "$state" = "active" ]; then
        svc_status+="  ✔  $svc\n"
    else
        svc_status+="  ✘  $svc ($state)\n"
        WARNINGS+=("Systemd service FAILED: $svc")
    fi
done

# ── Docker containers ─────────────────────────────────────────
WATCHED_CONTAINERS=(
    audiobookshelf
    stirling-pdf
    homebox
    uptime-kuma
    paperless-ngx
    vaultwarden
    homepage
    netdata
    linkding
    dawarich_app
)

docker_status=""
for ctr in "${WATCHED_CONTAINERS[@]}"; do
    state=$(docker inspect --format='{{.State.Status}}' "$ctr" 2>/dev/null || echo "not found")
    if [ "$state" = "running" ]; then
        docker_status+="  ✔  $ctr\n"
    else
        docker_status+="  ✘  $ctr ($state)\n"
        WARNINGS+=("Docker container FAILED: $ctr")
    fi
done

# ── Disk usage ────────────────────────────────────────────────
disk_status=""
while IFS= read -r line; do
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    disk_status+="  $line\n"
    if [ "$pct" -ge 85 ]; then
        WARNINGS+=("Disk usage at ${pct}% on $mount")
    fi
done < <(df -h | grep -E '^/dev/' | awk '{print $1, $2, $3, $4, $5, $6}')

# ── Memory ───────────────────────────────────────────────────
mem_total=$(free -m | awk '/^Mem:/{print $2}')
mem_used=$(free -m | awk '/^Mem:/{print $3}')
mem_pct=$(( mem_used * 100 / mem_total ))
mem_status="  Used: ${mem_used}MB / ${mem_total}MB (${mem_pct}%)"
if [ "$mem_pct" -ge 90 ]; then
    WARNINGS+=("Memory usage critical: ${mem_pct}%")
fi

# ── Uptime ────────────────────────────────────────────────────
uptime_str=$(uptime -p)

# ── Recent failed logins ──────────────────────────────────────
failed_logins=$(journalctl _SYSTEMD_UNIT=sshd.service --since "24 hours ago" \
    | grep -c "Failed password" 2>/dev/null || echo "0")
if [ "$failed_logins" -gt 10 ]; then
    WARNINGS+=("$failed_logins failed SSH login attempts in the last 24 hours")
fi

# ── Last backup check ─────────────────────────────────────────
backup_log="/var/log/backup.log"
if [ -f "$backup_log" ]; then
    last_backup=$(grep "Backup complete" "$backup_log" | tail -1)
    backup_status="  $last_backup"
else
    backup_status="  No backup log found"
    WARNINGS+=("No backup log found — backup may not be running")
fi

# ── Build email body ──────────────────────────────────────────
if [ ${#WARNINGS[@]} -eq 0 ]; then
    summary="✔ All systems normal"
else
    summary="⚠ ${#WARNINGS[@]} warning(s) detected"
fi

BODY+="Server: $HOSTNAME\n"
BODY+="Time:   $(date)\n"
BODY+="Uptime: $uptime_str\n"
BODY+="\nSUMMARY: $summary\n"

if [ ${#WARNINGS[@]} -gt 0 ]; then
    BODY+="\n⚠ WARNINGS\n"
    BODY+="$(divider)\n"
    for w in "${WARNINGS[@]}"; do
        BODY+="  ! $w\n"
    done
fi

BODY+="\nSYSTEMD SERVICES\n"
BODY+="$(divider)\n"
BODY+="$svc_status"

BODY+="\nDOCKER CONTAINERS\n"
BODY+="$(divider)\n"
BODY+="$docker_status"

BODY+="\nDISK USAGE\n"
BODY+="$(divider)\n"
BODY+="$disk_status"

BODY+="\nMEMORY\n"
BODY+="$(divider)\n"
BODY+="$mem_status\n"

BODY+="\nLAST BACKUP\n"
BODY+="$(divider)\n"
BODY+="$backup_status\n"

BODY+="\nSSH FAILED LOGINS (last 24h)\n"
BODY+="$(divider)\n"
BODY+="  $failed_logins failed attempt(s)\n"

# Send it
echo -e "$BODY" | mail -s "$SUBJECT" "$TO"
STATUSEOF

chmod +x /opt/status-email.sh

# Cron: daily at 8 AM
(crontab -l 2>/dev/null; echo "0 8 * * * /opt/status-email.sh") | crontab -

warn "Edit the TO address in /opt/status-email.sh to set where the report gets sent."

# ── Enable all services ───────────────────────────────────────
step "Enabling and starting services..."
systemctl daemon-reload

systemctl enable --now jellyfin
systemctl enable --now tailscaled
systemctl enable --now caddy
systemctl enable --now "syncthing@${REAL_USER}"
systemctl enable --now docker
# All Docker services (ABS, Stirling-PDF, HomeBox, Uptime Kuma, Paperless) managed by Docker
systemctl enable --now rustdesk-hbbs
systemctl enable --now rustdesk-hbbr
# Game servers — enable but don't start (configure first)
systemctl enable minecraft
systemctl enable terraria

# ── Done ──────────────────────────────────────────────────────
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN} Install complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e " ${CYAN}Service URLs:${NC}"
echo -e "   Homepage        → http://localhost:3000  ← start here"
echo -e "   Jellyfin        → http://localhost:8096"
echo -e "   Audiobookshelf  → http://localhost:13378"
echo -e "   Stirling-PDF    → http://localhost:8080"
echo -e "   HomeBox         → http://localhost:7745"
echo -e "   Syncthing       → http://localhost:8384"
echo -e "   Uptime Kuma     → http://localhost:3001"
echo -e "   Paperless-ngx   → http://localhost:8000"
echo -e "   Vaultwarden     → http://localhost:8222"
echo -e "   Netdata         → http://localhost:19999"
echo -e "   Linkding        → http://localhost:9090"
echo -e "   Dawarich        → http://localhost:3030"
echo -e "   AMP             → http://localhost:8081  (after manual install)"
echo -e "   RustDesk hbbs   → port 21116 (configure in RustDesk client)"
echo ""
echo -e " ${YELLOW}Manual steps still needed:${NC}"
echo -e "   1.  tailscale up"
echo -e "   2.  playit  (configure tunnel)"
echo -e "   3.  Edit /etc/caddy/Caddyfile with your real hostnames, then: caddy reload"
echo -e "   4.  Edit /opt/terraria/serverconfig.txt before starting Terraria"
echo -e "   5.  Adjust Minecraft RAM in /etc/systemd/system/minecraft.service if needed"
echo -e "   6.  In Jellyfin settings → Playback → enable Intel Quick Sync transcoding"
echo -e "   7.  Point Jellyfin and ABS libraries to /media"
echo -e "   8.  Configure Timeshift snapshots: sudo timeshift-gtk"
echo -e "   9.  Set up Syncthing vault at http://localhost:8384"
echo -e "   10. Streambert is a desktop app — launch from app menu"
echo -e "   11. SSH password auth is now DISABLED — key access only"
echo -e "   12. RustDesk: cat /opt/rustdesk/id_ed25519.pub — enter key in RustDesk client"
echo -e "   13. Edit /etc/msmtprc — fill in Gmail address and App Password"
echo -e "       https://myaccount.google.com/apppasswords"
echo -e "   14. Edit /opt/status-email.sh — set TO address, then: sudo /opt/status-email.sh"
echo -e "   15. Vaultwarden: disable open signups at http://localhost:8222/admin"
echo -e "   16. Linkding: docker exec -it linkding python manage.py createsuperuser --username=admin"
echo -e "   17. Paperless: docker compose -f /opt/paperless/docker-compose.yml exec webserver createsuperuser"
echo -e "   18. AMP: register free at cubecoders.com then run: sudo /opt/install-amp.sh"
echo -e "       Set port to 8081 during AMP wizard (8080 is taken by Stirling-PDF)"
echo ""
