#!/bin/sh
# Cut the map tiles for training from the Protomaps daily build.
# Usage: training/update-map.sh [--world]
set -eu

cd "$(dirname "$0")/.."
set -a
. ./.env
set +a

BUILD=$(curl -fsS https://build-metadata.protomaps.dev/builds.json |
	grep -o '"key": *"[0-9]*\.pmtiles"' | tail -1 | grep -o '[0-9]*\.pmtiles')
if [ -z "$BUILD" ]; then
	echo "could not find the latest Protomaps build" >&2
	exit 1
fi
URL="https://build.protomaps.com/$BUILD"
echo "using $URL"

docker compose exec -T training-api python -m app.map regions

pmtiles() {
	docker compose --profile training-map run --rm training-pmtiles "$@"
}

if [ "${1:-}" = "--world" ] || ! sudo test -f "$DATA_DIR/training/map/world.pmtiles"; then
	pmtiles extract "$URL" /data/world.pmtiles.tmp --maxzoom=6
	sudo mv "$DATA_DIR/training/map/world.pmtiles.tmp" "$DATA_DIR/training/map/world.pmtiles"
fi

pmtiles extract "$URL" /data/detail.pmtiles.tmp --region=/data/work/regions.geojson
sudo mv "$DATA_DIR/training/map/detail.pmtiles.tmp" "$DATA_DIR/training/map/detail.pmtiles"

sudo ls -la "$DATA_DIR/training/map"
