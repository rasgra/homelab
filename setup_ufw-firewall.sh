#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ----------------------------
# Firewall rule definitions
# ----------------------------
# Format: "port/proto:comment"
BASE_RULES=(
  "22/tcp:SSH"
  "80/tcp:HTTP"
  "443/tcp:HTTPS"
)
RULES_NEXTCLOUD=() 
RULES_UISP=(
  "2055/udp:NetFlow/UDP 2055"
)
RULES_JITSI=(
  "10000/udp:Jitsi JVB Media"
)

RULES_UNIFI=(
  "3478/udp:UniFi STUN"
  "10001/udp:UniFi Device Discovery"
  "8080/tcp:UniFi Inform (Adoption)"
)

# ----------------------------
# Helpers
# ----------------------------
require_root() {
  [[ "$(id -u)" -eq 0 ]] || error "Run as root (sudo $0)"
}

# Reads COMPOSE_PROFILES from $SCRIPT_DIR/.env (comma-separated)
load_profiles() {
  [[ -f "$SCRIPT_DIR/.env" ]] || error "Missing $SCRIPT_DIR/.env (expected COMPOSE_PROFILES=nextcloud,uisp,jitsi)"

  # shellcheck disable=SC1090
  set -a
  source "$SCRIPT_DIR/.env"
  set +a

  if [[ -z "${COMPOSE_PROFILES:-}" ]]; then
    error "COMPOSE_PROFILES is empty in $SCRIPT_DIR/.env"
  fi

  PROFILES="${COMPOSE_PROFILES}"
}

# Split comma-separated into array PROFILES_ARR
split_profiles() {
  IFS=',' read -r -a PROFILES_ARR <<< "$PROFILES"
}

# Confirm prompt, default No
confirm() {
  local prompt="$1"
  read -p "$prompt [y/N] " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]]
}

# Get current UFW IPv6 setting from /etc/default/ufw
get_ufw_ipv6_setting() {
  local f="/etc/default/ufw"
  [[ -f "$f" ]] || { echo "unknown"; return 0; }
  local val
  val="$(grep -E '^[[:space:]]*IPV6=' "$f" | tail -n1 | cut -d= -f2- | tr -d '[:space:]' || true)"
  case "${val,,}" in
    yes) echo "yes" ;;
    no)  echo "no" ;;
    *)   echo "unknown" ;;
  esac
}

set_ufw_ipv6_yes() {
  local f="/etc/default/ufw"
  [[ -f "$f" ]] || error "Missing $f; cannot set IPV6=yes"
  cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  if grep -qE '^[[:space:]]*IPV6=' "$f"; then
    sed -i 's/^[[:space:]]*IPV6=.*/IPV6=yes/' "$f"
  else
    echo "IPV6=yes" >> "$f"
  fi
}

# Build desired rules into DESIRED_RULES array
# Includes BASE_RULES + per-profile rules
build_desired_rules() {
  DESIRED_RULES=()
  DESIRED_RULES+=( "${BASE_RULES[@]}" )

  local p
  for p in "${PROFILES_ARR[@]}"; do
    case "$p" in
      nextcloud)
        DESIRED_RULES+=( "${RULES_NEXTCLOUD[@]}" )
        ;;
      uisp)
        DESIRED_RULES+=( "${RULES_UISP[@]}" )
        ;;
      jitsi)
        DESIRED_RULES+=( "${RULES_JITSI[@]}" )
        ;;
      unifi)
        DESIRED_RULES+=( "${RULES_UNIFI[@]}" )
        ;;
      "" )
        ;;
      *)
        warn "Unknown profile '$p' in COMPOSE_PROFILES; ignoring for firewall rules."
        ;;
    esac
  done

  # De-dup (by port/proto) while preserving order
  local seen=""
  local out=()
  local rule portproto
  for rule in "${DESIRED_RULES[@]}"; do
    portproto="${rule%%:*}"
    if [[ ",$seen," != *",$portproto,"* ]]; then
      out+=( "$rule" )
      seen="${seen},${portproto}"
    fi
  done
  DESIRED_RULES=( "${out[@]}" )
}

# Extract existing allow rules from `ufw status` as "port/proto" lines (v4 + v6 treated separately by ufw display)
# We'll compare a normalized representation.
get_existing_allow_rules_normalized() {
  # Output normalized list:
  #   tcp:22
  #   udp:10000
  #
  # We intentionally ignore comments. We also ignore destination scope "Anywhere" vs specific IP.
  # If user has more restrictive rules, we will NOT treat them as equal.
  ufw status 2>/dev/null \
    | awk '
      BEGIN{IGNORECASE=1}
      NR>2 && $1 !~ /^(Status:|To)$/ {
        # Typical lines:
        # 22/tcp                    ALLOW       Anywhere
        # 10000/udp                 ALLOW       Anywhere (v6)
        to=$1
        action=$2
        if (action != "ALLOW") next

        # Normalize to "proto:port"
        split(to, a, "/")
        port=a[1]
        proto=a[2]
        if (port ~ /^[0-9]+$/ && proto ~ /^(tcp|udp)$/) {
          print proto ":" port
        }
      }
    ' | sort -u
}

get_desired_allow_rules_normalized() {
  # From DESIRED_RULES "port/proto:comment" -> "proto:port"
  local rule portproto port proto
  for rule in "${DESIRED_RULES[@]}"; do
    portproto="${rule%%:*}"
    port="${portproto%%/*}"
    proto="${portproto##*/}"
    echo "${proto}:${port}"
  done | sort -u
}

# Returns 0 if existing exactly equals desired (same set), else 1.
# NOTE: this compares only "ALLOW anywhere" style rules that show up in ufw status.
# If you have additional rules (deny, limit, allow from CIDR) they'll cause mismatch (good).
rules_already_match() {
  local existing desired
  existing="$(get_existing_allow_rules_normalized || true)"
  desired="$(get_desired_allow_rules_normalized || true)"
  [[ "$existing" == "$desired" ]]
}

# Default policy check. Returns "ok" or "diff"
default_policies_status() {
  local s incoming outgoing
  s="$(ufw status verbose 2>/dev/null || true)"
  incoming="$(awk -F': ' '/Default: /{print $2}' <<<"$s" | awk -F', ' '{print $1}' | xargs || true)"
  outgoing="$(awk -F': ' '/Default: /{print $2}' <<<"$s" | awk -F', ' '{print $2}' | xargs || true)"

  local in_ok=0 out_ok=0
  [[ "${incoming,,}" == "deny (incoming)" || "${incoming,,}" == "deny" ]] && in_ok=1
  [[ "${outgoing,,}" == "allow (outgoing)" || "${outgoing,,}" == "allow" ]] && out_ok=1

  [[ "$in_ok" -eq 1 && "$out_ok" -eq 1 ]] && echo "ok" || echo "diff"
}

apply_defaults_if_needed() {
  if [[ "$(default_policies_status)" == "ok" ]]; then
    info "Default policies already match expected (deny incoming, allow outgoing)."
    return 0
  fi

  warn "Default policies are not as expected."
  ufw status verbose || true

  if confirm "Set default incoming policy to deny and outgoing to allow?"; then
    ufw default deny incoming
    ufw default allow outgoing
  else
    warn "Leaving default policies unchanged."
  fi
}

# ----------------------------
# Main
# ----------------------------
echo "========================================="
echo "  UFW Firewall Setup"
echo "========================================="
echo

require_root
load_profiles
split_profiles
build_desired_rules

info "Profiles enabled (from $SCRIPT_DIR/.env): ${PROFILES}"
info "Desired firewall allow rules:"
for r in "${DESIRED_RULES[@]}"; do
  echo "  - ${r%%:*}  (${r##*:})"
done
echo

# Pre-req: ufw installed?
if ! command -v ufw >/dev/null 2>&1; then
  warn "ufw is not installed."
  if confirm "Install ufw now via apt-get?"; then
    apt-get update
    apt-get install -y ufw
    info "ufw installed."
  else
    error "ufw is required. Exiting without changes."
  fi
else
  info "ufw is installed: $(ufw --version | head -n1 || true)"
fi

# Check if existing rules already match desired (and defaults match)
# If so: inform user and exit
# (We also require defaults to match, else we consider it a mismatch.)
if rules_already_match && [[ "$(default_policies_status)" == "ok" ]]; then
  info "UFW already matches the desired rule set and default policies. No changes needed."
  exit 0
fi

# IPv6 enablement check (only if rules include public v6 expectations — you asked for v6 parity)
ipv6_setting="$(get_ufw_ipv6_setting)"
info "Current UFW IPv6 setting: IPV6=${ipv6_setting}"
if [[ "$ipv6_setting" != "yes" ]]; then
  warn "IPv6 is not enabled for UFW (IPV6=yes). IPv6 allow rules may not be applied."
  if confirm "Set IPV6=yes in /etc/default/ufw (backup will be created)?"; then
    set_ufw_ipv6_yes
    info "Set IPV6=yes."
  else
    warn "Keeping IPV6 unchanged."
  fi
fi

# Show current status
info "Current UFW status:"
ufw status verbose || true
echo

# Reset prompt
if confirm "Reset UFW (removes existing rules) before applying desired rule set?"; then
  ufw --force reset
  info "UFW reset complete."
else
  warn "Skipping reset. Will add desired rules on top of existing configuration."
fi

# Defaults
apply_defaults_if_needed

# Apply rules
if confirm "Apply the desired allow rules now?"; then
  for rule in "${DESIRED_RULES[@]}"; do
    PORT_PROTO="${rule%%:*}"
    COMMENT="${rule##*:}"
    ufw allow "$PORT_PROTO" comment "$COMMENT"
  done
  info "Allow rules applied."
else
  warn "Skipping allow rules."
fi

# Enable prompt
info "UFW status before enable:"
ufw status verbose || true
echo

if confirm "Enable UFW now?"; then
  ufw --force enable
  info "UFW enabled."
else
  warn "UFW was not enabled by this script."
fi

echo
echo "========================================="
echo -e "${GREEN}  Firewall setup complete!${NC}"
echo "========================================="
echo
info "Final UFW status:"
ufw status verbose || true

