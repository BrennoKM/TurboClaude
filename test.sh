#!/bin/bash
# TurboClaude - end-to-end test.
# Runs one cycle right now (via systemd/cron path when installed, or
# directly otherwise) and reports whether it worked.
#
# Usage: ./test.sh [--lang pt|en] [--direct]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" "$@"

DIRECT=false
for arg in "$@"; do
    [ "$arg" = "--direct" ] && DIRECT=true
done

echo ""
echo -e "${BOLD}TurboClaude $(t 'Teste' 'Test')${NC}"
echo ""

TODAY_LOG="$DATA_DIR/$(date '+%Y-%m-%d').log"
LINES_BEFORE=0
[ -f "$TODAY_LOG" ] && LINES_BEFORE=$(wc -l < "$TODAY_LOG")

if [ "$DIRECT" = false ] && command -v systemctl &>/dev/null && systemctl --user cat turbo-claude.service &>/dev/null; then
    info "$(t 'Disparando turbo-claude.service via systemd...' 'Triggering turbo-claude.service via systemd...')"
    systemctl --user start turbo-claude.service --wait
    RESULT=$?
elif [ -x "$SCRIPT_DIR/turbo-claude.sh" ]; then
    info "$(t 'systemd não configurado, rodando turbo-claude.sh diretamente...' 'systemd not set up, running turbo-claude.sh directly...')"
    "$SCRIPT_DIR/turbo-claude.sh"
    RESULT=$?
else
    error "$(t 'Nada para testar: instale primeiro com ./install.sh' 'Nothing to test: install first with ./install.sh')"
    exit 1
fi

echo ""
if [ -f "$TODAY_LOG" ]; then
    info "$(t 'Novas linhas de log' 'New log lines'):"
    tail -n "+$((LINES_BEFORE + 1))" "$TODAY_LOG"
else
    warn "$(t 'Nenhum arquivo de log encontrado em' 'No log file found at') $TODAY_LOG"
fi

echo ""
if [ "$RESULT" -eq 0 ] && grep -q "OK" <(tail -n "+$((LINES_BEFORE + 1))" "$TODAY_LOG" 2>/dev/null); then
    info "$(t 'Teste passou: o Claude respondeu com sucesso.' 'Test passed: Claude responded successfully.')"
    exit 0
else
    error "$(t 'Teste falhou. Veja o log acima.' 'Test failed. See the log above.')"
    exit 1
fi
