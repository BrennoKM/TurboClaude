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

HAVE_SYSTEMD=false
command -v systemctl &>/dev/null && systemctl --user show-environment &>/dev/null && HAVE_SYSTEMD=true
HAVE_CRON=false
command -v crontab &>/dev/null && HAVE_CRON=true

if [ "$HAVE_SYSTEMD" = false ] && [ "$HAVE_CRON" = false ]; then
    error "$(t 'Nem systemd nem cron encontrados neste sistema. Instale um dos dois antes de continuar.' 'Neither systemd nor cron found on this system. Install one of them before continuing.')"
    exit 1
fi

# ─── prompt ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}TurboClaude $(t 'Instalador' 'Installer')${NC}"
echo ""

info "$(t 'Certifique-se de que o Claude Code já está autenticado (rode "claude" uma vez e faça login, se ainda não fez). O TurboClaude usa as mesmas credenciais salvas.' 'Make sure Claude Code is already authenticated (run "claude" once and log in, if you have not yet). TurboClaude uses the same saved credentials.')"
echo ""

if [ ! -f /.dockerenv ]; then
    warn "$(t 'Quer rodar em um container Docker (ex: pra instalar pra outras pessoas)? Não use este script direto, use ./docker-new-account.sh <nome> no host, ele cuida disso.' "Want to run this in a Docker container (e.g. to install it for other people)? Don't use this script directly, use ./docker-new-account.sh <name> on the host instead, it handles that.")"
    echo ""
fi

if [ "$HAVE_SYSTEMD" = true ] && [ "$HAVE_CRON" = true ]; then
    ask "$(t 'Qual agendador usar?' 'Which scheduler to use?') [${CYAN}systemd${NC}/cron] [${CYAN}${SCHEDULER:-systemd}${NC}]: "
    read -r input_scheduler || true
    input_scheduler="${input_scheduler:-${SCHEDULER:-}}"
    case "$input_scheduler" in
        cron|Cron|CRON) SCHEDULER="cron" ;;
        *) SCHEDULER="systemd" ;;
    esac
elif [ "$HAVE_SYSTEMD" = true ]; then
    SCHEDULER="systemd"
else
    SCHEDULER="cron"
    warn "$(t 'systemd não disponível neste sistema, usando cron.' 'systemd not available on this system, using cron.')"
fi
info "$(t 'Agendador escolhido' 'Scheduler chosen'): $SCHEDULER"
echo ""

# Every default below falls back to a same-named env var before the
# hardcoded literal, so a non-interactive caller (docker-entrypoint.sh)
# can pre-seed answers and run this with stdin closed (< /dev/null):
# every `read` then gets EOF, keeping the pre-seeded default.
PROMPT_DEFAULT="${PROMPT:-Oi}"
ask "$(t 'Prompt a enviar ao Claude' 'Prompt to send to Claude') [${CYAN}${PROMPT_DEFAULT}${NC}]: "
read -r input_prompt || true
PROMPT="${input_prompt:-$PROMPT_DEFAULT}"

# Asked before the schedule on purpose: "05:00" only means something once
# you know the timezone it's relative to. Matters most on a server whose
# system clock isn't already set to your own timezone (e.g. most VPSes
# default to UTC).
TZ_DEFAULT="${TZ:-$(detect_host_tz)}"
echo "$(t '  Aceita nome IANA (America/Sao_Paulo) ou deslocamento (UTC-3, -3, GMT+2)' '  Accepts an IANA name (America/Sao_Paulo) or an offset (UTC-3, -3, GMT+2)')"
ask "$(t 'Timezone' 'Timezone') [${CYAN}${TZ_DEFAULT}${NC}]: "
read -r input_tz || true
TZ_INPUT="${input_tz:-$TZ_DEFAULT}"
TZ_VALUE="$(resolve_tz "$TZ_INPUT")"
TZ_VALUE="$(validate_tz "$TZ_VALUE")"
if [ "$TZ_VALUE" != "$TZ_INPUT" ]; then
    info "$(t 'Timezone' 'Timezone'): $TZ_INPUT -> $TZ_VALUE"
else
    info "$(t 'Timezone' 'Timezone'): $TZ_VALUE"
fi
echo ""

ADVANCED_DEFAULT="N"
[[ "${ADVANCED:-}" =~ ^[Yy] ]] && ADVANCED_DEFAULT="Y"
ask "$(t 'Modo avançado? Informar a expressão de agendamento manualmente (y/N)' 'Advanced mode? Enter the schedule expression manually (y/N)') [${CYAN}${ADVANCED_DEFAULT}${NC}]: "
read -r input_advanced || true
input_advanced="$(validate_yn "$input_advanced" "$ADVANCED_DEFAULT" "$(t 'modo avançado' 'advanced mode')")"
ADVANCED=false
[[ "$input_advanced" =~ ^[Yy] ]] && ADVANCED=true

if [ "$ADVANCED" = false ]; then
    TIMES_DEFAULT="${TIMES:-05:00,10:00,15:00}"
    ask "$(t 'Horários (24h, separados por vírgula)' 'Schedule times (24h, comma-separated)') [${CYAN}${TIMES_DEFAULT}${NC}]: "
    read -r input_times || true
    TIMES="$(validate_times "${input_times:-$TIMES_DEFAULT}" "$TIMES_DEFAULT")"

    DAYS_DEFAULT="${DAYS:-*}"
    echo "$(t '  Exemplos de dias: * (todo dia), Mon..Fri (dias úteis), Sat,Sun (fim de semana), Mon,Wed,Fri' '  Day examples: * (every day), Mon..Fri (weekdays), Sat,Sun (weekend), Mon,Wed,Fri')"
    ask "$(t 'Dias da semana' 'Days of week') [${CYAN}${DAYS_DEFAULT}${NC}]: "
    read -r input_days || true
    DAYS="$(validate_days "${input_days:-$DAYS_DEFAULT}" "$DAYS_DEFAULT")"
elif [ "$SCHEDULER" = "systemd" ]; then
    ONCALENDAR_DEFAULT="${RAW_ONCALENDAR:-*-*-* 05,10,15:00:00}"
    ask "$(t 'Expressões OnCalendar do systemd (separadas por ;)' 'systemd OnCalendar expressions (semicolon-separated)') [${CYAN}${ONCALENDAR_DEFAULT}${NC}]: "
    read -r input_oncalendar || true
    RAW_ONCALENDAR="$(validate_oncalendar "${input_oncalendar:-$ONCALENDAR_DEFAULT}" "$ONCALENDAR_DEFAULT")"
else
    CRON_DEFAULT="${RAW_CRON:-0 5,10,15 * * *}"
    ask "$(t 'Expressão cron (5 campos)' 'Cron expression (5 fields)') [${CYAN}${CRON_DEFAULT}${NC}]: "
    read -r input_cron || true
    RAW_CRON="$(validate_cron "${input_cron:-$CRON_DEFAULT}" "$CRON_DEFAULT")"
fi

LOG_DEFAULT="Y"
[ "${LOG_RESPONSE:-true}" = "false" ] && LOG_DEFAULT="N"
ask "$(t 'Registrar a resposta do Claude no log? (Y/n)' "Log Claude's response? (Y/n)") [${CYAN}${LOG_DEFAULT}${NC}]: "
read -r input_log || true
input_log="$(validate_yn "$input_log" "$LOG_DEFAULT" "$(t 'registrar log' 'log response')")"
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
if [ "$SCHEDULER" = "systemd" ]; then
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
            # The timezone is appended per systemd.time(7) so the schedule
            # means what you typed regardless of the system's own zone.
            if [ "$DAYS" = "*" ]; then
                ON_CALENDAR+="OnCalendar=${t_val}:00 $TZ_VALUE"$'\n'
            else
                ON_CALENDAR+="OnCalendar=$DAYS ${t_val}:00 $TZ_VALUE"$'\n'
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

else
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

    EXISTING_CRONTAB="$(crontab -l 2>/dev/null | grep -v turbo-claude | grep -v '^CRON_TZ=')"
    if echo "$EXISTING_CRONTAB" | grep -qv '^\s*$\|^#'; then
        warn "$(t "CRON_TZ=$TZ_VALUE vai valer pra TODAS as entradas do seu crontab, não só a do TurboClaude. Se algo mais estiver agendado, confira se o horário continua certo." "CRON_TZ=$TZ_VALUE will apply to ALL entries in your crontab, not just TurboClaude's. If anything else is scheduled there, double-check its time still makes sense.")"
    fi
    (echo "CRON_TZ=$TZ_VALUE"; echo "$EXISTING_CRONTAB"; echo "$CRON_LINE") | crontab -

    echo ""
    info "$(t 'Entrada no crontab adicionada!' 'Crontab entry added!')"
    echo ""
    echo "  edit schedule  crontab -e"
    echo "  view           crontab -l | grep turbo-claude"
    echo "  uninstall      $SCRIPT_DIR/uninstall.sh"
    echo "  test           $SCRIPT_DIR/test.sh"
fi

echo ""
echo -e "${BOLD}$(t 'Resumo' 'Summary')${NC}"
echo "  $(t 'Prompt' 'Prompt'):      $PROMPT"
echo "  $(t 'Timezone' 'Timezone'):    $TZ_VALUE"
echo "  $(t 'Agendador' 'Scheduler'):   $SCHEDULER"
if [ "$ADVANCED" = true ]; then
    [ "$SCHEDULER" = "systemd" ] && echo "  OnCalendar:  $RAW_ONCALENDAR"
    [ "$SCHEDULER" = "cron" ] && echo "  Cron:        $RAW_CRON"
else
    echo "  $(t 'Horários' 'Times'):     $TIMES"
    echo "  $(t 'Dias' 'Days'):        $DAYS"
fi
echo "  $(t 'Log' 'Log'):         $LOG_RESPONSE"
echo "  $(t 'Modelo' 'Model'):      claude-haiku-4-5-20251001 $(t '(padrão, edite o .conf pra trocar)' '(default, edit the .conf to change)')"
echo ""
info "$(t "Pronto. O próximo disparo vai enviar" "Done. Next run will send"): ${PROMPT}"
echo ""

TEST_NOW_DEFAULT="Y"
[ "${TEST_NOW:-true}" = "false" ] && TEST_NOW_DEFAULT="N"
ask "$(t 'Testar agora? (Y/n)' 'Test now? (Y/n)') [${CYAN}${TEST_NOW_DEFAULT}${NC}]: "
read -r input_test || true
input_test="${input_test:-$TEST_NOW_DEFAULT}"
if [[ ! "$input_test" =~ ^[Nn] ]]; then
    "$SCRIPT_DIR/test.sh" --lang "$UI_LANG"
fi
