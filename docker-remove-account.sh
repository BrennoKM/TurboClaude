#!/bin/bash
# Removes an account (person) from the Docker setup: stops/removes its
# container, removes its service from docker-compose.yml, and asks
# whether to also delete its credentials/logs folder.
#
# Usage: ./docker-remove-account.sh <name> [--lang pt|en]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-}"
shift || true
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" "$@"

if [ -z "$NAME" ]; then
    error "$(t 'Uso: ./docker-remove-account.sh <nome>' 'Usage: ./docker-remove-account.sh <name>')"
    exit 1
fi

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
DIR="$SCRIPT_DIR/accounts/$NAME"
SERVICE="turbo-claude-$NAME"

if ! grep -q "^  $SERVICE:$" "$COMPOSE_FILE" 2>/dev/null; then
    error "$(t "Não existe um serviço $SERVICE no docker-compose.yml." "There is no $SERVICE service in docker-compose.yml.")"
    exit 1
fi

echo ""
echo -e "${BOLD}TurboClaude $(t 'Remover conta (Docker)' 'Remove account (Docker)'): $NAME${NC}"
echo ""

if command -v docker &>/dev/null && docker inspect "$SERVICE" &>/dev/null; then
    docker rm -f "$SERVICE" >/dev/null 2>&1 || true
    docker rmi "$SERVICE" >/dev/null 2>&1 || true
    info "$(t 'Container e imagem removidos.' 'Container and image removed.')"
fi

# Deletes the "  turbo-claude-<name>:" block: from that line up to (but
# not including) the next line that starts a new service at the same
# 2-space indent, or end of file. Also drops the blank line right
# before it, which belonged to that block, not the previous one.
awk -v svc="  $SERVICE:" '
    $0 == "" { pending_blank = 1; next }
    $0 == svc { skip = 1; pending_blank = 0; next }
    skip && /^  [a-zA-Z]/ { skip = 0 }
    !skip { if (pending_blank) print ""; pending_blank = 0; print }
' "$COMPOSE_FILE" > "$COMPOSE_FILE.tmp" && mv "$COMPOSE_FILE.tmp" "$COMPOSE_FILE"

if ! grep -q '^  [a-zA-Z]' "$COMPOSE_FILE"; then
    printf '# Run ./docker-new-account.sh <name> to add a person here automatically.\n# Each service below is one person/account: its own schedule (env vars)\n# and its own Claude credentials (volumes), never shared between them.\nservices: {}\n' > "$COMPOSE_FILE"
fi

info "$(t "Serviço $SERVICE removido do docker-compose.yml." "Service $SERVICE removed from docker-compose.yml.")"

if [ -d "$DIR" ]; then
    ask "$(t 'Remover também as credenciais e logs em' 'Also remove credentials and logs at') $DIR? (y/N) [${CYAN}N${NC}]: "
    read -r input_purge || true
    if [[ "$input_purge" =~ ^[Yy] ]]; then
        docker run --rm -v "$DIR/claude:/data" alpine sh -c "rm -rf /data/*" >/dev/null 2>&1 || true
        rm -rf "$DIR"
        info "$(t 'Pasta da conta removida.' 'Account folder removed.')"
    else
        info "$(t 'Pasta da conta mantida (credenciais preservadas).' 'Account folder kept (credentials preserved).')"
    fi
fi

echo ""
info "$(t "Conta '$NAME' removida." "Account '$NAME' removed.")"
echo ""
