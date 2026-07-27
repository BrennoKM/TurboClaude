#!/bin/bash
# TurboClaude installer
# https://github.com/BrennoKM/TurboClaude
#
# Installs turbo-claude.sh, configures the prompt,
# and sets up a systemd user timer (with cron fallback)
# to run at your chosen schedule.
#
# Usage: ./install.sh [--lang pt|en]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" "$@"

SCRIPT_SRC="$SCRIPT_DIR/turbo-claude.sh"

# ─── checks ──────────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
    error "$(t 'claude CLI não encontrado. Instale primeiro:' 'claude CLI not found. Install it first:')"
    echo "  https://docs.anthropic.com/en/docs/claude-code/overview"
    exit 1
fi

# ─── prompt ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}TurboClaude $(t 'Instalador' 'Installer')${NC}"
echo ""

ask "$(t 'Prompt a enviar ao Claude' 'Prompt to send to Claude') [${CYAN}Oi${NC}]: "
read -r input_prompt
PROMPT="${input_prompt:-Oi}"

ask "$(t 'Modo avançado? Informar a expressão de agendamento manualmente (y/N)' 'Advanced mode? Enter the schedule expression manually (y/N)') [${CYAN}N${NC}]: "
read -r input_advanced
ADVANCED=false
[[ "$input_advanced" =~ ^[Yy] ]] && ADVANCED=true

if [ "$ADVANCED" = false ]; then
    ask "$(t 'Horários (24h, separados por vírgula)' 'Schedule times (24h, comma-separated)') [${CYAN}05:00,10:00,15:00${NC}]: "
    read -r input_times
    TIMES="${input_times:-05:00,10:00,15:00}"

    echo "$(t '  Exemplos de dias: * (todo dia), Mon..Fri (dias úteis), Sat,Sun (fim de semana), Mon,Wed,Fri' '  Day examples: * (every day), Mon..Fri (weekdays), Sat,Sun (weekend), Mon,Wed,Fri')"
    ask "$(t 'Dias da semana' 'Days of week') [${CYAN}*${NC}]: "
    read -r input_days
    DAYS="${input_days:-*}"
else
    ask "$(t 'Expressões OnCalendar do systemd (separadas por ;)' 'systemd OnCalendar expressions (semicolon-separated)') [${CYAN}*-*-* 05,10,15:00:00${NC}]: "
    read -r input_oncalendar
    RAW_ONCALENDAR="${input_oncalendar:-*-*-* 05,10,15:00:00}"

    ask "$(t 'Expressão cron (fallback, 5 campos)' 'Cron expression (fallback, 5 fields)') [${CYAN}0 5,10,15 * * *${NC}]: "
    read -r input_cron
    RAW_CRON="${input_cron:-0 5,10,15 * * *}"
fi

ask "$(t 'Registrar a resposta do Claude no log? (Y/n)' "Log Claude's response? (Y/n)") [${CYAN}Y${NC}]: "
read -r input_log
LOG_RESPONSE=true
[[ "$input_log" =~ ^[Nn] ]] && LOG_RESPONSE=false

echo ""

# ─── directories ─────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" "$SERVICE_DIR"

# ─── config ──────────────────────────────────────────────────────────────────
cat > "$CONFIG_FILE" << CONF
# TurboClaude configuration
# Sourced by turbo-claude.sh on each run.

PROMPT="$PROMPT"
LOG_DIR="$DATA_DIR"
LOG_RESPONSE=$LOG_RESPONSE
# MODEL="claude-haiku-4-5-20251001" is the default, uncomment to override
CONF

info "$(t 'Config' 'Config'): $CONFIG_FILE"

# ─── script ──────────────────────────────────────────────────────────────────
if [ ! -f "$SCRIPT_SRC" ]; then
    error "$(t "$SCRIPT_SRC não encontrado. Rode o install.sh a partir da pasta do TurboClaude." "$SCRIPT_SRC not found. Run install.sh from the TurboClaude directory.")"
    exit 1
fi

cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"
info "$(t 'Script' 'Script'): $SCRIPT_DST"

# ─── systemd timer ───────────────────────────────────────────────────────────
if command -v systemctl &>/dev/null; then
    ON_CALENDAR=""
    if [ "$ADVANCED" = true ]; then
        IFS=';' read -ra CAL_LIST <<< "$RAW_ONCALENDAR"
        for c in "${CAL_LIST[@]}"; do
            c="$(echo "$c" | xargs)"
            [ -n "$c" ] && ON_CALENDAR+="OnCalendar=$c"$'\n'
        done
    else
        IFS=',' read -ra TIME_LIST <<< "$TIMES"
        for t_val in "${TIME_LIST[@]}"; do
            t_val="$(echo "$t_val" | xargs)"
            # "*" means every day: systemd expects the weekday field to be
            # omitted for that, not a literal "*" (that fails to parse).
            if [ "$DAYS" = "*" ]; then
                ON_CALENDAR+="OnCalendar=${t_val}:00"$'\n'
            else
                ON_CALENDAR+="OnCalendar=$DAYS ${t_val}:00"$'\n'
            fi
        done
    fi

    cat > "$SERVICE_DIR/turbo-claude.service" << SERVICE
[Unit]
Description=TurboClaude scheduled message
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/turbo-claude

[Install]
WantedBy=default.target
SERVICE

    cat > "$SERVICE_DIR/turbo-claude.timer" << TIMER
[Unit]
Description=TurboClaude schedule

[Timer]
$ON_CALENDAR
AccuracySec=1min

[Install]
WantedBy=timers.target
TIMER

    # Validate before enabling, so a bad expression fails loudly here
    # instead of silently as "Cannot add dependency job" later.
    if ! systemd-analyze --user verify "$SERVICE_DIR/turbo-claude.timer" 2>/tmp/turbo-claude-verify.log; then
        error "$(t 'Expressão de agendamento inválida:' 'Invalid schedule expression:')"
        cat /tmp/turbo-claude-verify.log >&2
        rm -f /tmp/turbo-claude-verify.log
        exit 1
    fi
    rm -f /tmp/turbo-claude-verify.log

    systemctl --user daemon-reload
    systemctl --user enable turbo-claude.timer
    systemctl --user start turbo-claude.timer
    systemctl --user enable turbo-claude.service

    # Enable lingering so the timer runs even when no one is logged in
    if command -v loginctl &>/dev/null; then
        loginctl enable-linger "$USER" 2>/dev/null || true
    fi

    echo ""
    info "$(t 'Timer do systemd instalado e iniciado!' 'systemd timer installed and started!')"
    echo ""
    echo "  status         systemctl --user status turbo-claude.timer"
    echo "  logs           journalctl --user -u turbo-claude.service -n 20"
    echo "  next runs      systemctl --user list-timers turbo-claude.timer"
    echo "  edit schedule  systemctl --user edit turbo-claude.timer"
    echo "  stop           systemctl --user stop turbo-claude.timer"
    echo "  disable        systemctl --user disable turbo-claude.timer"
    echo "  uninstall      $SCRIPT_DIR/uninstall.sh"
    echo "  test           $SCRIPT_DIR/test.sh"

elif command -v crontab &>/dev/null; then
    warn "$(t 'systemd não encontrado, usando cron como fallback' 'systemd not found -- falling back to cron')"

    if [ "$ADVANCED" = true ]; then
        CRON_LINE="$RAW_CRON $SCRIPT_DST"
    else
        CRON_HOURS=""
        CRON_MINUTES=""
        IFS=',' read -ra TIME_LIST <<< "$TIMES"
        for t_val in "${TIME_LIST[@]}"; do
            t_val="$(echo "$t_val" | xargs)"
            hour="${t_val%%:*}"
            min="${t_val##*:}"
            CRON_HOURS="${CRON_HOURS:+$CRON_HOURS,}$hour"
            CRON_MINUTES="${CRON_MINUTES:+$CRON_MINUTES,}$min"
        done

        # cron uses "-" for ranges, systemd-style input uses "..".
        CRON_DOW="${DAYS//../-}"

        CRON_LINE="$CRON_MINUTES $CRON_HOURS * * $CRON_DOW $SCRIPT_DST"
    fi

    (crontab -l 2>/dev/null | grep -v turbo-claude; echo "$CRON_LINE") | crontab -

    echo ""
    info "$(t 'Entrada no crontab adicionada!' 'Crontab entry added!')"
    echo ""
    echo "  edit schedule  crontab -e"
    echo "  view           crontab -l | grep turbo-claude"
    echo "  uninstall      $SCRIPT_DIR/uninstall.sh"
    echo "  test           $SCRIPT_DIR/test.sh"
else
    warn "$(t 'Nenhum agendador encontrado. Configure manualmente (veja o README).' 'No scheduler found. Set up scheduling manually (see README).')"
fi

echo ""
info "$(t "Pronto. O próximo disparo vai enviar" "Done. Next run will send"): ${PROMPT}"
echo ""

ask "$(t 'Testar agora? (Y/n)' 'Test now? (Y/n)') [${CYAN}Y${NC}]: "
read -r input_test
if [[ ! "$input_test" =~ ^[Nn] ]]; then
    "$SCRIPT_DIR/test.sh" --lang "$UI_LANG"
fi
