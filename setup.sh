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

# Management subnet default for UISP/Unifi GUI (empty means "no restriction")
DEFAULT_MGMT_SUBNET=""

echo "========================================="
echo "  Homelab Stack Setup"
echo "========================================="
echo

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    info "Using existing $SCRIPT_DIR/.env (re-run mode)"
    # set -a so sourced vars are exported and visible to docker compose.
    set -a
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
    set +a
    DOMAIN="$BASE_DOMAIN"
    PROFILES="$COMPOSE_PROFILES"
    DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
    MGMT_ALLOWED_SUBNET="${MGMT_ALLOWED_SUBNET:-}"
else
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
    read -p "  Enable UniFi Controller? [Y/n] " -n 1 -r ENABLE_UNIFI
    echo

    PROFILES=""
    [[ ! $ENABLE_NEXTCLOUD =~ ^[Nn]$ ]] && PROFILES="${PROFILES}nextcloud,"
    [[ ! $ENABLE_UISP =~ ^[Nn]$ ]] && PROFILES="${PROFILES}uisp,"
    [[ ! $ENABLE_JITSI =~ ^[Nn]$ ]] && PROFILES="${PROFILES}jitsi,"
    [[ ! $ENABLE_UNIFI =~ ^[Nn]$ ]] && PROFILES="${PROFILES}unifi,"
    PROFILES=${PROFILES%,}

    MGMT_ALLOWED_SUBNET="$DEFAULT_MGMT_SUBNET"
    if [[ $PROFILES == *"uisp"* ]] || [[ $PROFILES == *"unifi"* ]]; then
        echo
        echo "Management GUI access restriction (recommended):"
        echo "  Provide ONE allowed subnet in CIDR (example: 192.168.2.0/24 or 172.16.1.0/24)."
        echo "  Leave blank to skip restriction (NOT recommended if exposed externally)."
        read -p "  Allowed subnet for UISP/UniFi GUIs [$DEFAULT_MGMT_SUBNET]: " MGMT_ALLOWED_SUBNET
        MGMT_ALLOWED_SUBNET=${MGMT_ALLOWED_SUBNET:-$DEFAULT_MGMT_SUBNET}

        if [[ -n "$MGMT_ALLOWED_SUBNET" ]] && [[ ! "$MGMT_ALLOWED_SUBNET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
            error "Invalid CIDR format: '$MGMT_ALLOWED_SUBNET' (expected e.g. 192.168.2.0/24)"
        fi
    fi
fi

# Secret generation
generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
}

prompt_secret() {
    local name="$1"
    local var_name="$2"
    local value=""

    read -p "  $name - generate random? [Y/n] " -n 1 -r generate
    echo
    if [[ $generate =~ ^[Nn]$ ]]; then
        read -p "    Enter $name: " -s value
        echo
        while [[ -z "$value" ]]; do
            echo "    Password cannot be empty"
            read -p "    Enter $name: " -s value
            echo
        done
    else
        value=$(generate_secret)
        echo "    (generated)"
    fi
    printf -v "$var_name" '%s' "$value"
}

if [[ $PROFILES == *"nextcloud"* ]] && [[ ! -f "$SCRIPT_DIR/nextcloud/.env.secrets" ]]; then
    echo
    echo "Configure secrets:"
    echo
    echo "Nextcloud/MariaDB:"
    prompt_secret "MySQL password" MYSQL_PASSWORD
    prompt_secret "MySQL root password" MYSQL_ROOT_PASSWORD
fi

if [[ $PROFILES == *"jitsi"* ]] && [[ ! -f "$SCRIPT_DIR/jitsi-deploy/.env.secrets" ]]; then
    echo
    echo "Jitsi:"
    prompt_secret "Jicofo auth password" JICOFO_AUTH_PASSWORD
    prompt_secret "JVB auth password" JVB_AUTH_PASSWORD
fi

if [[ $PROFILES == *"training"* ]] && [[ ! -f "$SCRIPT_DIR/training/.env.secrets" ]]; then
    info "Generating training/.env.secrets..."
    TRAINING_SECRET_KEY=$(openssl rand -hex 32)
    TRAINING_GARMIN_KEY=$(python3 -c "import os, base64; print(base64.b64encode(os.urandom(32)).decode())")
    TRAINING_PG_PASSWORD=$(generate_secret)
    mkdir -p "$SCRIPT_DIR/training"
    cat > "$SCRIPT_DIR/training/.env.secrets" << EOF
POSTGRES_USER=track
POSTGRES_PASSWORD=$TRAINING_PG_PASSWORD
POSTGRES_DB=track
DATABASE_URL=postgresql+psycopg://track:$TRAINING_PG_PASSWORD@db:5432/track
SECRET_KEY=$TRAINING_SECRET_KEY
GARMIN_CREDS_KEY=$TRAINING_GARMIN_KEY
EOF
    chmod 600 "$SCRIPT_DIR/training/.env.secrets"
fi

if [[ $PROFILES == *"zigbee2mqtt"* ]] && [[ ! -f "$SCRIPT_DIR/zigbee2mqtt/.env.secrets" ]]; then
    info "Generating zigbee2mqtt/.env.secrets..."
    MQTT_HA_PASSWORD=$(generate_secret)
    MQTT_Z2M_PASSWORD=$(generate_secret)
    mkdir -p "$SCRIPT_DIR/zigbee2mqtt"
    cat > "$SCRIPT_DIR/zigbee2mqtt/.env.secrets" << EOF
MQTT_HA_USER=homeassistant
MQTT_HA_PASSWORD=$MQTT_HA_PASSWORD
MQTT_Z2M_USER=zigbee2mqtt
MQTT_Z2M_PASSWORD=$MQTT_Z2M_PASSWORD
EOF
    chmod 600 "$SCRIPT_DIR/zigbee2mqtt/.env.secrets"
fi

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    info "Creating root .env..."

    {
        cat << EOF
# Base domain for all services
BASE_DOMAIN=$DOMAIN

# Data directory for all persistent storage
DATA_DIR=$DATA_DIR

# Services to enable (comma-separated: nextcloud,uisp,jitsi,unifi)
# Caddy always runs as it's the reverse proxy
COMPOSE_PROFILES=$PROFILES
EOF

        if [[ $PROFILES == *"uisp"* ]] || [[ $PROFILES == *"unifi"* ]]; then
            cat << EOF

# Restrict management GUIs (UISP + UniFi) to a single subnet (CIDR)
# Example: 192.168.2.0/24
MGMT_ALLOWED_SUBNET=$MGMT_ALLOWED_SUBNET
EOF
        fi
    } > "$SCRIPT_DIR/.env"
fi

if [[ $PROFILES == *"nextcloud"* ]]; then
    if [[ ! -f "$SCRIPT_DIR/nextcloud/.env" ]]; then
        info "Creating nextcloud/.env..."
        sed "s/\${BASE_DOMAIN}/$DOMAIN/g" "$SCRIPT_DIR/nextcloud/.env.example" > "$SCRIPT_DIR/nextcloud/.env"
    fi

    if [[ ! -f "$SCRIPT_DIR/nextcloud/.env.secrets" ]]; then
        info "Creating nextcloud/.env.secrets..."
        cat > "$SCRIPT_DIR/nextcloud/.env.secrets" << EOF
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
EOF
    fi
fi

if [[ $PROFILES == *"jitsi"* ]]; then
    if [[ ! -f "$SCRIPT_DIR/jitsi-deploy/.env" ]]; then
        info "Creating jitsi-deploy/.env..."
        sed "s/\${BASE_DOMAIN}/$DOMAIN/g" "$SCRIPT_DIR/jitsi-deploy/.env.example" > "$SCRIPT_DIR/jitsi-deploy/.env"
    fi

    if [[ ! -f "$SCRIPT_DIR/jitsi-deploy/.env.secrets" ]]; then
        info "Creating jitsi-deploy/.env.secrets..."
        cat > "$SCRIPT_DIR/jitsi-deploy/.env.secrets" << EOF
JICOFO_AUTH_USER=focus
JVB_AUTH_USER=jvb
JICOFO_AUTH_PASSWORD=$JICOFO_AUTH_PASSWORD
JVB_AUTH_PASSWORD=$JVB_AUTH_PASSWORD
EOF
    fi
fi

# Create data directories
info "Creating data directories in $DATA_DIR..."
sudo mkdir -p "$DATA_DIR/caddy/data"
sudo mkdir -p "$DATA_DIR/caddy/config"
sudo mkdir -p "$DATA_DIR/caddy/files"

if [[ $PROFILES == *"nextcloud"* ]]; then
    if [[ -d "$DATA_DIR/nextcloud/html" ]]; then
        info "Nextcloud html directory exists, skipping (existing installation)"
    else
        sudo mkdir -p "$DATA_DIR/nextcloud/html"
        sudo mkdir -p "$DATA_DIR/nextcloud/data"
        sudo mkdir -p "$DATA_DIR/nextcloud/db"
        sudo mkdir -p "$DATA_DIR/nextcloud/redis"
    fi
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

if [[ $PROFILES == *"unifi"* ]]; then
    sudo mkdir -p "$DATA_DIR/unifi/data"
fi

if [[ $PROFILES == *"cloudflared"* ]]; then
    sudo mkdir -p "$DATA_DIR/cloudflared"
    # 65532 is the nonroot UID used inside the cloudflared container.
    # The daemon needs to read cert.pem, config.yml and the credentials JSON
    # at runtime, so the host dir must be owned by that UID.
    sudo chown -R 65532:65532 "$DATA_DIR/cloudflared"
    sudo chmod 700 "$DATA_DIR/cloudflared"
fi

if [[ $PROFILES == *"finance"* ]]; then
    sudo mkdir -p "$DATA_DIR/finance/data"
    # Finance runs as root inside the container; keep host ownership matching.
    sudo chown -R root:root "$DATA_DIR/finance"
    sudo chmod 755 "$DATA_DIR/finance"
fi

if [[ $PROFILES == *"training"* ]]; then
    sudo mkdir -p "$DATA_DIR/training/db" "$DATA_DIR/training/uploads"
    # postgres official image runs as uid 999, api image as uid 10001.
    sudo chown -R 999:999 "$DATA_DIR/training/db"
    sudo chown -R 10001:10001 "$DATA_DIR/training/uploads"
    sudo chmod 750 "$DATA_DIR/training/db" "$DATA_DIR/training/uploads"
fi

if [[ $PROFILES == *"homeassistant"* ]]; then
    sudo mkdir -p "$DATA_DIR/homeassistant/config"
    # HA runs as root inside the container; keep host ownership matching.
    sudo chown -R root:root "$DATA_DIR/homeassistant"
    sudo chmod 755 "$DATA_DIR/homeassistant"

    # Pre-populate configuration.yaml so HA trusts the Caddy reverse proxy
    # from first boot. Only created when absent — existing configs are
    # left alone so manual customisation is preserved.
    if [[ ! -f "$DATA_DIR/homeassistant/config/configuration.yaml" ]]; then
        sudo tee "$DATA_DIR/homeassistant/config/configuration.yaml" > /dev/null <<'EOF'
# Loads default set of integrations. Do not remove.
default_config:

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.22.0.0/16
EOF
    fi
fi

if [[ $PROFILES == *"zigbee2mqtt"* ]]; then
    sudo mkdir -p "$DATA_DIR/mosquitto/config" "$DATA_DIR/mosquitto/data"
    sudo mkdir -p "$DATA_DIR/zigbee2mqtt/data"
    # mosquitto runs as uid 1883 inside the official image.
    sudo chown -R 1883:1883 "$DATA_DIR/mosquitto"
    sudo chmod 755 "$DATA_DIR/mosquitto"
    # zigbee2mqtt runs as root inside the container.
    sudo chown -R root:root "$DATA_DIR/zigbee2mqtt"
    sudo chmod 755 "$DATA_DIR/zigbee2mqtt"

    # Mosquitto password file (hashed). The mosquitto image's default
    # entrypoint intercepts shell-style commands, so we override the
    # entrypoint to mosquitto_passwd directly and call it once per user.
    # The bind-mounted /m gives us the resulting file on the host. Args
    # are -c -b separated; mosquitto 2.1.2's parser silently rejects
    # the combined -bc form and prints its help text.
    if [[ ! -f "$DATA_DIR/mosquitto/config/passwd" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/zigbee2mqtt/.env.secrets"
        info "Generating mosquitto password file..."
        docker run --rm \
            -v "$DATA_DIR/mosquitto/config:/m" \
            --entrypoint mosquitto_passwd \
            eclipse-mosquitto:2 \
            -c -b /m/passwd "$MQTT_HA_USER" "$MQTT_HA_PASSWORD"
        docker run --rm \
            -v "$DATA_DIR/mosquitto/config:/m" \
            --entrypoint mosquitto_passwd \
            eclipse-mosquitto:2 \
            -b /m/passwd "$MQTT_Z2M_USER" "$MQTT_Z2M_PASSWORD"
        sudo chown 1883:1883 "$DATA_DIR/mosquitto/config/passwd"
        sudo chmod 600 "$DATA_DIR/mosquitto/config/passwd"
    fi

    # Mosquitto config
    if [[ ! -f "$DATA_DIR/mosquitto/config/mosquitto.conf" ]]; then
        sudo tee "$DATA_DIR/mosquitto/config/mosquitto.conf" > /dev/null <<'EOF'
listener 1883
persistence true
persistence_location /mosquitto/data/
log_dest stdout
allow_anonymous false
password_file /mosquitto/config/passwd
EOF
        sudo chown 1883:1883 "$DATA_DIR/mosquitto/config/mosquitto.conf"
        sudo chmod 644 "$DATA_DIR/mosquitto/config/mosquitto.conf"
    fi

    # Zigbee2MQTT configuration.yaml. Talks to mosquitto over docker DNS
    # and to the Sonoff Dongle Max over LAN serial-over-IP. Existing
    # config is left untouched so manual edits survive setup re-runs.
    if [[ ! -f "$DATA_DIR/zigbee2mqtt/data/configuration.yaml" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/zigbee2mqtt/.env.secrets"
        sudo tee "$DATA_DIR/zigbee2mqtt/data/configuration.yaml" > /dev/null <<EOF
homeassistant: true
permit_join: false
mqtt:
  server: mqtt://mosquitto
  user: $MQTT_Z2M_USER
  password: $MQTT_Z2M_PASSWORD
serial:
  port: tcp://192.168.22.199:6638
  adapter: ember
frontend:
  port: 8080
  host: 0.0.0.0
advanced:
  network_key: GENERATE
EOF
        sudo chmod 600 "$DATA_DIR/zigbee2mqtt/data/configuration.yaml"
    fi
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
# files/ is the public_html drop — owned by the invoking user so scp/mkdir
# work without sudo. Caddy mounts it read-only so ownership only needs to
# let the user write.
sudo chown -R "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$DATA_DIR/caddy/files"
sudo chmod 755 "$DATA_DIR/caddy/files"

if [[ $PROFILES == *"nextcloud"* ]]; then
    # Secret files: restrict access
    chmod 600 "$SCRIPT_DIR/nextcloud/.env.secrets"

    # Only set permissions for fresh installs (skip if config.php exists)
    if [[ ! -f "$DATA_DIR/nextcloud/html/config/config.php" ]]; then
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
    else
        info "Nextcloud config.php exists, skipping permission changes"
    fi
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

if [[ $PROFILES == *"unifi"* ]]; then
    # UniFi: runs as unifi user (999:999)
    sudo chown -R 999:999 "$DATA_DIR/unifi/data"
    sudo chmod 750 "$DATA_DIR/unifi/data"
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
[[ -n "$MGMT_ALLOWED_SUBNET" ]] && echo "  Mgmt subnet: $MGMT_ALLOWED_SUBNET"
echo
echo "Service URLs:"
[[ $PROFILES == *"nextcloud"* ]] && echo "  Nextcloud:  https://nextcloud.$DOMAIN"
[[ $PROFILES == *"uisp"* ]] && echo "  UISP:       https://uisp.$DOMAIN"
[[ $PROFILES == *"jitsi"* ]] && echo "  Jitsi:      https://meet.$DOMAIN"
[[ $PROFILES == *"jitsi"* ]] && echo "  Jitsi Admin: https://adm.meet.$DOMAIN"
[[ $PROFILES == *"unifi"* ]] && echo "  UniFi:      https://unifi.$DOMAIN"
echo "  Files:      https://files.$PUBLIC_DOMAIN"
echo
echo "Next steps:"
echo "  1. Review generated config files"
[[ $PROFILES == *"jitsi"* ]] && echo "  2. Customize Jitsi logo: $DATA_DIR/jitsi/branding/watermark.svg"
echo "  3. Start the stack: docker compose up -d"
echo "  4. Check logs: docker compose logs -f"
echo
[[ $PROFILES == *"nextcloud"* ]] && echo "Migrating existing Nextcloud? See README.md for steps."
echo

# ----------------------------
# Firewall (UFW) setup
# ----------------------------
setup_firewall() {
  local BASE_RULES=(
    "22/tcp:SSH"
    "80/tcp:HTTP"
    "443/tcp:HTTPS"
  )
  local RULES_NEXTCLOUD=()
  local RULES_UISP=(
    "2055/udp:NetFlow/UDP 2055"
  )
  local RULES_JITSI=(
    "10000/udp:Jitsi JVB Media"
  )
  local RULES_UNIFI=(
    "3478/udp:UniFi STUN"
    "10001/udp:UniFi Device Discovery"
    "8080/tcp:UniFi Inform (Adoption)"
  )

  local DESIRED_RULES=()
  DESIRED_RULES+=( "${BASE_RULES[@]}" )

  IFS=',' read -r -a profiles_arr <<< "$PROFILES"
  local p
  for p in "${profiles_arr[@]}"; do
    case "$p" in
      nextcloud) DESIRED_RULES+=( "${RULES_NEXTCLOUD[@]}" ) ;;
      uisp)      DESIRED_RULES+=( "${RULES_UISP[@]}" ) ;;
      jitsi)     DESIRED_RULES+=( "${RULES_JITSI[@]}" ) ;;
      unifi)     DESIRED_RULES+=( "${RULES_UNIFI[@]}" ) ;;
      "")        ;;
      *)         warn "Unknown profile '$p'; ignoring for firewall rules." ;;
    esac
  done

  local seen="" out=() rule portproto
  for rule in "${DESIRED_RULES[@]}"; do
    portproto="${rule%%:*}"
    if [[ ",$seen," != *",$portproto,"* ]]; then
      out+=( "$rule" )
      seen="${seen},${portproto}"
    fi
  done
  DESIRED_RULES=( "${out[@]}" )

  info "Desired firewall allow rules:"
  for r in "${DESIRED_RULES[@]}"; do
    echo "  - ${r%%:*}  (${r##*:})"
  done
  echo

  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed."
    read -p "Install ufw now via apt-get? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      sudo apt-get update
      sudo apt-get install -y ufw
      info "ufw installed."
    else
      warn "ufw is required for firewall setup. Skipping."
      return 0
    fi
  else
    info "ufw is installed: $(sudo ufw --version | head -n1 || true)"
  fi

  local status_verbose
  status_verbose="$(sudo ufw status verbose 2>/dev/null || true)"

  local existing desired
  existing="$(awk '
    BEGIN{IGNORECASE=1}
    NR>2 && $1 !~ /^(Status:|To)$/ {
      to=$1; action=$2
      if (action != "ALLOW") next
      split(to, a, "/")
      port=a[1]; proto=a[2]
      if (port ~ /^[0-9]+$/ && proto ~ /^(tcp|udp)$/)
        print proto ":" port
    }
  ' <<<"$status_verbose" | sort -u)"

  desired="$(for rule in "${DESIRED_RULES[@]}"; do
    portproto="${rule%%:*}"
    port="${portproto%%/*}"
    proto="${portproto##*/}"
    echo "${proto}:${port}"
  done | sort -u)"

  local incoming outgoing
  read -r incoming outgoing < <(awk -F': ' '/Default: /{print $2}' <<<"$status_verbose" \
    | awk -F', ' '{print $1, $2}' | xargs || true)

  local defaults_ok=0
  if [[ "${incoming,,}" == "deny (incoming)" || "${incoming,,}" == "deny" ]] && \
     [[ "${outgoing,,}" == "allow (outgoing)" || "${outgoing,,}" == "allow" ]]; then
    defaults_ok=1
  fi

  # Source-CIDR rule for the docker frontend bridge to reach host-networked
  # services (Home Assistant on host:8123). Not port-based, so it lives
  # outside DESIRED_RULES, but checked here so the early-return below
  # does not skip it when port rules already match.
  local bridge_rule_present=0
  if grep -q "172\.22\.0\.0/16" <<<"$status_verbose"; then
    bridge_rule_present=1
  fi

  if [[ "$existing" == "$desired" ]] && [[ "$defaults_ok" -eq 1 ]] && [[ "$bridge_rule_present" -eq 1 ]]; then
    info "UFW already matches the desired rule set and default policies. No changes needed."
    return 0
  fi

  local ipv6_setting="unknown"
  if [[ -f /etc/default/ufw ]]; then
    ipv6_setting="$(grep -E '^[[:space:]]*IPV6=' /etc/default/ufw | tail -n1 | cut -d= -f2- | tr -d '[:space:]' || true)"
    ipv6_setting="${ipv6_setting,,}"
    [[ "$ipv6_setting" != "yes" && "$ipv6_setting" != "no" ]] && ipv6_setting="unknown"
  fi
  info "Current UFW IPv6 setting: IPV6=${ipv6_setting}"
  if [[ "$ipv6_setting" != "yes" ]]; then
    warn "IPv6 is not enabled for UFW. IPv6 allow rules may not be applied."
    read -p "Set IPV6=yes in /etc/default/ufw (backup will be created)? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      local ufw_conf="/etc/default/ufw"
      sudo cp -a "$ufw_conf" "${ufw_conf}.bak.$(date +%Y%m%d%H%M%S)"
      if grep -qE '^[[:space:]]*IPV6=' "$ufw_conf"; then
        sudo sed -i 's/^[[:space:]]*IPV6=.*/IPV6=yes/' "$ufw_conf"
      else
        echo "IPV6=yes" | sudo tee -a "$ufw_conf" >/dev/null
      fi
      info "Set IPV6=yes."
    else
      warn "Keeping IPV6 unchanged."
    fi
  fi

  info "Current UFW status:"
  sudo ufw status verbose || true
  echo

  read -p "Reset UFW (removes existing rules) before applying? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo ufw --force reset
    info "UFW reset complete."
  else
    warn "Skipping reset. Will add rules on top of existing configuration."
  fi

  if [[ "$defaults_ok" -eq 0 ]]; then
    warn "Default policies are not as expected."
    read -p "Set default incoming=deny, outgoing=allow? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      sudo ufw default deny incoming
      sudo ufw default allow outgoing
    else
      warn "Leaving default policies unchanged."
    fi
  else
    info "Default policies already match (deny incoming, allow outgoing)."
  fi

  read -p "Apply the desired allow rules now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    for rule in "${DESIRED_RULES[@]}"; do
      local port_proto="${rule%%:*}"
      local comment="${rule##*:}"
      sudo ufw allow "$port_proto" comment "$comment"
    done
    info "Allow rules applied."
  else
    warn "Skipping allow rules."
  fi

  # Always (re-)apply the frontend bridge rule. Required for Caddy to
  # reach host-networked services. UFW skips duplicates silently, so
  # this is safe even when the rule is already present. Re-applied
  # unconditionally because the reset path above wipes it.
  if [[ "$bridge_rule_present" -eq 0 ]]; then
    info "Adding frontend bridge (172.22.0.0/16) to host rule..."
  fi
  sudo ufw allow from 172.22.0.0/16 to 172.22.0.1 \
      comment 'frontend bridge to host' >/dev/null 2>&1 || true

  read -p "Enable UFW now? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo ufw --force enable
    info "UFW enabled."
  else
    warn "UFW was not enabled."
  fi

  echo
  info "Final UFW status:"
  sudo ufw status verbose || true
}

# Always ensure the frontend bridge can reach host-networked services
# (e.g. home assistant on host net). UFW default-deny on INPUT blocks
# packets from the bridge to the host without this rule. Idempotent —
# UFW skips duplicate adds.
if command -v ufw >/dev/null 2>&1 && sudo ufw status 2>/dev/null | grep -q "^Status: active"; then
    if ! sudo ufw status 2>/dev/null | grep -q "172.22.0.0/16"; then
        info "Allowing frontend bridge (172.22.0.0/16) to reach host in UFW..."
        sudo ufw allow from 172.22.0.0/16 to 172.22.0.1 comment 'frontend bridge to host'
    fi
fi

# Ask if user wants to set up firewall
echo
read -p "Configure UFW firewall now? [y/N] " -n 1 -r SETUP_FIREWALL
echo
if [[ $SETUP_FIREWALL =~ ^[Yy]$ ]]; then
  echo
  echo "========================================="
  echo "  UFW Firewall Setup"
  echo "========================================="
  echo
  setup_firewall
  echo
  echo "========================================="
  echo -e "${GREEN}  Firewall setup complete!${NC}"
  echo "========================================="
fi
