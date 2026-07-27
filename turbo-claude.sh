#!/bin/bash
# TurboClaude - Send a scheduled prompt to Claude CLI.
# https://github.com/BrennoKM/TurboClaude

set -euo pipefail

# systemd --user and cron run with a minimal PATH that usually
# excludes ~/.local/bin, where the claude CLI is typically installed.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/turbo-claude"
CONFIG_FILE="$CONFIG_DIR/turbo-claude.conf"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

PROMPT="${PROMPT:-Oi}"
LOG_DIR="${LOG_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/turbo-claude}"
LOG_RESPONSE="${LOG_RESPONSE:-true}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date '+%Y-%m-%d').log"

echo "[$(date '+%H:%M:%S')] Running: $PROMPT" >> "$LOG_FILE"

if [ "$LOG_RESPONSE" = "true" ]; then
    OUT_TARGET="$LOG_FILE"
else
    OUT_TARGET="/dev/null"
fi

MODEL_ARGS=()
[ -n "$MODEL" ] && MODEL_ARGS=(--model "$MODEL")

if command -v jq &>/dev/null; then
    # --output-format json exposes which model actually answered (modelUsage),
    # so the log can show it instead of trusting --model blindly.
    if RESPONSE_JSON="$(claude -p "$PROMPT" "${MODEL_ARGS[@]}" --output-format json 2>>"$LOG_FILE")"; then
        MODEL_USED="$(echo "$RESPONSE_JSON" | jq -r '(.modelUsage | to_entries[0].value.canonicalModel) // "unknown"' 2>/dev/null || echo "unknown")"
        RESULT_TEXT="$(echo "$RESPONSE_JSON" | jq -r '.result // ""' 2>/dev/null || echo "")"
        if [ "$LOG_RESPONSE" = "true" ]; then
            echo "[$MODEL_USED] $RESULT_TEXT" >> "$LOG_FILE"
        fi
        echo "[$(date '+%H:%M:%S')] OK" >> "$LOG_FILE"
    else
        s=$?
        echo "$RESPONSE_JSON" >> "$LOG_FILE"
        echo "[$(date '+%H:%M:%S')] FAIL (exit $s)" >> "$LOG_FILE"
    fi
else
    if claude -p "$PROMPT" "${MODEL_ARGS[@]}" >> "$OUT_TARGET" 2>> "$LOG_FILE"; then
        echo "[$(date '+%H:%M:%S')] OK" >> "$LOG_FILE"
    else
        s=$?
        echo "[$(date '+%H:%M:%S')] FAIL (exit $s)" >> "$LOG_FILE"
    fi
fi
