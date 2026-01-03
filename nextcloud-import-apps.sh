#!/bin/bash
# Install Nextcloud apps from a list file
#
# Usage: ./nextcloud-import-apps.sh apps.txt
#
# The apps.txt file should have one app name per line.
# Create it with: ./nextcloud-export-apps.sh > apps.txt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -z "$1" || ! -f "$1" ]]; then
    echo "Usage: $0 <apps.txt>"
    echo
    echo "Install Nextcloud apps from a list file."
    echo "Create the list with: ./nextcloud-export-apps.sh > apps.txt"
    exit 1
fi

APP_LIST="$1"

# Check if nextcloud is running
if ! docker compose ps nextcloud 2>/dev/null | grep -q "running"; then
    echo "Error: Nextcloud container is not running"
    echo "Start it with: docker compose up -d"
    exit 1
fi

echo "Installing apps from: $APP_LIST"
echo

while IFS= read -r app || [[ -n "$app" ]]; do
    # Skip empty lines and comments
    [[ -z "$app" || "$app" =~ ^# ]] && continue
    # Clean whitespace
    app=$(echo "$app" | tr -d '[:space:]')
    [[ -z "$app" ]] && continue

    echo -n "  $app: "
    if docker compose exec -T -u www-data nextcloud php occ app:install "$app" 2>/dev/null; then
        echo "installed"
    elif docker compose exec -T -u www-data nextcloud php occ app:enable "$app" 2>/dev/null; then
        echo "enabled (already installed)"
    else
        echo "failed (not in app store?)"
    fi
done < "$APP_LIST"

echo
echo "Done. Check app status with:"
echo "  docker compose exec -u www-data nextcloud php occ app:list"
