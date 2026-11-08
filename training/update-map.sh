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

extract() {
	name=$1
	shift
	pmtiles extract "$URL" "/data/$name.pmtiles.tmp" "$@"
	sudo mv "$MAP_DIR/$name.pmtiles.tmp" "$MAP_DIR/$name.pmtiles"
}

MAP_DIR="$DATA_DIR/training/map"

if [ "${1:-}" = "--world" ] || ! sudo test -f "$MAP_DIR/world.pmtiles"; then
	extract world --maxzoom=6
fi

extract detail --region=/data/work/regions.geojson

sudo ls -la "$MAP_DIR"
