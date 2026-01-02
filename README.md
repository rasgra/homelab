# Homelab Stack

Docker Compose-based homelab infrastructure with Caddy reverse proxy, Nextcloud, UISP, and Jitsi Meet.

## Quick Start

```bash
# 1. Create environment files
cp dot_env .env
cp nextcloud/dot_env nextcloud/.env
cp nextcloud/dot_env.secrets nextcloud/.env.secrets
cp jitsi-deploy/dot_env jitsi-deploy/.env
cp jitsi-deploy/dot_env.secrets jitsi-deploy/.env.secrets

# 2. Edit configuration (see below)
vim .env

# 3. Create data directories
sudo mkdir -p /opt/stack/{caddy/{data,config},nextcloud/{html,data,db,redis},uisp/{data,logs},jitsi/{web,web-public,prosody,jicofo,jvb}}

# 4. Copy Caddyfile
sudo cp caddy/Caddyfile /opt/stack/caddy/Caddyfile

# 5. Start the stack
docker compose up -d
```

## Configuration

### Root Configuration (`.env`)

| Variable | Description | Example |
|----------|-------------|---------|
| `BASE_DOMAIN` | Base domain for all services | `example.com` |
| `DATA_DIR` | Root directory for all persistent data | `/opt/stack` |
| `COMPOSE_PROFILES` | Services to enable (comma-separated) | `nextcloud,uisp,jitsi` |

### Enabling/Disabling Services

Edit `COMPOSE_PROFILES` in `.env`:

```bash
# All services
COMPOSE_PROFILES=nextcloud,uisp,jitsi

# Only Nextcloud
COMPOSE_PROFILES=nextcloud

# Nextcloud and Jitsi (no UISP)
COMPOSE_PROFILES=nextcloud,jitsi
```

Caddy always runs as it's the reverse proxy.

## Secrets

### Nextcloud (`nextcloud/.env.secrets`)

| Variable | Description |
|----------|-------------|
| `MYSQL_PASSWORD` | MariaDB password for nextcloud user |
| `MYSQL_ROOT_PASSWORD` | MariaDB root password |

Generate secure passwords:
```bash
openssl rand -base64 32
```

### Jitsi (`jitsi-deploy/.env.secrets`)

| Variable | Description |
|----------|-------------|
| `JICOFO_AUTH_PASSWORD` | Jicofo authentication password |
| `JVB_AUTH_PASSWORD` | JVB authentication password |

Generate secure passwords:
```bash
openssl rand -hex 16
```

## Data Directory Structure

All data is stored under `${DATA_DIR}` (default: `/opt/stack`):

```
/opt/stack/
├── caddy/
│   ├── Caddyfile      # Reverse proxy config
│   ├── data/          # TLS certificates
│   └── config/        # Caddy state
├── nextcloud/
│   ├── html/          # Nextcloud application
│   ├── data/          # User files (symlink for separate storage)
│   ├── db/            # MariaDB database
│   └── redis/         # Redis cache
├── uisp/
│   ├── data/          # UISP configuration
│   └── logs/          # UISP logs
└── jitsi/
    ├── web/           # Jitsi web (admin)
    ├── web-public/    # Jitsi web (public)
    ├── prosody/       # XMPP server
    ├── jicofo/        # Jitsi conference focus
    └── jvb/           # Jitsi video bridge
```

### Using Separate Storage for Nextcloud Data

If you want Nextcloud user files on a different disk:

```bash
# Remove the directory and create a symlink
sudo rmdir /opt/stack/nextcloud/data
sudo ln -s /mnt/large-disk/nextcloud-data /opt/stack/nextcloud/data
```

## Services and URLs

| Service | URL | Description |
|---------|-----|-------------|
| Nextcloud | `https://nextcloud.${BASE_DOMAIN}` | File sync and collaboration |
| UISP | `https://uisp.${BASE_DOMAIN}` | Ubiquiti network management |
| Jitsi (public) | `https://meet.${BASE_DOMAIN}` | Video conferencing (guests) |
| Jitsi (admin) | `https://adm.meet.${BASE_DOMAIN}` | Video conferencing (authenticated) |

## Commands

```bash
# Start all enabled services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f [service-name]

# Restart a service
docker compose restart [service-name]

# Rebuild Nextcloud image (after Dockerfile changes)
docker compose build nextcloud

# Update images
docker compose pull
docker compose up -d
```

## Network Architecture

- `frontend` - Public-facing network for Caddy and web services
- `nextcloud-backend` - Internal network for Nextcloud, MariaDB, Redis
- `uisp-backend` - Internal network for UISP
- `jitsi-backend` - Internal network for Jitsi components

## Security Notes

- UISP admin UI (`/nms/*`) is restricted to VPN network `172.16.1.0/24`
- All services use HTTPS via Caddy with automatic Let's Encrypt certificates
- Backend networks are isolated (internal: true)
