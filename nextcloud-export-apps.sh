#!/bin/bash
# Export list of enabled Nextcloud apps for migration
#
# Usage: ./nextcloud-export-apps.sh > apps.txt
#
# Then use apps.txt with migrate-nextcloud.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if nextcloud is running
if ! docker compose ps nextcloud 2>/dev/null | grep -q "running"; then
    echo "Error: Nextcloud container is not running" >&2
    echo "Start it with: docker compose up -d nextcloud" >&2
    exit 1
fi

# Export enabled apps (one per line)
docker compose exec -T -u www-data nextcloud php occ app:list --enabled --output=plain 2>/dev/null \
    | grep -E '^\s+-' \
    | sed 's/.*- //' \
    | cut -d: -f1 \
    | sort
