#!/bin/bash
# TurboClaude - shared helpers (i18n, paths, colors).
# Sourced by install.sh, uninstall.sh and test.sh.

UI_LANG=""
_lib_args=("$@")
for ((i = 0; i < ${#_lib_args[@]}; i++)); do
    case "${_lib_args[$i]}" in
        --lang) UI_LANG="${_lib_args[$((i + 1))]}" ;;
        --lang=*) UI_LANG="${_lib_args[$i]#*=}" ;;
    esac
done
if [ -z "$UI_LANG" ]; then
    case "${TURBO_CLAUDE_LANG:-${LC_ALL:-${LANG:-}}}" in
        pt*) UI_LANG="pt" ;;
        *) UI_LANG="en" ;;
    esac
fi

# t <pt> <en> - returns the string for the active UI language.
t() {
    if [ "$UI_LANG" = "pt" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}::${NC} $*"; }
warn()  { echo -e "${YELLOW}!!${NC} $*"; }
error() { echo -e "${RED}EE${NC} $*"; }
ask()   { echo -en "${CYAN}??${NC} $*"; }

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/turbo-claude"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/turbo-claude"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONFIG_FILE="$CONFIG_DIR/turbo-claude.conf"
SCRIPT_DST="$BIN_DIR/turbo-claude"
