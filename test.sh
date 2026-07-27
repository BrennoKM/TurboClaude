#!/bin/bash
# TurboClaude - end-to-end test.
#
# Default mode: runs one cycle right now (via systemd/cron path when
# installed, or directly otherwise) and reports whether it worked. This
# proves the *command* works under the scheduler's environment, but does
# not prove the scheduler itself will fire unattended.
#
# --wait N: proves the real unattended path. Temporarily adds an extra
# one-off trigger (in N seconds) alongside the installed timer/cron
# entry -- the original schedule keeps running untouched, so a real
# scheduled run landing inside the test window is not skipped. Waits
# for the extra trigger to fire on its own (nothing is triggered
# manually), then removes it, restoring the original schedule exactly.
#
# Usage: ./test.sh [--lang pt|en] [--direct] [--wait N]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh" "$@"

DIRECT=false
WAIT_SECONDS=""
_args=("$@")
for ((i = 0; i < ${#_args[@]}; i++)); do
    case "${_args[$i]}" in
        --direct) DIRECT=true ;;
        --wait) WAIT_SECONDS="${_args[$((i + 1))]}" ;;
        --wait=*) WAIT_SECONDS="${_args[$i]#*=}" ;;
    esac
done

echo ""
echo -e "${BOLD}TurboClaude $(t 'Teste' 'Test')${NC}"
echo ""

TODAY_LOG="$DATA_DIR/$(date '+%Y-%m-%d').log"

count_lines() {
    [ -f "$TODAY_LOG" ] && wc -l < "$TODAY_LOG" || echo 0
}

# Polls until the run's completion marker (OK/FAIL) shows up in the log,
# not just the "Running" line -- the run itself takes a few seconds.
wait_for_result() {
    local deadline="$1"
    FIRED=false
    RUN_OK=false
    while [ "$SECONDS" -lt "$deadline" ]; do
        if [ -f "$TODAY_LOG" ]; then
            new_content="$(tail -n "+$((LINES_BEFORE + 1))" "$TODAY_LOG")"
            if echo "$new_content" | grep -q '\] OK$'; then
                FIRED=true
                RUN_OK=true
                return
            elif echo "$new_content" | grep -q '\] FAIL'; then
                FIRED=true
                RUN_OK=false
                return
            fi
        fi
        sleep 2
    done
}

HAVE_TIMER=false
command -v systemctl &>/dev/null && systemctl --user cat turbo-claude.timer &>/dev/null && HAVE_TIMER=true
HAVE_CRON_ENTRY=false
command -v crontab &>/dev/null && crontab -l 2>/dev/null | grep -q turbo-claude && HAVE_CRON_ENTRY=true

if [ "$HAVE_TIMER" = true ]; then
    info "$(t 'Agendador ativo: systemd timer' 'Active scheduler: systemd timer')"
elif [ "$HAVE_CRON_ENTRY" = true ]; then
    info "$(t 'Agendador ativo: crontab (fallback)' 'Active scheduler: crontab (fallback)')"
else
    warn "$(t 'Nenhum agendador instalado, rodando o script direto.' 'No scheduler installed, running the script directly.')"
fi

# ─── --wait: prove the real unattended schedule fires ───────────────────────
if [ -n "$WAIT_SECONDS" ]; then
    if [ "$HAVE_TIMER" = false ] && [ "$HAVE_CRON_ENTRY" = false ]; then
        error "$(t 'Nenhum agendador instalado. Rode ./install.sh primeiro.' 'No scheduler installed. Run ./install.sh first.')"
        exit 1
    fi

    LINES_BEFORE=$(count_lines)

    if [ "$HAVE_TIMER" = true ]; then
        TIMER_FILE="$SERVICE_DIR/turbo-claude.timer"
        BACKUP_FILE="$(mktemp)"
        cp "$TIMER_FILE" "$BACKUP_FILE"

        restore_timer() {
            cp "$BACKUP_FILE" "$TIMER_FILE"
            rm -f "$BACKUP_FILE"
            systemctl --user daemon-reload
            systemctl --user restart turbo-claude.timer
        }
        trap restore_timer EXIT

        TARGET="$(date -d "+${WAIT_SECONDS} seconds" '+%Y-%m-%d %H:%M:%S')"
        # Add the test trigger alongside the existing OnCalendar lines
        # instead of replacing the file, so a real scheduled run that
        # happens to land inside the test window is not skipped.
        awk -v extra="OnCalendar=$TARGET" '
            /^\[Timer\]/ { print; print extra; next }
            /^AccuracySec=/ { print "AccuracySec=1s"; next }
            { print }
        ' "$BACKUP_FILE" > "$TIMER_FILE"
        systemctl --user daemon-reload
        systemctl --user restart turbo-claude.timer

        info "$(t "Disparo extra agendado para daqui a ${WAIT_SECONDS}s (${TARGET}), sem mexer no agendamento original. Aguardando o disparo automático..." "Extra trigger scheduled to fire in ${WAIT_SECONDS}s (${TARGET}), without touching the original schedule. Waiting for it to fire on its own...")"

        DEADLINE=$((SECONDS + WAIT_SECONDS + 30))
        wait_for_result "$DEADLINE"
    else
        # cron granularity is whole minutes: round up to the next minute
        # boundary that is at least WAIT_SECONDS away.
        CRON_MIN=$(( (WAIT_SECONDS + 59) / 60 ))
        [ "$CRON_MIN" -lt 1 ] && CRON_MIN=1
        TARGET_EPOCH=$(( $(date +%s) + CRON_MIN * 60 ))
        TARGET_MIN=$(date -d "@$TARGET_EPOCH" '+%M')
        TARGET_HOUR=$(date -d "@$TARGET_EPOCH" '+%H')

        BACKUP_CRONTAB="$(mktemp)"
        crontab -l 2>/dev/null > "$BACKUP_CRONTAB"

        restore_cron() {
            crontab "$BACKUP_CRONTAB"
            rm -f "$BACKUP_CRONTAB"
        }
        trap restore_cron EXIT

        # Appended alongside the existing entry, not replacing it, so a
        # real scheduled run that happens to land inside the test window
        # is not skipped.
        NEW_LINE="$TARGET_MIN $TARGET_HOUR * * * $SCRIPT_DST"
        (cat "$BACKUP_CRONTAB"; echo "$NEW_LINE") | crontab -

        info "$(t "Entrada extra adicionada ao crontab para ${TARGET_HOUR}:${TARGET_MIN} (granularidade mínima de 1 minuto), sem mexer na entrada original. Aguardando o disparo automático..." "Extra crontab entry added for ${TARGET_HOUR}:${TARGET_MIN} (minimum 1-minute granularity), without touching the original entry. Waiting for it to fire on its own...")"

        DEADLINE=$((SECONDS + CRON_MIN * 60 + 90))
        wait_for_result "$DEADLINE"
    fi

    echo ""
    if [ -f "$TODAY_LOG" ]; then
        info "$(t 'Novas linhas de log' 'New log lines'):"
        tail -n "+$((LINES_BEFORE + 1))" "$TODAY_LOG"
    fi

    echo ""
    if [ "$FIRED" = true ] && [ "$RUN_OK" = true ]; then
        info "$(t 'O agendamento disparou sozinho, sem intervenção manual, e a execução terminou com sucesso. Agendador confirmado funcionando.' 'The schedule fired on its own, with no manual trigger, and the run completed successfully. Scheduler confirmed working.')"
        exit 0
    elif [ "$FIRED" = true ]; then
        error "$(t 'O agendamento disparou sozinho, mas a execução falhou. Veja o log acima.' 'The schedule fired on its own, but the run failed. See the log above.')"
        exit 1
    else
        error "$(t 'Tempo esgotado sem disparo. Verifique a configuração do agendador.' 'Timed out with no trigger. Check the scheduler configuration.')"
        exit 1
    fi
fi

# ─── default mode: trigger the service/script once, right now ──────────────
LINES_BEFORE=$(count_lines)

if [ "$DIRECT" = false ] && [ "$HAVE_TIMER" = true ]; then
    info "$(t 'Disparando turbo-claude.service via systemd...' 'Triggering turbo-claude.service via systemd...')"
    systemctl --user start turbo-claude.service --wait
    RESULT=$?
elif [ -x "$SCRIPT_DIR/turbo-claude.sh" ]; then
    info "$(t 'Rodando turbo-claude.sh diretamente...' 'Running turbo-claude.sh directly...')"
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
