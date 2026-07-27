#!/bin/bash
# TurboClaude installer
# https://github.com/BrennoKM/TurboClaude
#
# Installs turbo-claude.sh, configures the prompt,
# and sets up a systemd user timer (with cron fallback)
# to run at your chosen schedule.

set -euo pipefail

# ─── helpers ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}::${NC} $*"; }
warn()  { echo -e "${YELLOW}!!${NC} $*"; }
error() { echo -e "${RED}EE${NC} $*"; }
ask()   { echo -en "${CYAN}??${NC} $*"; }

# ─── paths ────────────────────────────────────────────────────────────────────
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/turbo-claude"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/turbo-claude"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

SCRIPT_SRC="$(dirname "$0")/turbo-claude.sh"
SCRIPT_DST="$BIN_DIR/turbo-claude"

# ─── checks ──────────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
    error "claude CLI not found. Install it first:"
    echo "  https://docs.anthropic.com/en/docs/claude-code/overview"
    exit 1
fi

# ─── prompt ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}TurboClaude Installer${NC}"
echo ""

ask "Prompt to send to Claude [${CYAN}Oi, bom dia${NC}]: "
read -r input_prompt
PROMPT="${input_prompt:-Oi, bom dia}"

ask "Schedule times (24h, comma-separated) [${CYAN}05:00,10:00,15:00${NC}]: "
read -r input_times
TIMES="${input_times:-05:00,10:00,15:00}"

ask "Days of week (comma-separated, 3-letter) [${CYAN}Mon..Fri${NC}]: "
read -r input_days
DAYS="${input_days:-Mon..Fri}"

ask "Log Claude's response? (Y/n) [${CYAN}Y${NC}]: "
read -r input_log
LOG_RESPONSE=true
[[ "$input_log" =~ ^[Nn] ]] && LOG_RESPONSE=false

echo ""

# ─── directories ─────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" "$SERVICE_DIR"

# ─── config ──────────────────────────────────────────────────────────────────
cat > "$CONFIG_DIR/turbo-claude.conf" << CONF
# TurboClaude configuration
# Sourced by turbo-claude.sh on each run.

PROMPT="$PROMPT"
LOG_DIR="$DATA_DIR"
LOG_RESPONSE=$LOG_RESPONSE
CONF

info "Config: $CONFIG_DIR/turbo-claude.conf"

# ─── script ──────────────────────────────────────────────────────────────────
if [ ! -f "$SCRIPT_SRC" ]; then
    error "$SCRIPT_SRC not found. Run install.sh from the TurboClaude directory."
    exit 1
fi

cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"
info "Script: $SCRIPT_DST"

# ─── systemd timer ───────────────────────────────────────────────────────────
if command -v systemctl &>/dev/null; then
    # Build OnCalendar lines from user times
    ON_CALENDAR=""
    IFS=',' read -ra TIME_LIST <<< "$TIMES"
    for t in "${TIME_LIST[@]}"; do
        t="$(echo "$t" | xargs)"  # trim
        ON_CALENDAR+="OnCalendar=$DAYS ${t}:00"$'\n'
    done

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

    systemctl --user daemon-reload
    systemctl --user enable turbo-claude.timer
    systemctl --user start turbo-claude.timer
    systemctl --user enable turbo-claude.service

    # Enable lingering so the timer runs even when no one is logged in
    if command -v loginctl &>/dev/null; then
        loginctl enable-linger "$USER" 2>/dev/null || true
    fi

    echo ""
    info "systemd timer installed and started!"
    echo ""
    echo "  status         systemctl --user status turbo-claude.timer"
    echo "  logs           journalctl --user -u turbo-claude.service -n 20"
    echo "  next runs      systemctl --user list-timers turbo-claude.timer"
    echo "  edit schedule  systemctl --user edit turbo-claude.timer"
    echo "  stop           systemctl --user stop turbo-claude.timer"
    echo "  disable        systemctl --user disable turbo-claude.timer"

elif command -v crontab &>/dev/null; then
    warn "systemd not found -- falling back to cron"

    # Convert 05:00,10:00 -> 0 5,10 * * ...
    CRON_HOURS=""
    CRON_MINUTES=""
    IFS=',' read -ra TIME_LIST <<< "$TIMES"
    for t in "${TIME_LIST[@]}"; do
        t="$(echo "$t" | xargs)"
        hour="${t%%:*}"
        min="${t##*:}"
        CRON_HOURS="${CRON_HOURS:+$CRON_HOURS,}$hour"
        CRON_MINUTES="${CRON_MINUTES:+$CRON_MINUTES,}$min"
    done

    # Convert Mon..Fri to 1-5
    CRON_DOW="*"
    if echo "$DAYS" | grep -qi "mon.*fri"; then
        CRON_DOW="1-5"
    fi

    (crontab -l 2>/dev/null | grep -v turbo-claude; echo "$CRON_MINUTES $CRON_HOURS * * $CRON_DOW $SCRIPT_DST") | crontab -

    echo ""
    info "Crontab entry added!"
    echo ""
    echo "  edit schedule  crontab -e"
    echo "  view           crontab -l | grep turbo-claude"
else
    warn "No scheduler found. Set up scheduling manually (see README)."
fi

echo ""
info "Done. Next run will send: ${PROMPT}"
echo ""
