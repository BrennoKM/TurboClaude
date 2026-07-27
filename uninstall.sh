#!/bin/bash
# TurboClaude uninstaller.
# Removes the systemd timer/service (or crontab entry), the installed
# script, and optionally the config/logs.
#
# Usage: ./uninstall.sh [--lang pt|en]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" "$@"

echo ""
echo -e "${BOLD}TurboClaude $(t 'Desinstalador' 'Uninstaller')${NC}"
echo ""

if command -v systemctl &>/dev/null && systemctl --user cat turbo-claude.timer &>/dev/null; then
    systemctl --user stop turbo-claude.timer 2>/dev/null || true
    systemctl --user disable turbo-claude.timer 2>/dev/null || true
    systemctl --user disable turbo-claude.service 2>/dev/null || true
    rm -f "$SERVICE_DIR/turbo-claude.timer" "$SERVICE_DIR/turbo-claude.service"
    systemctl --user daemon-reload
    info "$(t 'Timer e service do systemd removidos.' 'systemd timer and service removed.')"
fi

if command -v crontab &>/dev/null && crontab -l 2>/dev/null | grep -q turbo-claude; then
    (crontab -l 2>/dev/null | grep -v turbo-claude) | crontab -
    info "$(t 'Entrada do crontab removida.' 'Crontab entry removed.')"
fi

if [ -f "$SCRIPT_DST" ]; then
    rm -f "$SCRIPT_DST"
    info "$(t 'Script removido' 'Script removed'): $SCRIPT_DST"
fi

if [ -d "$CONFIG_DIR" ] || [ -d "$DATA_DIR" ]; then
    ask "$(t 'Remover também config e logs (' 'Also remove config and logs (')${CONFIG_DIR}, ${DATA_DIR}$(t ')? (Y/n)' ')? (Y/n)') [${CYAN}Y${NC}]: "
    read -r input_purge
    if [[ ! "$input_purge" =~ ^[Nn] ]]; then
        rm -rf "$CONFIG_DIR" "$DATA_DIR"
        info "$(t 'Config e logs removidos.' 'Config and logs removed.')"
    else
        info "$(t 'Config e logs mantidos.' 'Config and logs kept.')"
    fi
fi

echo ""
info "$(t 'TurboClaude desinstalado.' 'TurboClaude uninstalled.')"
echo ""
