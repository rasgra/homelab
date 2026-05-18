# Home Assistant

Single container running `ghcr.io/home-assistant/home-assistant:stable`
with `network_mode: host`. Host networking is what lets HA do mDNS /
SSDP discovery for Chromecasts, Sonos, Nest Hubs and similar.

Caddy reverse-proxies `https://home.roxell.se` to `host.docker.internal:8123`,
gated to the mgmt subnet via `tls internal`. The host gateway IP is
pinned to `172.22.0.1` in `caddy/compose.yml` so the docker bridge
can reach HA on port 8123 reliably.

setup.sh pre-creates `configuration.yaml` with `http: use_x_forwarded_for: true`
and `trusted_proxies: 172.22.0.0/16`, so HA accepts proxied requests
from Caddy out of the box.

## After first boot

Open `https://home.roxell.se` and complete the onboarding wizard:

1. Create the admin user (email, name, password).
2. Set timezone to **Europe/Stockholm** and your home location.
3. HA reboots once on its own when onboarding finishes.

Then add the integrations below.

## Zigbee devices via Zigbee2MQTT

Add the MQTT integration. See `../zigbee2mqtt/README.md` for the
broker credentials and pairing steps. Once MQTT is connected, every
Zigbee device paired through Z2M auto-appears in HA without extra
configuration.

## Google devices (Chromecast, Nest Hub, smart speakers)

These are discovered over mDNS on the local network. Prerequisite:
the EdgeRouter must repeat mDNS to `eth1` so HA (on the .100 VLAN)
sees IoT devices on VLAN .22.

```
ssh ubnt@192.168.100.1
configure
set service mdns repeater interface eth1
commit; save; exit
```

Then in HA:

1. **Settings → Devices & services**.
2. Look under **Discovered** for Cast devices already detected, or
   click **Add integration → Google Cast** to trigger a fresh sweep.
3. Click each device → **Configure** → name → done.

Each Cast device becomes a `media_player.*` entity. Speaker groups,
TTS announcements, push media, casting dashboards — all from HA.

**Nest cameras / doorbells / thermostats** (Nest-branded, not just
Chromecast) need a separate **Google Nest** integration. Cloud-based,
needs a Google Device Access Console project — follow HA's official
guide. Not needed for plain Cast targets.

## Yale Doorman lock + Smart Keypad

These talk to Yale's cloud via the Yale Connect Wi-Fi Bridge. HA
authenticates against the same cloud and treats the lock as a
`lock.*` entity.

1. **Settings → Devices & services → Add integration → "Yale Access"**
   (depending on HA version, it may be labelled "Yale").
2. Enter the same email + password you use in the Yale Home / Yale
   Access app on your phone.
3. Yale sends a verification code by email or SMS. Enter it in HA.
4. Lock + keypad appear as devices. The lock exposes:
   - state (locked / unlocked)
   - battery level
   - last operation (who, when, app vs keypad vs manual)
5. Automations can lock the door on a schedule, announce arrivals via
   Cast, send notifications on PIN-code use, etc.

**Yale Doorman bound to Verisure** uses a different path: enable HA's
**Verisure** integration with your Verisure credentials instead. The
lock comes in as a Verisure device. You can have only one of the two
active at a time.

### Common Yale gotchas

| Symptom                                          | Fix                                          |
| ------------------------------------------------ | -------------------------------------------- |
| "Invalid credentials" but same login works in app | Update HA — the new Yale Home backend needs a recent integration version |
| Lock works but battery shows 0%                  | Open the Yale app, view the device once. HA picks up the next sync |
| Verification code never arrives                  | Yale sometimes silently rate-limits — wait 10 min before retrying |
| Lock appears but state is "unknown"              | Wi-Fi Bridge is offline. Power-cycle the bridge, wait 2 min |

## Common HA bring-up issues

| Symptom                                    | First place to look                     |
| ------------------------------------------ | --------------------------------------- |
| `https://home.roxell.se` → 502             | UFW rule `172.22.0.0/16 → 172.22.0.1` missing (see top-level `setup.sh`) |
| `https://home.roxell.se` → 400 Bad Request | `trusted_proxies` not in `/opt/stack/homeassistant/config/configuration.yaml` |
| Chromecasts do not appear                  | EdgeRouter mDNS repeater missing `eth1` |
| Login works but page is slow / partial     | `docker compose logs --tail 50 homeassistant` |
| MQTT integration not finding the bridge    | `docker compose logs --tail 20 mosquitto` for connection from HA |

## Files

- `compose.yml` — HA service definition, host networking
- `/opt/stack/homeassistant/config/configuration.yaml` — HA config
  (pre-populated by setup.sh with `http: trusted_proxies` block)
- `/opt/stack/homeassistant/config/.storage/` — onboarding state,
  user accounts, integration credentials (encrypted)
- `/opt/stack/homeassistant/config/automations.yaml` — automations
  (UI-managed)
- `/opt/stack/homeassistant/config/home-assistant.log` — runtime log

## Backups

HA has its own backup integration (**Settings → System → Backups**).
Schedule a daily backup, save to `/opt/stack/homeassistant/config/backups/`,
mount that to your normal homelab backup target.

Critical files to back up at minimum:

- `configuration.yaml` (the trusted_proxies block, plus any manual config)
- `.storage/` (users, integration credentials, device registry)
- `automations.yaml`, `scripts.yaml`, `scenes.yaml` (if you use them)
