#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Default values
DEFAULT_DOMAIN="example.com"
DEFAULT_DATA_DIR="/opt/stack"

echo "========================================="
echo "  Homelab Stack Setup"
echo "========================================="
echo

# Check if already configured
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    warn "Configuration already exists (.env found)"
    read -p "Overwrite existing configuration? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# Prompt for configuration
read -p "Enter your domain [$DEFAULT_DOMAIN]: " DOMAIN
DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}

read -p "Enter data directory [$DEFAULT_DATA_DIR]: " DATA_DIR
DATA_DIR=${DATA_DIR:-$DEFAULT_DATA_DIR}

echo
echo "Select services to enable:"
read -p "  Enable Nextcloud? [Y/n] " -n 1 -r ENABLE_NEXTCLOUD
echo
read -p "  Enable UISP? [Y/n] " -n 1 -r ENABLE_UISP
echo
read -p "  Enable Jitsi? [Y/n] " -n 1 -r ENABLE_JITSI
echo

# Build COMPOSE_PROFILES
PROFILES=""
[[ ! $ENABLE_NEXTCLOUD =~ ^[Nn]$ ]] && PROFILES="${PROFILES}nextcloud,"
[[ ! $ENABLE_UISP =~ ^[Nn]$ ]] && PROFILES="${PROFILES}uisp,"
[[ ! $ENABLE_JITSI =~ ^[Nn]$ ]] && PROFILES="${PROFILES}jitsi,"
PROFILES=${PROFILES%,}  # Remove trailing comma

# Generate secrets
generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
}

info "Generating secrets..."
MYSQL_PASSWORD=$(generate_secret)
MYSQL_ROOT_PASSWORD=$(generate_secret)
JICOFO_AUTH_PASSWORD=$(generate_secret)
JVB_AUTH_PASSWORD=$(generate_secret)

# Create root .env
info "Creating root .env..."
cat > "$SCRIPT_DIR/.env" << EOF
# Base domain for all services
BASE_DOMAIN=$DOMAIN

# Data directory for all persistent storage
DATA_DIR=$DATA_DIR

# Services to enable (comma-separated: nextcloud,uisp,jitsi)
# Caddy always runs as it's the reverse proxy
COMPOSE_PROFILES=$PROFILES
EOF

# Create nextcloud .env files
if [[ $PROFILES == *"nextcloud"* ]]; then
    info "Creating nextcloud/.env..."
    sed "s/\${BASE_DOMAIN}/$DOMAIN/g" "$SCRIPT_DIR/nextcloud/.env.example" > "$SCRIPT_DIR/nextcloud/.env"

    info "Creating nextcloud/.env.secrets..."
    cat > "$SCRIPT_DIR/nextcloud/.env.secrets" << EOF
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
EOF
fi

# Create jitsi .env files
if [[ $PROFILES == *"jitsi"* ]]; then
    info "Creating jitsi-deploy/.env..."
    sed "s/\${BASE_DOMAIN}/$DOMAIN/g" "$SCRIPT_DIR/jitsi-deploy/.env.example" > "$SCRIPT_DIR/jitsi-deploy/.env"

    info "Creating jitsi-deploy/.env.secrets..."
    cat > "$SCRIPT_DIR/jitsi-deploy/.env.secrets" << EOF
JICOFO_AUTH_USER=focus
JVB_AUTH_USER=jvb
JICOFO_AUTH_PASSWORD=$JICOFO_AUTH_PASSWORD
JVB_AUTH_PASSWORD=$JVB_AUTH_PASSWORD
EOF
fi

# Create data directories
info "Creating data directories in $DATA_DIR..."
sudo mkdir -p "$DATA_DIR/caddy/data"
sudo mkdir -p "$DATA_DIR/caddy/config"

if [[ $PROFILES == *"nextcloud"* ]]; then
    sudo mkdir -p "$DATA_DIR/nextcloud/html"
    sudo mkdir -p "$DATA_DIR/nextcloud/data"
    sudo mkdir -p "$DATA_DIR/nextcloud/db"
    sudo mkdir -p "$DATA_DIR/nextcloud/redis"
fi

if [[ $PROFILES == *"uisp"* ]]; then
    sudo mkdir -p "$DATA_DIR/uisp/data"
    sudo mkdir -p "$DATA_DIR/uisp/logs"
fi

if [[ $PROFILES == *"jitsi"* ]]; then
    sudo mkdir -p "$DATA_DIR/jitsi/web"
    sudo mkdir -p "$DATA_DIR/jitsi/web-public"
    sudo mkdir -p "$DATA_DIR/jitsi/prosody"
    sudo mkdir -p "$DATA_DIR/jitsi/jicofo"
    sudo mkdir -p "$DATA_DIR/jitsi/jvb"
    sudo mkdir -p "$DATA_DIR/jitsi/branding"
fi

# Copy Caddyfile
info "Copying Caddyfile to $DATA_DIR/caddy/..."
sudo cp "$SCRIPT_DIR/caddy/Caddyfile" "$DATA_DIR/caddy/Caddyfile"

# Copy Jitsi branding
if [[ $PROFILES == *"jitsi"* ]]; then
    info "Copying Jitsi branding to $DATA_DIR/jitsi/branding/..."
    sudo cp "$SCRIPT_DIR/jitsi-deploy/branding/watermark.svg" "$DATA_DIR/jitsi/branding/watermark.svg"
fi

# Set permissions
info "Setting permissions..."

# Caddy: runs as root, config files read-only
sudo chown -R root:root "$DATA_DIR/caddy"
sudo chmod 755 "$DATA_DIR/caddy"
sudo chmod 644 "$DATA_DIR/caddy/Caddyfile"
sudo chmod 755 "$DATA_DIR/caddy/data" "$DATA_DIR/caddy/config"

if [[ $PROFILES == *"nextcloud"* ]]; then
    # Nextcloud: runs as www-data (33:33)
    sudo chown -R 33:33 "$DATA_DIR/nextcloud/html"
    sudo chown -R 33:33 "$DATA_DIR/nextcloud/data"
    sudo chmod 750 "$DATA_DIR/nextcloud/html" "$DATA_DIR/nextcloud/data"

    # MariaDB: runs as mysql (999:999)
    sudo chown -R 999:999 "$DATA_DIR/nextcloud/db"
    sudo chmod 750 "$DATA_DIR/nextcloud/db"

    # Redis: runs as redis (999:999)
    sudo chown -R 999:999 "$DATA_DIR/nextcloud/redis"
    sudo chmod 750 "$DATA_DIR/nextcloud/redis"

    # Secret files: restrict access
    chmod 600 "$SCRIPT_DIR/nextcloud/.env.secrets"
fi

if [[ $PROFILES == *"uisp"* ]]; then
    # UISP: runs as root
    sudo chown -R root:root "$DATA_DIR/uisp"
    sudo chmod 755 "$DATA_DIR/uisp/data" "$DATA_DIR/uisp/logs"
fi

if [[ $PROFILES == *"jitsi"* ]]; then
    # Jitsi: runs as root
    sudo chown -R root:root "$DATA_DIR/jitsi"
    sudo chmod 755 "$DATA_DIR/jitsi/web" "$DATA_DIR/jitsi/web-public"
    sudo chmod 755 "$DATA_DIR/jitsi/prosody" "$DATA_DIR/jitsi/jicofo" "$DATA_DIR/jitsi/jvb"
    sudo chmod 755 "$DATA_DIR/jitsi/branding"
    sudo chmod 644 "$DATA_DIR/jitsi/branding/watermark.svg"

    # Secret files: restrict access
    chmod 600 "$SCRIPT_DIR/jitsi-deploy/.env.secrets"
fi

echo
echo "========================================="
echo -e "${GREEN}  Setup complete!${NC}"
echo "========================================="
echo
echo "Configuration summary:"
echo "  Domain:     $DOMAIN"
echo "  Data dir:   $DATA_DIR"
echo "  Services:   $PROFILES"
echo
echo "Service URLs:"
[[ $PROFILES == *"nextcloud"* ]] && echo "  Nextcloud:  https://nextcloud.$DOMAIN"
[[ $PROFILES == *"uisp"* ]] && echo "  UISP:       https://uisp.$DOMAIN"
[[ $PROFILES == *"jitsi"* ]] && echo "  Jitsi:      https://meet.$DOMAIN"
[[ $PROFILES == *"jitsi"* ]] && echo "  Jitsi Admin: https://adm.meet.$DOMAIN"
echo
echo "Next steps:"
echo "  1. Review generated config files"
[[ $PROFILES == *"jitsi"* ]] && echo "  2. Customize Jitsi logo: $DATA_DIR/jitsi/branding/watermark.svg"
echo "  3. Start the stack: docker compose up -d"
echo "  4. Check logs: docker compose logs -f"
echo
