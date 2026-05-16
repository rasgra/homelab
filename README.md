# Homelab Stack

Docker Compose-based homelab infrastructure with Caddy reverse proxy, Nextcloud, UISP, Jitsi Meet, and UniFi Controller.

## Quick Start

```bash
./setup.sh
docker compose up -d
```

The setup script will:
- Prompt for your domain and data directory
- Let you choose which services to enable
- Let you choose GUI subnet restriction for uisp & unifi
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
| `COMPOSE_PROFILES` | Services to enable | `nextcloud,uisp,jitsi,unifi` |
| `MGMT_ALLOWED_SUBNET` | GUI subnet restriction | `xxx.xxx.xxx.xxx/xx` |

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
COMPOSE_PROFILES=nextcloud,uisp,jitsi,unifi  # All services
COMPOSE_PROFILES=nextcloud                    # Only Nextcloud
COMPOSE_PROFILES=nextcloud,jitsi              # No UISP or UniFi
```

Caddy always runs (no profile) as it's the reverse proxy.

## Custom Projects

Ephemeral or prototype projects can be plugged into the stack without editing any core files. The setup script manages a `compose.override.yml` (auto-merged by Docker Compose) and drops Caddy config snippets into `conf.d/`.

### Adding a project

```bash
./setup.sh --add-project ./my-project
```

This registers the project, regenerates `compose.override.yml`, and deploys the Caddy snippet to `$DATA_DIR/caddy/conf.d/`. Then restart the stack:

```bash
docker compose up -d
```

### Removing a project

```bash
./setup.sh --remove-project ./my-project
docker compose up -d
```

### Listing registered projects

```bash
./setup.sh --list-projects
```

### Project structure

Each custom project directory must contain a `homelab.yml` descriptor:

```yaml
name: my-project           # unique identifier
subdomain: my-project      # → my-project.<BASE_DOMAIN>
backend_network: my-project-backend   # Docker network for backend services (omit if not needed)
compose: compose.yml       # path to the project's compose file (relative to project dir)
caddy_snippet: caddy.caddy # path to the Caddy virtual host block (relative to project dir)
```

The `caddy_snippet` file is a standard Caddy site block that can use `{$BASE_DOMAIN}` and any snippets defined in the main Caddyfile (`security_headers`, `proxy_headers`):

```
my-project.{$BASE_DOMAIN} {
    import security_headers

    reverse_proxy my-service:8080 {
        import proxy_headers
    }
}
```

The project's compose file should declare its services and reference the backend network as external:

```yaml
services:
  my-service:
    image: ...
    networks:
      - my-project-backend

networks:
  my-project-backend:
    external: true
    name: my-project-backend
```

### Updating Caddy config without full setup

If you've edited the Caddyfile or a project's caddy snippet and want to push the changes without re-running setup:

```bash
./scripts/update-caddyfile
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Data Directory

All data stored under `${DATA_DIR}` (default `/opt/stack`):

```
/opt/stack/
├── caddy/
│   ├── Caddyfile
│   ├── conf.d/          # Custom project Caddy snippets (auto-managed)
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
├── jitsi/
│   ├── web/
│   ├── web-public/
│   ├── prosody/
│   ├── jicofo/
│   └── jvb/
└── unifi/
    └── data/       # UniFi config, db, backups
```

### Separate Storage for Nextcloud

To put user files on a different disk, use a symlink:

```bash
sudo rmdir /opt/stack/nextcloud/data
sudo ln -s /mnt/large-disk/nextcloud-data /opt/stack/nextcloud/data
```

### Migrating Existing Nextcloud Installation

#### Step 1: Export from old server

```bash
# Export database
docker compose exec mariadb mariadb-dump -u root -p nextcloud > nextcloud-dump.sql

# Export app list
./nextcloud-export-apps.sh > apps.txt

# Note your data directory location
```

#### Step 2: Setup new server

```bash
./setup.sh
docker compose up -d
# Wait for initial setup to complete
docker compose logs -f nextcloud
```

#### Step 3: Import database

```bash
# Stop nextcloud
docker compose stop nextcloud nextcloud-cron

# Import dump (use password from nextcloud/.env.secrets)
docker compose exec -T mariadb mariadb -u root -p nextcloud < nextcloud-dump.sql

# Start nextcloud
docker compose start nextcloud nextcloud-cron
```

#### Step 4: Install apps

```bash
./nextcloud-import-apps.sh apps.txt
```

#### Step 5: Copy user data (optional)

```bash
sudo cp -a /old/data/* /opt/stack/nextcloud/data/
sudo chown -R 33:33 /opt/stack/nextcloud/data

# Update Nextcloud
docker compose exec -u www-data nextcloud php occ maintenance:data-fingerprint
docker compose exec -u www-data nextcloud php occ files:scan --all
```

## Service URLs

| Service | URL |
|---------|-----|
| Nextcloud | `https://nextcloud.${BASE_DOMAIN}` |
| UISP | `https://uisp.${BASE_DOMAIN}` |
| Jitsi (public) | `https://meet.${BASE_DOMAIN}` |
| Jitsi (admin) | `https://adm.meet.${BASE_DOMAIN}` |
| UniFi | `https://unifi.${BASE_DOMAIN}` |

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

Custom project networks are declared in `compose.override.yml` and managed by `./setup.sh --add-project`.

## Jitsi User Management

Only authenticated users can create meetings. Guests can join existing meetings but must wait in the lobby for moderator approval.

```bash
# Create a Jitsi user (can create meetings)
./jitsi-users.sh add USERNAME PASSWORD

# List users
./jitsi-users.sh list

# Change password
./jitsi-users.sh passwd USERNAME NEWPASSWORD

# Delete a user
./jitsi-users.sh delete USERNAME
```

## Security

- UISP admin (`/nms/*`) restricted to VPN `172.16.1.0/24`
- Jitsi: only authenticated users can create meetings
- Automatic HTTPS via Caddy with Let's Encrypt
- Backend networks are isolated
