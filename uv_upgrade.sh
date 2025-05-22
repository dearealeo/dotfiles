#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
umask 077

readonly LOGFILE="$HOME/Library/Logs/uv_upgrade.log"
readonly STAMP="$HOME/.uv_upgrade_stamp"
readonly RETRY_STAMP="$HOME/.uv_upgrade_retry"
# shellcheck disable=SC2155
readonly TODAY="$(date +%Y-%m-%d)"
readonly UV_BIN="/opt/homebrew/bin/uv"
readonly MAX_RETRIES=5
readonly MAX_LOG_SIZE=1048576
readonly MAX_ROTATED_LOGS=1

log() { printf '[%s] %s\n' "$(date +%FT%T)" "$*"; }

handle_error() {
    log "Error at $(caller)"
    local retry=1
    [[ -f "$RETRY_STAMP" ]] && retry=$(( $(< "$RETRY_STAMP") + 1 ))
    printf '%s' "$retry" > "$RETRY_STAMP"
    exit 1
}

rotate_log() {
    mkdir -p "$(dirname -- "$LOGFILE")"
    if [[ -f "$LOGFILE" && $(stat -f%z "$LOGFILE") -ge $MAX_LOG_SIZE ]]; then
        for ((i=MAX_ROTATED_LOGS; i>=1; i--)); do
            local c_log="$LOGFILE.$i"
            local n_log="$LOGFILE.$((i+1))"
            # shellcheck disable=SC2015
            [[ -f "$c_log" ]] && { ((i==MAX_ROTATED_LOGS)) && rm -f "$c_log" || mv "$c_log" "$n_log"; }
        done
        mv "$LOGFILE" "$LOGFILE.1"
    fi
}

trap handle_error ERR
trap 'exit' EXIT

LOCK_F="$STAMP.lock"
if command -v flock >/dev/null 2>&1; then
    exec 200>"$LOCK_F"
    flock -n 200 || exit 0
fi

rotate_log
exec >> "$LOGFILE" 2>&1

[[ -f "$STAMP" && "$(< "$STAMP")" == "$TODAY" ]] && { log "Already executed today ($TODAY)"; exit 0; }
# shellcheck disable=SC2015
command -v "$UV_BIN" >/dev/null 2>&1 && [[ -x "$UV_BIN" ]] || { log "Fatal: $UV_BIN not found or not executable"; exit 1; }

if [[ -f "$RETRY_STAMP" ]]; then
    retry=$(< "$RETRY_STAMP")
    (( retry >= MAX_RETRIES )) && { log "Max retries ($MAX_RETRIES) reached. Deferring."; rm -f "$RETRY_STAMP"; exit 0; }
    log "Retry #$retry"
fi

log "Listing installed tools"
TOOLS=$(LC_ALL=C "$UV_BIN" tool list | awk 'NR>1 && $1 ~ /^[a-zA-Z0-9]/ {print $1}')
if [[ -z "$TOOLS" ]]; then
    log "No tools installed, nothing to upgrade"
else
    log "Found installed tools, proceeding with upgrades"
    while IFS= read -r tool; do
        [[ -z "$tool" || "$tool" == "-" ]] && continue
        [[ ! "$tool" =~ ^[a-zA-Z0-9] ]] && continue
        log "Upgrading: $tool"
        "$UV_BIN" tool upgrade "$tool" 2>/dev/null || log "Warning: Failed to upgrade $tool, continuing"
    done < <(printf '%s\n' "$TOOLS")
fi
printf '%s' "$TODAY" > "$STAMP.tmp" && mv "$STAMP.tmp" "$STAMP"
[[ -f "$RETRY_STAMP" ]] && rm -f "$RETRY_STAMP"
log "Operation completed"
