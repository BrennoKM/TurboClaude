#!/bin/bash
# Scaffolds a new account (person) for the Docker setup: creates its
# folders and appends a ready-to-run service to docker-compose.yml.
# Each account gets its own schedule and its own Claude credentials,
# fully independent from every other account.
#
# Usage: ./docker-new-account.sh <name> [--lang pt|en]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="${1:-}"
shift || true
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" "$@"

if [ -z "$NAME" ]; then
    error "$(t 'Uso: ./docker-new-account.sh <nome>' 'Usage: ./docker-new-account.sh <name>')"
    exit 1
fi

if ! [[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "$(t 'Nome inválido. Use apenas letras, números, hífen e underscore.' 'Invalid name. Use only letters, numbers, hyphen and underscore.')"
    exit 1
fi

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
DIR="$SCRIPT_DIR/accounts/$NAME"

if grep -q "turbo-claude-$NAME:" "$COMPOSE_FILE" 2>/dev/null; then
    error "$(t "Já existe um serviço turbo-claude-$NAME no docker-compose.yml." "A turbo-claude-$NAME service already exists in docker-compose.yml.")"
    exit 1
fi

echo ""
echo -e "${BOLD}TurboClaude $(t 'Nova conta (Docker)' 'New account (Docker)'): $NAME${NC}"
echo ""

ask "$(t 'Prompt a enviar ao Claude' 'Prompt to send to Claude') [${CYAN}Oi${NC}]: "
read -r input_prompt || true
PROMPT="${input_prompt:-Oi}"

ask "$(t 'Horários (24h, separados por vírgula)' 'Schedule times (24h, comma-separated)') [${CYAN}05:00,10:00,15:00${NC}]: "
read -r input_times || true
TIMES="${input_times:-05:00,10:00,15:00}"

echo "$(t '  Exemplos de dias: * (todo dia), Mon..Fri (dias úteis), Sat,Sun (fim de semana), Mon,Wed,Fri' '  Day examples: * (every day), Mon..Fri (weekdays), Sat,Sun (weekend), Mon,Wed,Fri')"
ask "$(t 'Dias da semana' 'Days of week') [${CYAN}*${NC}]: "
read -r input_days || true
DAYS="${input_days:-*}"

ask "$(t 'Registrar a resposta do Claude no log? (Y/n)' "Log Claude's response? (Y/n)") [${CYAN}Y${NC}]: "
read -r input_log || true
LOG_RESPONSE=true
[[ "$input_log" =~ ^[Nn] ]] && LOG_RESPONSE=false

mkdir -p "$DIR/claude" "$DIR/logs"
echo '{}' > "$DIR/claude.json"

# "services: {}" is a valid empty mapping for editors/schemas; turn it
# into a real (non-empty) mapping before appending the first account.
sed -i 's/^services: {}$/services:/' "$COMPOSE_FILE"

cat >> "$COMPOSE_FILE" << EOF

  turbo-claude-$NAME:
    build: .
    container_name: turbo-claude-$NAME
    restart: unless-stopped
    environment:
      PROMPT: "$PROMPT"
      TIMES: "$TIMES"
      DAYS: "$DAYS"
      LOG_RESPONSE: "$LOG_RESPONSE"
    volumes:
      - ./accounts/$NAME/claude.json:/root/.claude.json
      - ./accounts/$NAME/claude:/root/.claude
      - ./accounts/$NAME/logs:/root/.local/share/turbo-claude
EOF

echo ""
info "$(t "Conta '$NAME' adicionada ao docker-compose.yml." "Account '$NAME' added to docker-compose.yml.")"
echo ""
echo "  docker compose up -d turbo-claude-$NAME"
echo "  docker exec -it turbo-claude-$NAME claude auth login   # $(t 'se ainda não tiver credenciais montadas' 'if credentials are not already mounted')"
echo "  ./test.sh --container turbo-claude-$NAME --wait 30      # $(t 'valida o disparo real' 'validates the real trigger')"
echo ""
