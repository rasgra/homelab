# Jitsi Branding

Custom branding files for Jitsi Meet. These are mounted directly into the container — no copying to the data directory required.

## Files

- `watermark.svg` — Placeholder (overridden by the SVG below)
- `stormyra-consulting-ab-white.svg` — Logo shown in top-left during calls (watermark) and on the welcome page
- `bg.png` — Background image for the welcome page
- `branding.json` — Dynamic branding config (references logo and background by relative URL)

## Updating branding

Edit or replace the files in this directory, then recreate the web container:

```bash
docker compose up -d --force-recreate web
```

## Adding new branding fields

Edit `branding.json`. Supported fields include `logoImageUrl`, `backgroundImageUrl`, `backgroundColor`, and `headerLogoUrl`.
See the [Jitsi Meet branding docs](https://jitsi.github.io/handbook/docs/dev-guide/dev-guide-branding) for the full list.
