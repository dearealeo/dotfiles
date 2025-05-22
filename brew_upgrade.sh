#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
umask 077

readonly LOGFILE="$HOME/Library/Logs/brew_upgrade.log"
readonly STAMP="$HOME/.brew_upgrade_stamp"
readonly RETRY_STAMP="$HOME/.brew_upgrade_retry"
# shellcheck disable=SC2155
readonly TODAY="$(date +%Y-%m-%d)"
readonly BREW_BIN="/opt/homebrew/bin/brew"
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
            [[ -f "$c_log" ]] && { if ((i==MAX_ROTATED_LOGS)); then rm -f "$c_log"; fi; mv "$c_log" "$n_log"; }
        done
        mv "$LOGFILE" "$LOGFILE.1"
    fi
}

trap handle_error ERR
trap 'exit' EXIT

# Concurrency lock (if flock available)
LOCK_F="$STAMP.lock"
if command -v flock >/dev/null 2>&1; then
    exec 200>"$LOCK_F"
    flock -n 200 || exit 0
fi

rotate_log
exec >> "$LOGFILE" 2>&1

[[ -f "$STAMP" && "$(< "$STAMP")" == "$TODAY" ]] && { log "Already executed today ($TODAY)"; exit 0; }
# shellcheck disable=SC2015
command -v "$BREW_BIN" >/dev/null 2>&1 && [[ -x "$BREW_BIN" ]] || { log "Fatal: Homebrew not found or not executable"; exit 1; }

if [[ -f "$RETRY_STAMP" ]]; then
    retry=$(< "$RETRY_STAMP")
    (( retry >= MAX_RETRIES )) && { log "Max retries ($MAX_RETRIES) reached. Deferring."; rm -f "$RETRY_STAMP"; exit 0; }
    log "Retry #$retry"
fi

log "brew update"
LC_ALL=C "$BREW_BIN" update
log "brew upgrade"
LC_ALL=C "$BREW_BIN" upgrade
log "brew cu (cask upgrade)"
LC_ALL=C "$BREW_BIN" cu -a -y
log "brew cleanup"
LC_ALL=C "$BREW_BIN" cleanup --prune=all
log "Operation completed"
printf '%s' "$TODAY" > "$STAMP.tmp" && mv "$STAMP.tmp" "$STAMP"
[[ -f "$RETRY_STAMP" ]] && rm -f "$RETRY_STAMP"
