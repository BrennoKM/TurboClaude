#!/bin/bash
# Container startup: runs the *same* install.sh a human would run, just
# non-interactively. install.sh's prompts all default to the matching
# env var (PROMPT, TIMES, DAYS, LOG_RESPONSE, TEST_NOW) when set, so with
# stdin closed every `read` hits EOF immediately and keeps that default.
# No separate install path, no fake keystrokes.
set -euo pipefail

export TEST_NOW="${TEST_NOW:-false}"

if [ ! -f "$XDG_CONFIG_HOME/turbo-claude/turbo-claude.conf" ]; then
    /opt/turbo-claude/install.sh < /dev/null
fi

echo ""
echo "TurboClaude running. Crontab:"
crontab -l

# dcron mails job output instead of echoing it to its own stdout, and
# this image has no mailer, so runs would otherwise be invisible to
# `docker logs`. Follow today's log file into the container's stdout
# instead, re-pointing to the new file at each day's rollover.
LOG_DIR="$XDG_DATA_HOME/turbo-claude"
mkdir -p "$LOG_DIR"
(
    while true; do
        LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d').log"
        touch "$LOG_FILE"
        tail -n0 -F "$LOG_FILE" &
        TAIL_PID=$!
        SLEEP_SECS=$(( $(date -d 'tomorrow 00:00:00' '+%s') - $(date '+%s') ))
        sleep "$SLEEP_SECS"
        kill "$TAIL_PID" 2>/dev/null || true
    done
) &

exec crond -f -l 5
