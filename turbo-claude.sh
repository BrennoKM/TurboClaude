#!/bin/bash
# TurboClaude - Send a scheduled prompt to Claude CLI.
# https://github.com/BrennoKM/TurboClaude

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/turbo-claude"
CONFIG_FILE="$CONFIG_DIR/turbo-claude.conf"

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

PROMPT="${PROMPT:-Oi, bom dia}"
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

if claude -p "$PROMPT" "${MODEL_ARGS[@]}" >> "$OUT_TARGET" 2>> "$LOG_FILE"; then
    echo "[$(date '+%H:%M:%S')] OK" >> "$LOG_FILE"
else
    s=$?
    echo "[$(date '+%H:%M:%S')] FAIL (exit $s)" >> "$LOG_FILE"
fi
