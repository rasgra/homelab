#!/bin/bash
set -e

PROSODY_CONTAINER="prosody"
XMPP_DOMAIN="meet.jitsi"

usage() {
    echo "Usage: $0 <command> [arguments]"
    echo
    echo "Commands:"
    echo "  add <username> <password>   Create a new user"
    echo "  delete <username>           Delete a user"
    echo "  list                        List all users"
    echo "  passwd <username> <password> Change user password"
    echo
    exit 1
}

prosodyctl() {
    docker compose exec -T "$PROSODY_CONTAINER" prosodyctl --config /config/prosody.cfg.lua "$@"
}

case "${1:-}" in
    add)
        [[ -z "${2:-}" || -z "${3:-}" ]] && { echo "Error: add requires username and password"; usage; }
        prosodyctl register "$2" "$XMPP_DOMAIN" "$3"
        echo "User '$2' created"
        ;;
    delete)
        [[ -z "${2:-}" ]] && { echo "Error: delete requires username"; usage; }
        prosodyctl unregister "$2" "$XMPP_DOMAIN"
        echo "User '$2' deleted"
        ;;
    list)
        docker compose exec -T "$PROSODY_CONTAINER" \
            sh -c 'find /config/data -path "*/meet*/accounts/*.dat" 2>/dev/null | xargs -I{} basename {} .dat' \
            || echo "(no users found)"
        ;;
    passwd)
        [[ -z "${2:-}" || -z "${3:-}" ]] && { echo "Error: passwd requires username and password"; usage; }
        prosodyctl passwd "$2@$XMPP_DOMAIN" "$3"
        echo "Password changed for '$2'"
        ;;
    *)
        usage
        ;;
esac
