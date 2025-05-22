#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
umask 077

readonly RIME_DIR="$HOME/Library/Rime"
readonly LOGFILE="$HOME/Library/Logs/rime_git_pull.log"
readonly STAMP="$HOME/.rime_git_pull_stamp"
readonly RETRY_STAMP="$HOME/.rime_git_pull_retry"
# shellcheck disable=SC2155
readonly TODAY="$(date +%Y-%m-%d)"
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
[[ -d "$RIME_DIR/.git" ]] || { log "Fatal: $RIME_DIR is not a git repository"; exit 1; }
command -v git >/dev/null 2>&1 || { log "Fatal: git not found"; exit 1; }

if [[ -f "$RETRY_STAMP" ]]; then
    retry=$(< "$RETRY_STAMP")
    (( retry >= MAX_RETRIES )) && { log "Max retries ($MAX_RETRIES) reached. Deferring."; rm -f "$RETRY_STAMP"; exit 0; }
    log "Retry #$retry"
fi

log "Executing git pull in $RIME_DIR"
cd -- "$RIME_DIR"
LC_ALL=C git pull
log "Operation completed"
printf '%s' "$TODAY" > "$STAMP.tmp" && mv "$STAMP.tmp" "$STAMP"
[[ -f "$RETRY_STAMP" ]] && rm -f "$RETRY_STAMP"
