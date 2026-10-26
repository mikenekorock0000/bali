#!/bin/sh
# KUAL の「Start」から呼ばれる。ダッシュボードを裏で起動する。
. "$(dirname "$0")/common.sh"

if is_running; then
    log "already running"
    exit 0
fi

sh "$EXT_DIR/bin/dashboard.sh" </dev/null >>"$LOG_FILE" 2>&1 &

if [ "$EXIT_ON_POWER_BUTTON" = 1 ]; then
    sh "$EXT_DIR/bin/watch_power.sh" </dev/null >>"$LOG_FILE" 2>&1 &
fi
