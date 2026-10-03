#!/bin/bash
# ===============================================================
# VoiceStudio — tmux + Docker launcher generator (v2)
# Adds: SSL + domain + HTTP Basic Auth + systemd for server mode
# ===============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   VoiceStudio — launcher generator (local + server)           ║"
echo "║   tmux for local dev  •  SSL+auth+systemd for Ubuntu servers  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Launcher folder name (default: voicestudio-tmux): " EXTNAME
EXTNAME=${EXTNAME:-voicestudio-tmux}

if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwrite."
        exit 1
    fi
fi

mkdir -p "$EXTNAME/icons" "$EXTNAME/server" "$EXTNAME/templates"
cd "$EXTNAME" || exit

# ---------------------------------------------------------------
# Icon
# ---------------------------------------------------------------
echo -e "${CYAN}📥 Downloading VoiceStudio icon...${NC}"
curl -sL -o icons/icon.png \
    "https://avatars.githubusercontent.com/u/167430648?s=200&v=4" || true

if [ ! -s icons/icon.png ]; then
    echo -e "${YELLOW}⚠ Icon download failed — using fallback SVG${NC}"
    cat > icons/icon.svg << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#0f172a"/>
  <rect x="10" y="20" width="6" height="24" rx="3" fill="#38bdf8"/>
  <rect x="20" y="14" width="6" height="36" rx="3" fill="#a78bfa"/>
  <rect x="30" y="24" width="6" height="16" rx="3" fill="#fbbf24"/>
  <rect x="40" y="16" width="6" height="32" rx="3" fill="#34d399"/>
  <rect x="50" y="26" width="6" height="12" rx="3" fill="#f472b6"/>
</svg>
SVGEOF
    cp icons/icon.svg icons/icon.png 2>/dev/null || true
fi

cp icons/icon.png icons/icon128.png 2>/dev/null || true

# ===============================================================
# LOCAL DEV: voicestudio-tmux.sh (unchanged from v1)
# ===============================================================
cat << 'EOL' > voicestudio-tmux.sh
#!/bin/bash
set -e

# VoiceStudio — tmux + Docker launcher (LOCAL DEV)
# Usage: ./voicestudio-tmux.sh [cpu|gpu|rocm|worker-gpu|worker-rocm] [path-to-repo]

SESSION="${VOICESTUDIO_SESSION:-voicestudio}"
PROFILE="${1:-cpu}"
REPO="${2:-.}"

if ! command -v tmux >/dev/null 2>&1; then
    echo "Error: tmux is not installed." >&2
    echo "  macOS:  brew install tmux" >&2
    echo "  Debian: sudo apt install tmux" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed." >&2
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Error: docker compose (plugin) is not available." >&2
    exit 1
fi

if [ ! -f "$REPO/deploy/docker-compose.yml" ]; then
    echo "Error: $REPO/deploy/docker-compose.yml not found." >&2
    echo "Run this from the VoiceStudio repo root, or pass the path as arg 2." >&2
    exit 1
fi

REPO_ABS="$(cd "$REPO" && pwd)"
COMPOSE_FILE="$REPO_ABS/deploy/docker-compose.yml"

if [ -z "${OMNIVOICE_API_KEY:-}" ]; then
    echo "Error: OMNIVOICE_API_KEY is not set." >&2
    echo "Generate one with:" >&2
    echo "  export OMNIVOICE_API_KEY=\"\$(openssl rand -hex 32)\"" >&2
    exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already exists. Attaching..."
    tmux attach -t "$SESSION"
    exit 0
fi

UP_FLAGS="${COMPOSE_UP_FLAGS:-}"
COMPOSE_CMD="cd '$REPO_ABS' && docker compose -f '$COMPOSE_FILE' --profile $PROFILE"

tmux new-session -d -s "$SESSION" -n "studio"
tmux send-keys -t "$SESSION:studio" "$COMPOSE_CMD up $UP_FLAGS" Enter

tmux new-window -t "$SESSION" -n "logs"
tmux send-keys -t "$SESSION:logs" "$COMPOSE_CMD logs -f" Enter

tmux new-window -t "$SESSION" -n "shell"
tmux send-keys -t "$SESSION:shell" "cd '$REPO_ABS'" Enter

tmux set-option -t "$SESSION" status-left "[#S] "
tmux set-option -t "$SESSION" status-right "profile=$PROFILE  |  %H:%M"

echo "Session '$SESSION' created. Attaching..."
echo "Detach with Ctrl-b d, re-attach with: tmux attach -t $SESSION"
tmux attach -t "$SESSION"
EOL
chmod +x voicestudio-tmux.sh

# ===============================================================
# LOCAL DEV: start.sh / stop.sh
# ===============================================================
cat << 'EOL' > start.sh
#!/bin/bash
set -e
if [ -z "${OMNIVOICE_API_KEY:-}" ]; then
    if [ -f .env ]; then
        set -a; . ./.env; set +a
    else
        echo "Generating OMNIVOICE_API_KEY and saving to .env ..."
        echo "OMNIVOICE_API_KEY=$(openssl rand -hex 32)" > .env
        chmod 600 .env
        set -a; . ./.env; set +a
    fi
fi
./voicestudio-tmux.sh "${1:-cpu}" "${2:-.}"
EOL
chmod +x start.sh

cat << 'EOL' > stop.sh
#!/bin/bash
set -e
SESSION="${VOICESTUDIO_SESSION:-voicestudio}"
PROFILE="${1:-cpu}"
REPO="${2:-.}"
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Killing tmux session '$SESSION'..."
    tmux kill-session -t "$SESSION"
fi
if [ -f "$REPO/deploy/docker-compose.yml" ]; then
    echo "Bringing compose stack down (profile $PROFILE)..."
    ( cd "$REPO" && docker compose -f deploy/docker-compose.yml --profile "$PROFILE" down ) || true
fi
echo "Stopped."
EOL
chmod +x stop.sh

# ===============================================================
# SERVER: templates
# ===============================================================
cat << 'EOL' > templates/voicestudio.service
[Unit]
Description=VoiceStudio (docker compose, {{PROFILE}} profile)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={{REPO_ABS}}
EnvironmentFile={{ENV_FILE}}
ExecStart=/usr/bin/docker compose -f {{REPO_ABS}}/deploy/docker-compose.yml --profile {{PROFILE}} up -d
ExecStop=/usr/bin/docker compose -f {{REPO_ABS}}/deploy/docker-compose.yml --profile {{PROFILE}} down
TimeoutStartSec=0
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOL

cat << 'EOL' > templates/nginx-voicestudio.conf
# VoiceStudio — managed by setup-ssl.sh
# Do not edit by hand. Re-run setup-ssl.sh instead.
#
# Assumes VoiceStudio is bound to 127.0.0.1:{{UI_PORT}}.
# The 443 block is a placeholder; certbot --nginx will fill in the
# ssl_certificate directives and add the HTTP->HTTPS redirect.

server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}};

    # ACME challenge must be reachable without auth
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Everything else: 301 to HTTPS (certbot --redirect will enforce this
    # too, but we set it explicitly so plain-HTTP never serves the UI)
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name {{DOMAIN}};

    # --- certbot fills these in ---
    # ssl_certificate     /etc/letsencrypt/live/{{DOMAIN}}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/{{DOMAIN}}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    # --- AUTH: the only thing between the internet and your GPU ---
    auth_basic "VoiceStudio";
    auth_basic_user_file /etc/nginx/.htpasswd-voicestudio;

    # --- Security headers ---
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    # --- Uploads: voice samples ---
    client_max_body_size 200M;

    # --- Timeouts: TTS jobs can run for minutes ---
    proxy_connect_timeout 60s;
    proxy_send_timeout    600s;
    proxy_read_timeout    600s;

    # --- Streaming-friendly: do not buffer ---
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_http_version 1.1;

    # --- WebSocket upgrade support (UI progress streams) ---
    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection "upgrade";

    # --- Real client info to the app ---
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    location / {
        proxy_pass http://127.0.0.1:{{UI_PORT}};
    }

    # Health endpoint stays unauthenticated so monitors work
    location = /health {
        auth_basic off;
        proxy_pass http://127.0.0.1:{{UI_PORT}}/health;
        access_log off;
    }
}
EOL

# ===============================================================
# SERVER: setup-ssl.sh
# ===============================================================
cat << 'EOL' > setup-ssl.sh
#!/bin/bash
# ===============================================================
# VoiceStudio — Ubuntu server setup (SSL + Basic Auth + systemd)
#
# Usage:
#   sudo ./setup-ssl.sh <domain> <email> [repo-path]
#
# Example:
#   sudo ./setup-ssl.sh voice.example.com admin@example.com /opt/VoiceStudio
#
# Assumptions:
#   - Ubuntu 22.04 / 24.04
#   - docker + docker compose plugin installed
#   - The VoiceStudio repo is cloned with deploy/docker-compose.yml
#   - Domain A-record already points at this box's public IP
#   - Ports 80 + 443 reachable from the internet (no ISP block)
#
# What it does:
#   1. Installs nginx, certbot, apache2-utils (htpasswd)
#   2. Writes + enables a systemd unit for the compose stack
#   3. Writes an nginx server block with basic auth + long timeouts
#   4. Runs certbot --nginx to issue + install the cert and redirect
#   5. Prints the credentials ONCE
#
# Re-runnable: existing certs are reused; existing htpasswd is preserved
# unless BASIC_AUTH_PASS is set in the environment.
# ===============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[x]${NC} $1" >&2; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# ---------------------------------------------------------------
# Args
# ---------------------------------------------------------------
DOMAIN="${1:-}"
SSL_EMAIL="${2:-}"
REPO_PATH="${3:-}"

if [ -z "$DOMAIN" ] || [ -z "$SSL_EMAIL" ]; then
    echo "Usage: sudo ./setup-ssl.sh <domain> <email> [repo-path]"
    echo "  e.g. sudo ./setup-ssl.sh voice.example.com you@example.com /opt/VoiceStudio"
    exit 1
fi

[ "$EUID" -eq 0 ] || die "Must run as root (use sudo)."

[[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || die "Invalid domain: $DOMAIN"
[[ "$SSL_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]        || die "Invalid email: $SSL_EMAIL"

# ---------------------------------------------------------------
# Resolve repo
# ---------------------------------------------------------------
if [ -z "$REPO_PATH" ]; then
    for c in /opt/VoiceStudio /root/VoiceStudio "$HOME/VoiceStudio" ./VoiceStudio; do
        if [ -f "$c/deploy/docker-compose.yml" ]; then REPO_PATH="$c"; break; fi
    done
fi
[ -n "$REPO_PATH" ] || die "Could not find VoiceStudio repo. Pass it as arg 3."
[ -f "$REPO_PATH/deploy/docker-compose.yml" ] || die "$REPO_PATH/deploy/docker-compose.yml not found."
REPO_ABS="$(cd "$REPO_PATH" && pwd)"

# ---------------------------------------------------------------
# Config (env overrides)
# ---------------------------------------------------------------
PROFILE="${PROFILE:-cpu}"
UI_PORT="${UI_PORT:-3900}"
BASIC_AUTH_USER="${BASIC_AUTH_USER:-admin}"
# If BASIC_AUTH_PASS is set, we always rewrite the htpasswd entry.
# If it's not set and htpasswd already exists, we preserve it.
if [ -z "${BASIC_AUTH_PASS:-}" ]; then
    if [ -f /etc/nginx/.htpasswd-voicestudio ]; then
        BASIC_AUTH_PASS=""
        info "Reusing existing /etc/nginx/.htpasswd-voicestudio"
    else
        BASIC_AUTH_PASS="$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)"
    fi
fi

log "Repo:    $REPO_ABS"
log "Domain:  $DOMAIN"
log "Email:   $SSL_EMAIL"
log "Profile: $PROFILE"
log "UI port: $UI_PORT (on loopback)"

# ---------------------------------------------------------------
# DNS preflight
# ---------------------------------------------------------------
PUBLIC_IP="$(curl -fsS --max-time 5 https://api.ipify.org || curl -fsS --max-time 5 http://checkip.amazonaws.com || true)"
if [ -n "$PUBLIC_IP" ]; then
    RESOLVED="$(getent hosts "$DOMAIN" | awk '{print $1; exit}' || true)"
    if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "$PUBLIC_IP" ]; then
        warn "DNS mismatch: $DOMAIN -> $RESOLVED, this box -> $PUBLIC_IP"
        warn "Certbot will fail if the A-record does not point here."
        read -p "Continue anyway? (y/N): " CONT
        [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
    else
        info "DNS check: $DOMAIN resolves to $RESOLVED (this box: $PUBLIC_IP)"
    fi
else
    warn "Could not determine public IP — skipping DNS preflight."
fi

# ---------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------
log "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

install_if_missing() {
    local pkg="$1"
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        log "Installing $pkg..."
        apt-get install -y -qq "$pkg"
    else
        info "$pkg already installed."
    fi
}

install_if_missing nginx
install_if_missing certbot
install_if_missing python3-certbot-nginx
install_if_missing apache2-utils

command -v docker >/dev/null 2>&1 || die "docker not installed."
docker compose version >/dev/null 2>&1 || die "docker compose plugin not available."

# ---------------------------------------------------------------
# Firewall (ufw) — open 80 + 443
# ---------------------------------------------------------------
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp  >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    info "ufw: 80/443 allowed."
fi

# ---------------------------------------------------------------
# Ensure .env exists in repo (holds OMNIVOICE_API_KEY)
# ---------------------------------------------------------------
ENV_FILE="$REPO_ABS/.env"
if [ ! -f "$ENV_FILE" ]; then
    log "Creating $ENV_FILE with a fresh OMNIVOICE_API_KEY"
    OMNIVOICE_API_KEY="$(openssl rand -hex 32)"
    cat > "$ENV_FILE" <<EOF
OMNIVOICE_API_KEY=$OMNIVOICE_API_KEY
EOF
    chmod 600 "$ENV_FILE"
else
    info "Reusing existing $ENV_FILE"
fi

# ---------------------------------------------------------------
# systemd unit
# ---------------------------------------------------------------
log "Writing systemd unit /etc/systemd/system/voicestudio.service"
TMP_UNIT="$(mktemp)"
sed -e "s|{{PROFILE}}|$PROFILE|g" \
    -e "s|{{REPO_ABS}}|$REPO_ABS|g" \
    -e "s|{{ENV_FILE}}|$ENV_FILE|g" \
    /dev/stdin > "$TMP_UNIT" <<'UNITEOF'
[Unit]
Description=VoiceStudio (docker compose, {{PROFILE}} profile)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory={{REPO_ABS}}
EnvironmentFile={{ENV_FILE}}
ExecStart=/usr/bin/docker compose -f {{REPO_ABS}}/deploy/docker-compose.yml --profile {{PROFILE}} up -d
ExecStop=/usr/bin/docker compose -f {{REPO_ABS}}/deploy/docker-compose.yml --profile {{PROFILE}} down
TimeoutStartSec=0
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
UNITEOF

mv "$TMP_UNIT" /etc/systemd/system/voicestudio.service
systemctl daemon-reload
systemctl enable voicestudio.service >/dev/null

# ---------------------------------------------------------------
# htpasswd
# ---------------------------------------------------------------
if [ -n "$BASIC_AUTH_PASS" ]; then
    log "Writing /etc/nginx/.htpasswd-voicestudio"
    htpasswd -bc /etc/nginx/.htpasswd-voicestudio "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS"
    chmod 640 /etc/nginx/.htpasswd-voicestudio
    chown root:www-data /etc/nginx/.htpasswd-voicestudio
fi

# ---------------------------------------------------------------
# nginx server block
# ---------------------------------------------------------------
log "Writing /etc/nginx/sites-available/voicestudio.conf"
TMP_CONF="$(mktemp)"
sed -e "s|{{DOMAIN}}|$DOMAIN|g" \
    -e "s|{{UI_PORT}}|$UI_PORT|g" \
    /dev/stdin > "$TMP_CONF" <<'NGINXEOF'
# VoiceStudio — managed by setup-ssl.sh
# Do not edit by hand. Re-run setup-ssl.sh instead.

server {
    listen 80;
    listen [::]:80;
    server_name {{DOMAIN}};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name {{DOMAIN}};

    # --- certbot fills these in ---
    # ssl_certificate     /etc/letsencrypt/live/{{DOMAIN}}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/{{DOMAIN}}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers off;

    auth_basic "VoiceStudio";
    auth_basic_user_file /etc/nginx/.htpasswd-voicestudio;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    client_max_body_size 200M;

    proxy_connect_timeout 60s;
    proxy_send_timeout    600s;
    proxy_read_timeout    600s;

    proxy_buffering off;
    proxy_request_buffering off;
    proxy_http_version 1.1;

    proxy_set_header Upgrade    $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    location / {
        proxy_pass http://127.0.0.1:{{UI_PORT}};
    }

    location = /health {
        auth_basic off;
        proxy_pass http://127.0.0.1:{{UI_PORT}}/health;
        access_log off;
    }
}
NGINXEOF

mv "$TMP_CONF" /etc/nginx/sites-available/voicestudio.conf
ln -sf /etc/nginx/sites-available/voicestudio.conf /etc/nginx/sites-enabled/voicestudio.conf

# ---------------------------------------------------------------
# Pre-cert nginx check
# The 443 block has commented-out ssl_certificate directives, which
# means nginx will refuse to start with a 443 listener. So: obtain
# the cert BEFORE we try to start nginx, using certbot standalone.
# ---------------------------------------------------------------
log "Ensuring /var/www/html exists for ACME challenges"
mkdir -p /var/www/html

# Remove the 443 block temporarily so nginx -t passes if nginx is
# already running. We do this by moving the file out of sites-enabled.
if [ -f /etc/nginx/sites-enabled/voicestudio.conf ]; then
    rm -f /etc/nginx/sites-enabled/voicestudio.conf
fi

# Make sure nginx is running for the webroot challenge path
systemctl start nginx 2>/dev/null || true
nginx -t || die "nginx config invalid before certbot. Check /etc/nginx/."

# ---------------------------------------------------------------
# Certbot
# ---------------------------------------------------------------
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    info "Certificate already exists for $DOMAIN — skipping issuance."
else
    log "Obtaining Let's Encrypt certificate (standalone on :80)"
    # Stop nginx for standalone :80 challenge
    systemctl stop nginx 2>/dev/null || true
    if ! certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "$SSL_EMAIL" \
            -d "$DOMAIN" \
            --preferred-challenges http; then
        warn "Standalone failed. Trying webroot..."
        systemctl start nginx 2>/dev/null || true
        certbot certonly --webroot -w /var/www/html \
            --non-interactive \
            --agree-tos \
            --email "$SSL_EMAIL" \
            -d "$DOMAIN" \
            || die "Certbot failed. Check DNS + that port 80 is reachable."
    fi
fi

# ---------------------------------------------------------------
# Inject cert paths into the 443 block
# ---------------------------------------------------------------
CONF=/etc/nginx/sites-available/voicestudio.conf
if ! grep -q "ssl_certificate /etc/letsencrypt/live/$DOMAIN" "$CONF"; then
    log "Injecting ssl_certificate paths"
    # Uncomment the placeholders and substitute domain
    sed -i \
        -e "s|# ssl_certificate     /etc/letsencrypt/live/{{DOMAIN}}/fullchain.pem;|ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;|" \
        -e "s|# ssl_certificate_key /etc/letsencrypt/live/{{DOMAIN}}/privkey.pem;|ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;|" \
        "$CONF"

    # If the sed above didn't match (because we substituted {{DOMAIN}} already),
    # fall back to a plain replace of the commented block.
    if ! grep -q "ssl_certificate " "$CONF"; then
        # Insert cert directives right after the http2 line
        sed -i "/http2 on;/a\\
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;\\
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;" "$CONF"
    fi
fi

# ---------------------------------------------------------------
# Re-enable the site and validate
# ---------------------------------------------------------------
ln -sf /etc/nginx/sites-available/voicestudio.conf /etc/nginx/sites-enabled/voicestudio.conf

log "Testing nginx config"
nginx -t || die "nginx config invalid after certbot. Inspect /etc/nginx/sites-available/voicestudio.conf"

# ---------------------------------------------------------------
# Cert renewal hook
# ---------------------------------------------------------------
log "Installing certbot renewal hook"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOKEOF'
#!/bin/bash
systemctl reload nginx || systemctl restart nginx
HOOKEOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

# ---------------------------------------------------------------
# Start services
# ---------------------------------------------------------------
log "Starting VoiceStudio stack (this may take a while on first run)"
systemctl start voicestudio.service || warn "voicestudio.service start returned non-zero — check journalctl -u voicestudio"

log "Restarting nginx"
systemctl restart nginx
systemctl enable nginx >/dev/null

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   VoiceStudio server setup complete                       ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "URL:  https://$DOMAIN"
if [ -n "${BASIC_AUTH_PASS:-}" ]; then
    info "User:     $BASIC_AUTH_USER"
    info "Password: $BASIC_AUTH_PASS"
    warn "Save the password now — it is not shown again and not stored in plaintext."
else
    info "Auth: reusing existing /etc/nginx/.htpasswd-voicestudio"
fi
echo ""
info "First start downloads ~4GB of models. Tail progress with:"
echo "    journalctl -u voicestudio -f"
echo "    docker compose -f $REPO_ABS/deploy/docker-compose.yml logs -f"
echo ""
info "Healthcheck start period is 120s (CPU) / 180s (GPU). The UI may 502"
info "until it passes. That is normal on first boot."
echo ""
info "Management:"
echo "    systemctl status voicestudio"
echo "    systemctl restart voicestudio"
echo "    journalctl -u voicestudio -f"
echo "    certbot renew --dry-run    # test renewal"
echo ""
warn "SECURITY: this endpoint is on the public internet behind HTTP Basic"
warn "Auth only. If you want stronger protection, put Cloudflare Access or"
warn "Tailscale in front. Do NOT remove the auth_basic lines."
EOL

chmod +x setup-ssl.sh

# ===============================================================
# .env.example
# ===============================================================
cat << 'EOL' > .env.example
# =============================================================
# VoiceStudio launcher environment
# =============================================================
#
# LOCAL DEV (tmux launcher):
#   export OMNIVOICE_API_KEY="$(openssl rand -hex 32)"
#   ./start.sh cpu
#
# SERVER (setup-ssl.sh):
#   sudo BASIC_AUTH_USER=admin \
#        BASIC_AUTH_PASS=change-me \
#        ./setup-ssl.sh voice.example.com you@example.com /opt/VoiceStudio
#
# =============================================================

# Required by the VoiceStudio compose file
OMNIVOICE_API_KEY=replace-me-with-a-long-random-string

# --- Local dev only ---
# VOICESTUDIO_SESSION=voicestudio

# --- Server only (setup-ssl.sh) ---
# BASIC_AUTH_USER=admin
# BASIC_AUTH_PASS=change-me
# PROFILE=cpu          # cpu | gpu | rocm
# UI_PORT=3900         # loopback port VoiceStudio binds to
EOL

# ===============================================================
# README.md
# ===============================================================
cat << 'EOL' > README.md
# VoiceStudio — launcher (local + server)

Two modes:

| Mode | Where | How | Auth |
|------|-------|-----|------|
| **Local dev** | Your laptop | `./start.sh cpu` → tmux session | none (loopback only) |
| **Server** | Ubuntu VPS | `sudo ./setup-ssl.sh <domain> <email>` | HTTP Basic Auth + HTTPS |

The server mode is what this README is mostly about, because that is
where the sharp edges are.

---

## TL;DR for a fresh Ubuntu box
# 1. Clone VoiceStudio
sudo mkdir -p /opt && cd /opt
sudo git clone https://github.com/debpalash/VoiceStudio.git
cd VoiceStudio

# 2. Make sure docker + compose plugin are installed
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker

# 3. Drop the launcher folder next to the repo
sudo cp -r /path/to/voicestudio-tmux /opt/voicestudio-tmux
cd /opt/voicestudio-tmux

# 4. Point voice.example.com at this box, then:
sudo BASIC_AUTH_USER=admin \
     BASIC_AUTH_PASS="$(openssl rand -base64 24)" \
     ./setup-ssl.sh voice.example.com you@example.com /opt/VoiceStudio

The script prints the password once. Save it.
What setup-ssl.sh does
    Installs nginx, certbot, python3-certbot-nginx, apache2-utils
    Opens 80/tcp and 443/tcp in ufw if present
    Ensures /opt/VoiceStudio/.env exists with an OMNIVOICE_API_KEY
    Writes /etc/systemd/system/voicestudio.service and enables it
    Writes /etc/nginx/.htpasswd-voicestudio from BASIC_AUTH_USER/BASIC_AUTH_PASS
    Writes /etc/nginx/sites-available/voicestudio.conf (basic auth + long TTS timeouts)
    Runs certbot certonly --standalone for the domain, then injects the cert paths
    Installs a renewal hook that reloads nginx on cert refresh
    Starts voicestudio.service and restarts nginx
    Prints the URL and credentials

Why the cert is issued before nginx starts with 443

Nginx refuses to start if an ssl_certificate path points at a file that
doesn't exist. So the script:
    Writes the server block without the 443 listener enable
    Starts nginx on :80 only (so the webroot challenge path works)
    Obtains the cert via certbot --standalone (temporarily stops nginx)
    Injects the cert paths into the 443 block
    Restarts nginx

This ordering is why you should not "just run certbot --nginx" on top of
this — it would fight with the script.
Firewall notes

If ufw is active and you have a restrictive default policy, confirm
80/tcp and 443/tcp are allowed. The script does this, but if you have
an upstream firewall (cloud provider security group, home router), you
must open them there too. Certbot will fail silently-ish if port 80 is
not reachable from the public internet.
Auth

The only thing between the internet and your GPU is HTTP Basic Auth. The
credentials live in /etc/nginx/.htpasswd-voicestudio (bcrypt-hashed).
There is no session, no lockout, no rate limit. That is deliberate — this
is a single-user personal deployment, not a service.

To rotate the password:
sudo BASIC_AUTH_USER=admin BASIC_AUTH_PASS=newpassword \
     ./setup-ssl.sh voice.example.com you@example.com /opt/VoiceStudio

The script will rewrite the htpasswd entry and reload nginx.

To add a second user:
sudo htpasswd /etc/nginx/.htpasswd-voicestudio alice
sudo systemctl reload nginx

Management
# Stack
sudo systemctl status voicestudio
sudo systemctl restart voicestudio
sudo systemctl stop voicestudio
sudo journalctl -u voicestudio -f

# Nginx
sudo nginx -t
sudo systemctl reload nginx

# Cert
sudo certbot renew --dry-run
sudo ls /etc/letsencrypt/live/<domain>/

# Logs from the container
sudo docker compose -f /opt/VoiceStudio/deploy/docker-compose.yml logs -f

First boot

The compose file downloads ~4 GB of models the first time. The
healthcheck has a start period of 120s (CPU) / 180s (GPU/ROCm). Until it
passes, the UI returns 502 through nginx. That is expected. Watch:
bash

sudo journalctl -u voicestudio -f

Things that will bite you

DNS not pointed at the box → certbot fails, nginx serves nothing
useful. Fix the A-record first.

Port 80 blocked upstream → certbot HTTP-01 fails. Open it in the
cloud firewall / router, not just ufw.

proxy_read_timeout too low → long TTS jobs return 504. The config
sets it to 600s. If you still see 504s, raise it further.

client_max_body_size too low → voice sample uploads fail with

The config sets it to 200M.

Basic auth over HTTP → password leaks on every request. The script
forces the HTTP block to 301 to HTTPS. Do not undo that.

Local dev (unchanged)

cd /path/to/VoiceStudio
export OMNIVOICE_API_KEY="$(openssl rand -hex 32)"
/path/to/voicestudio-tmux/start.sh cpu

Tmux session voicestudio with three windows: studio, logs, shell.
Detach with Ctrl-b d, re-attach with tmux attach -t voicestudio.
EOL

# ===============================================================
# LICENSE.md
# ===============================================================
cat << EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EOL


# ===============================================================
# Packaging 
# ===============================================================
cd ..

TAR_FILE="EXTNAME.tar.gz"rm−f"EXTNAME.tar.gz"rm−f"TAR_FILE"

tar --exclude="TARFILE"−czf"TARF​ILE"−czf"TAR_FILE" "$EXTNAME"

if [ -f "TARFILE"];thenecho""echo−e"TARF​ILE"];thenecho""echo−e"{GREEN}✅ Created: TARFILE(TARF​ILE((du -h "TARFILE"∣cut−f1))TARF​ILE"∣cut−f1)){NC}"
Try to move to ~/Downloads if it exists, otherwise leave alongside

if [ -d "HOME/Downloads"];thenmv"HOME/Downloads"];thenmv"TAR_FILE" "HOME/Downloads/HOME/Downloads/TAR_FILE"
echo -e "GREEN✅Archivemovedto:GREEN✅Archivemovedto:HOME/Downloads/TARFILETARF​ILE{NC}"
fi
fi

echo ""
echo -e "GREEN✨FILES:GREEN✨FILES:{NC}"
echo -e " • EXTNAME/—sourcefolder"echo−e"•EXTNAME/—sourcefolder"echo−e"•{TAR_FILE} — packaged launcher"
echo ""
echo -e "CYAN🚀INSTALL(localdev):CYAN🚀INSTALL(localdev):{NC}"
echo -e " • tar -xzf TARFILE"echo−e"•cdTARF​ILE"echo−e"•cd{EXTNAME}"
echo -e " • ./start.sh cpu"
echo ""
echo -e "CYAN🚀INSTALL(Ubuntuserver,HTTPS):CYAN🚀INSTALL(Ubuntuserver,HTTPS):{NC}"
echo -e " • tar -xzf TARFILE"echo−e"•cdTARF​ILE"echo−e"•cd{EXTNAME}"
echo -e " • sudo ./setup-ssl.sh voice.example.com you@example.com /opt/VoiceStudio"
echo ""
echo -e "YELLOW⚙®LAUNCHERFILES:YELLOW⚙R◯LAUNCHERFILES:{NC}"
echo -e " • voicestudio-tmux.sh — local tmux launcher"
echo -e " • start.sh — local convenience wrapper"
echo -e " • stop.sh — local teardown"
echo -e " • setup-ssl.sh — server install (SSL + auth + systemd)"
echo -e " • templates/ — nginx + systemd templates"
echo ""
echo -e "YELLOW⚠®REQUIRES:YELLOW⚠R◯REQUIRES:{NC}"
echo -e " • tmux, docker, docker compose plugin"
echo -e " • The VoiceStudio repo with deploy/docker-compose.yml"
echo -e " • OMNIVOICE_API_KEY (generated for you if missing)"
echo -e " • For server mode: a domain A-record pointing at the box"
echo ""
echo -e "YELLOW📋PROFILES:YELLOW📋PROFILES:{NC}"
echo -e " • cpu, gpu, rocm, worker-gpu, worker-rocm"
echo ""
echo -e "GREEN✅Local:./start.shcpuGREEN✅Local:./start.shcpu{NC}"
echo -e "GREEN✅Server:sudo./setup−ssl.sh<domain><email><repo−path>GREEN✅Server:sudo./setup−ssl.sh<domain><email><repo−path>{NC}"


# ---

# ## What changed vs. your v1, specifically

# | Item | v1 | v2 |
# |---|---|---|
# | Packaging block | Corrupted (`TAR_FILE="EXTNAME.tar.gz"rm−f...`) | Fixed, uses proper `$` vars |
# | Server mode | None | `setup-ssl.sh` + systemd + nginx |
# | Auth | None | HTTP Basic via `/etc/nginx/.htpasswd-voicestudio` |
# | SSL | None | `certbot --standalone` + renewal hook |
# | Templates | None | `templates/voicestudio.service`, `templates/nginx-voicestudio.conf` |
# | README | Local only | Local + server + "things that will bite you" |
# | `.env.example` | `OMNIVOICE_API_KEY` only | Adds server vars |
# | Local dev | Unchanged | Unchanged (tmux still works) |

# ---

# ## Before you run it — the two-minute sanity check

# 1. **Docker + compose plugin installed?** `docker compose version` should print something.
# 2. **Domain A-record points at the box?** `dig +short voice.example.com` should return the box's public IP.
# 3. **Port 80 reachable from the internet?** If you're behind a home router, forward it. If it's a cloud VPS, check the security group / firewall. `ufw` alone isn't enough.
# 4. **You have the VoiceStudio repo cloned** with `deploy/docker-compose.yml` present.
# 5. **You know which profile** — `cpu` for a normal VPS, `gpu`/`rocm` only if you have the hardware passthrough set up.

# If all five pass, `sudo ./setup-ssl.sh voice.example.com you@example.com /opt/VoiceStudio` should be a one-shot.

# ---

# ## The honest caveats, one more time

# - **Basic auth is the whole security model.** No rate limit, no lockout, no 2FA. If your password leaks, someone is using your GPU. Rotate it by re-running `setup-ssl.sh` with a new `BASIC_AUTH_PASS`.
# - **The certbot ordering is deliberate.** Don't run `certbot --nginx` manually on top of this — it will fight with the script's server block. If you need to re-issue, delete `/etc/letsencrypt/live/<domain>/` and re-run `setup-ssl.sh`.
# - **Port 80 must be reachable for the HTTP-01 challenge.** If you can't open 80, you need DNS-01 (not covered here — different certbot plugin).
# - **First boot is slow.** 4GB of models. Be patient. 502s for the first ~2 minutes are expected.

# Good luck. If the certbot step fails, paste the output and I'll tell you which of the five preflight checks is lying.