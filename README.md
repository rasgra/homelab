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
- Let you choose GUI subnet restriction for UISP & UniFi
- Generate secure passwords automatically
- Create all required directories and copy configuration files
- Optionally configure UFW firewall rules
- Optionally configure Telegram notifications and install monitoring cron jobs

## Manual Configuration

If you prefer manual setup or need to modify existing configuration:

### Environment Files

| File | Template | Description |
|------|----------|-------------|
| `.env` | `.env.example` | Root config (domain, data dir, profiles, notifications) |
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
| `MGMT_ALLOWED_SUBNET` | GUI subnet restriction for UISP/UniFi | `xxx.xxx.xxx.xxx/xx` |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token (from @BotFather) | _(optional)_ |
| `TELEGRAM_CHAT_ID` | Telegram chat or group ID for alerts | _(optional)_ |

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
./scripts/update-caddyfile --reload
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
| Collabora (Nextcloud Office) | `https://collabora.${BASE_DOMAIN}` |
| UISP | `https://uisp.${BASE_DOMAIN}` |
| Jitsi | `https://meet.${BASE_DOMAIN}` |
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

# Rebuild Nextcloud image (after base image update)
docker compose build nextcloud && docker compose up -d nextcloud
```

## Maintenance

### Check disk health

```bash
sudo ./scripts/check-disks
```

Reads S.M.A.R.T. data from all physical drives (SATA and NVMe). Checks overall health, reallocated/pending/uncorrectable sectors, SSD remaining life, temperature, and power-on time.

| Option | Description |
|--------|-------------|
| `--quiet` | Only print on issues; exit non-zero if any found |
| `--json` | NDJSON output, one object per drive |
| `--notify` | Send Telegram alert on issues |
| `--log FILE` | Append timestamped result to FILE |

### Check disk space

```bash
./scripts/check-space
```

Checks usage of all real mounted filesystems. Warns at 80%, critical at 90%.

| Option | Description |
|--------|-------------|
| `--warn-pct N` | Warn threshold (default: 80) |
| `--crit-pct N` | Critical threshold (default: 90) |
| `--quiet` | Only print on issues |
| `--notify` | Send Telegram alert on issues |

### Check TLS certificates

```bash
./scripts/check-certs
```

Reads domains from the Caddyfile, connects live, and shows expiry status for each. Skips `tls internal` blocks (e.g. UniFi).

| Option | Description |
|--------|-------------|
| `--warn-days N` | Warn threshold in days (default: 30) |
| `--crit-days N` | Critical threshold in days (default: 7) |
| `--quiet` | Print only warnings/errors; exit non-zero if any found |
| `--json` | NDJSON output, one object per domain |
| `--nagios` | Nagios/check_mk-compatible exit codes (0 OK, 1 WARN, 2 CRIT, 3 UNKNOWN) |
| `--notify` | Send Telegram alert on issues |
| `domain ...` | Check additional domains not in the Caddyfile |

### Watch container health

```bash
./scripts/watch-containers
```

Alerts when containers are unhealthy or in a restart loop. Uses a state file to avoid repeat notifications — sends once when an issue starts and once when it recovers.

| Option | Description |
|--------|-------------|
| `--notify` | Send Telegram alert on new issues and recoveries |
| `--quiet` | Suppress console output |

### Check for image updates

```bash
./scripts/update-images
```

Scans all compose files and Dockerfiles for pinned image versions, queries Docker Hub for newer releases, shows release notes links, and prompts before applying each update. Changes are logged to `update-history.log`. For Python/Node base images, minor version bumps are flagged as potentially breaking.

| Option | Description |
|--------|-------------|
| `--check-only` | Report only, no changes applied |
| `--notify` | Send Telegram message if updates are found |

To revert an applied update:
```bash
git checkout -- <compose-file>
docker compose up -d
```

### Weekly digest

```bash
sudo ./scripts/weekly-digest
```

Runs all checks (disk health, disk space, certificates, container updates, container health) and sends a single Telegram summary. Intended for use as a weekly cron job.

### Update Caddy config

```bash
./scripts/update-caddyfile [--reload]
```

Pushes the repo's Caddyfile and any registered project snippets to `$DATA_DIR/caddy/`. Pass `--reload` to also signal the running Caddy container to reload without restart.

## Notifications

Telegram alerts can be configured during initial setup or at any time:

```bash
./setup.sh --setup-notifications
```

This prompts for a bot token and chat ID, writes them to `.env`, sends a test message, and installs monitoring cron jobs into the root crontab.

**Getting credentials:**
1. Open Telegram → search for **@BotFather** → `/newbot`
2. Copy the bot token
3. Add the bot to your group (or use your personal chat with the bot)
4. Send a message, then visit `https://api.telegram.org/bot<TOKEN>/getUpdates` to find your chat ID

**Cron schedule (installed automatically):**

| Script | Schedule | Description |
|--------|----------|-------------|
| `check-disks` | Daily 06:00 | Disk S.M.A.R.T. health |
| `check-space` | Every 2 hours | Volume usage |
| `check-certs` | Daily 08:00 | TLS certificate expiry |
| `update-images` | Monday 09:00 | Container image updates |
| `watch-containers` | Every 5 minutes | Container health |
| `weekly-digest` | Sunday 08:00 | Full summary |

**Send a notification manually:**
```bash
./scripts/notify --level critical --title "Test" --message "Hello from homelab"
# Levels: info | warning | critical | ok
```

## Network Architecture

| Network | Purpose |
|---------|---------|
| `frontend` | Public-facing (Caddy, web services, Collabora) |
| `nextcloud-backend` | Internal (Nextcloud, MariaDB, Redis, Collabora) |
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

- UISP admin (`/nms/*`) restricted to management subnet
- UniFi GUI restricted to management subnet
- Jitsi: only authenticated users can create meetings; guests join via lobby
- Automatic HTTPS via Caddy with Let's Encrypt
- Backend networks are isolated from the frontend
