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

# Converts common offset shorthand (UTC-3, -3, GMT+2) to a real IANA
# zone name. Etc/GMT uses the opposite sign of what people mean (a
# POSIX quirk), so that flip happens here once, in one place, and
# whatever you type keeps its normal, intuitive meaning.
resolve_tz() {
    local input
    input="$(echo "$1" | xargs)"
    if [[ "$input" =~ ^(UTC|GMT)?([+-])([0-9]{1,2})$ ]]; then
        if [ "${BASH_REMATCH[2]}" = "-" ]; then
            echo "Etc/GMT+${BASH_REMATCH[3]}"
        else
            echo "Etc/GMT-${BASH_REMATCH[3]}"
        fi
    elif [[ "$input" =~ ^(UTC|GMT)$ ]]; then
        echo "UTC"
    else
        echo "$input"
    fi
}

detect_host_tz() {
    local tz
    tz="$(cat /etc/timezone 2>/dev/null || true)"
    if [ -z "$tz" ]; then
        tz="$(readlink -f /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')"
    fi
    echo "${tz:-UTC}"
}

# Warns and falls back to UTC if the resolved value isn't a real zone
# (e.g. a bare number with no sign, like "3", or a typo). Without this,
# a bad value gets written silently and nothing tells you until the
# schedule quietly fires at the wrong time.
validate_tz() {
    local tz="$1"
    if [ "$tz" = "UTC" ] || [ -f "/usr/share/zoneinfo/$tz" ]; then
        echo "$tz"
    else
        warn "$(t "Timezone '$tz' não reconhecido, usando UTC. Exemplos válidos: America/Sao_Paulo, UTC-3, GMT+2." "Timezone '$tz' not recognized, using UTC. Valid examples: America/Sao_Paulo, UTC-3, GMT+2.")" >&2
        echo "UTC"
    fi
}

# Warns and falls back to the given default if any comma-separated entry
# isn't a real HH:MM (24h). Without this, garbage typed here gets baked
# straight into the cron/systemd schedule with no feedback at all.
validate_times() {
    local times="$1" default="$2" entry
    IFS=',' read -ra _entries <<< "$times"
    for entry in "${_entries[@]}"; do
        entry="$(echo "$entry" | xargs)"
        if ! [[ "$entry" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            warn "$(t "Horário '$entry' inválido (use HH:MM, 24h), usando o padrão: $default" "Invalid time '$entry' (use HH:MM, 24h), using the default: $default")" >&2
            echo "$default"
            return
        fi
    done
    echo "$times"
}

# Same idea for days: "*" or a comma-separated list of Mon/Tue/.../Sun,
# optionally as a "Mon..Fri" range.
validate_days() {
    local days="$1" default="$2" entry
    local day_re='(Mon|Tue|Wed|Thu|Fri|Sat|Sun)'
    if [ "$days" = "*" ]; then
        echo "$days"
        return
    fi
    IFS=',' read -ra _entries <<< "$days"
    for entry in "${_entries[@]}"; do
        entry="$(echo "$entry" | xargs)"
        if ! [[ "$entry" =~ ^${day_re}(\.\.${day_re})?$ ]]; then
            warn "$(t "Dia '$entry' inválido, usando o padrão: $default" "Invalid day '$entry', using the default: $default")" >&2
            echo "$default"
            return
        fi
    done
    echo "$days"
}

# Warns and falls back to the default unless every ;-separated systemd
# OnCalendar expression actually parses (uses systemd-analyze itself as
# the validator, so it's exactly as strict as the real thing).
validate_oncalendar() {
    local expr="$1" default="$2" entry
    if ! command -v systemd-analyze &>/dev/null; then
        echo "$expr"
        return
    fi
    IFS=';' read -ra _entries <<< "$expr"
    for entry in "${_entries[@]}"; do
        entry="$(echo "$entry" | xargs)"
        if [ -z "$entry" ] || ! systemd-analyze calendar "$entry" &>/dev/null; then
            warn "$(t "Expressão OnCalendar '$entry' inválida, usando o padrão: $default" "Invalid OnCalendar expression '$entry', using the default: $default")" >&2
            echo "$default"
            return
        fi
    done
    echo "$expr"
}

# Warns and falls back to the default if the answer isn't recognizable
# as yes/no (a stray typo shouldn't silently flip a Y/n question).
# Empty input (just Enter) is not an error, it means "use the default".
validate_yn() {
    local input="$1" default="$2" label="$3"
    if [ -z "$input" ]; then
        echo "$default"
    elif [[ "$input" =~ ^[YyNn] ]]; then
        echo "$input"
    else
        warn "$(t "Resposta '$input' não reconhecida para '$label', usando o padrão." "Answer '$input' not recognized for '$label', using the default.")" >&2
        echo "$default"
    fi
}

# Warns and falls back to the given default unless the expression looks
# like a real 5-field cron line (minute hour day month weekday).
validate_cron() {
    local expr="$1" default="$2" field field_re
    field_re='^(\*|[0-9]+(-[0-9]+)?)(,(\*|[0-9]+(-[0-9]+)?))*(/[0-9]+)?$'
    local fields
    read -ra fields <<< "$expr"
    if [ "${#fields[@]}" -ne 5 ]; then
        warn "$(t "Expressão cron '$expr' inválida (precisa ter 5 campos), usando o padrão: $default" "Invalid cron expression '$expr' (needs 5 fields), using the default: $default")" >&2
        echo "$default"
        return
    fi
    for field in "${fields[@]}"; do
        if ! [[ "$field" =~ $field_re ]]; then
            warn "$(t "Expressão cron '$expr' inválida, usando o padrão: $default" "Invalid cron expression '$expr', using the default: $default")" >&2
            echo "$default"
            return
        fi
    done
    echo "$expr"
}

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/turbo-claude"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/turbo-claude"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONFIG_FILE="$CONFIG_DIR/turbo-claude.conf"
SCRIPT_DST="$BIN_DIR/turbo-claude"
