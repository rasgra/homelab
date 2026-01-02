# Jitsi Branding

Custom logo for Jitsi Meet calls.

## Template Files

This directory contains template branding files that are copied to `${DATA_DIR}/jitsi/branding/` during setup.

- `watermark.svg` - Logo shown in top-left corner during video calls

## Customizing the Logo

After running `./setup.sh`, edit the logo in your data directory:

```bash
# Replace with your logo
sudo cp /path/to/your-logo.svg /opt/stack/jitsi/branding/watermark.svg

# Restart Jitsi web containers
docker compose restart web web-public
```

## Requirements

- SVG format (preferred) or PNG
- Transparent background recommended
- Suggested dimensions: ~200px wide
