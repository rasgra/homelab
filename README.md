# Homelab Stack

Docker Compose-based homelab infrastructure with Caddy reverse proxy, Nextcloud, UISP, and Jitsi Meet.

## Quick Start

```bash
./setup.sh
docker compose up -d
```

The setup script will:
- Prompt for your domain and data directory
- Let you choose which services to enable
- Generate secure passwords automatically
- Create all required directories
- Copy configuration files

## Manual Configuration

If you prefer manual setup or need to modify existing configuration:

### Environment Files

| File | Template | Description |
|------|----------|-------------|
| `.env` | `.env.example` | Root config (domain, data dir, profiles) |
| `nextcloud/.env` | `nextcloud/.env.example` | Nextcloud settings |
| `nextcloud/.env.secrets` | `nextcloud/.env.secrets.example` | Database passwords |
| `jitsi-deploy/.env` | `jitsi-deploy/.env.example` | Jitsi settings |
| `jitsi-deploy/.env.secrets` | `jitsi-deploy/.env.secrets.example` | Jitsi auth passwords |

### Root Configuration (`.env`)

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_DOMAIN` | Base domain for all services | `stormyra.se` |
| `DATA_DIR` | Root directory for persistent data | `/opt/stack` |
| `COMPOSE_PROFILES` | Services to enable | `nextcloud,uisp,jitsi` |

### Secrets

**Nextcloud** (`nextcloud/.env.secrets`):
| Variable | Description |
|----------|-------------|
| `MYSQL_PASSWORD` | MariaDB password for nextcloud user |
| `MYSQL_ROOT_PASSWORD` | MariaDB root password |

**Jitsi** (`jitsi-deploy/.env.secrets`):
| Variable | Description |
|----------|-------------|
| `JICOFO_AUTH_PASSWORD` | Jicofo authentication password |
| `JVB_AUTH_PASSWORD` | JVB authentication password |

Generate passwords manually:
```bash
openssl rand -base64 32
```

## Enabling/Disabling Services

Edit `COMPOSE_PROFILES` in `.env`:

```bash
COMPOSE_PROFILES=nextcloud,uisp,jitsi  # All services
COMPOSE_PROFILES=nextcloud              # Only Nextcloud
COMPOSE_PROFILES=nextcloud,jitsi        # No UISP
```

Caddy always runs (no profile) as it's the reverse proxy.

## Data Directory

All data stored under `${DATA_DIR}` (default `/opt/stack`):

```
/opt/stack/
├── caddy/
│   ├── Caddyfile
│   ├── data/
│   └── config/
├── nextcloud/
│   ├── html/
│   ├── data/       # User files
│   ├── db/
│   └── redis/
├── uisp/
│   ├── data/
│   └── logs/
└── jitsi/
    ├── web/
    ├── web-public/
    ├── prosody/
    ├── jicofo/
    └── jvb/
```

### Separate Storage for Nextcloud

To put user files on a different disk, use a symlink:

```bash
sudo rmdir /opt/stack/nextcloud/data
sudo ln -s /mnt/large-disk/nextcloud-data /opt/stack/nextcloud/data
```

## Service URLs

| Service | URL |
|---------|-----|
| Nextcloud | `https://nextcloud.${BASE_DOMAIN}` |
| UISP | `https://uisp.${BASE_DOMAIN}` |
| Jitsi (public) | `https://meet.${BASE_DOMAIN}` |
| Jitsi (admin) | `https://adm.meet.${BASE_DOMAIN}` |

## Commands

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Logs
docker compose logs -f [service]

# Restart service
docker compose restart [service]

# Rebuild Nextcloud image
docker compose build nextcloud

# Update all images
docker compose pull && docker compose up -d
```

## Network Architecture

| Network | Purpose |
|---------|---------|
| `frontend` | Public-facing (Caddy, web services) |
| `nextcloud-backend` | Internal (Nextcloud, MariaDB, Redis) |
| `uisp-backend` | Internal (UISP) |
| `jitsi-backend` | Internal (Jitsi components) |

## Jitsi User Management

Only authenticated users can create meetings. Guests can join existing meetings but must wait in the lobby for moderator approval.

```bash
# Create a Jitsi user (can create meetings)
docker compose exec prosody prosodyctl --config /config/prosody.cfg.lua register USERNAME meet.jitsi PASSWORD

# List users
docker compose exec prosody prosodyctl --config /config/prosody.cfg.lua mod_listusers

# Delete a user
docker compose exec prosody prosodyctl --config /config/prosody.cfg.lua unregister USERNAME meet.jitsi
```

## Security

- UISP admin (`/nms/*`) restricted to VPN `172.16.1.0/24`
- Jitsi: only authenticated users can create meetings
- Automatic HTTPS via Caddy with Let's Encrypt
- Backend networks are isolated
