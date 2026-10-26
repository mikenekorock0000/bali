#!/bin/sh
# ダッシュボードを終了して通常の Kindle に戻す（KUAL の「Stop」や SSH から）。
. "$(dirname "$0")/common.sh"

if [ -f "$WATCH_PID_FILE" ]; then
    kill "$(cat "$WATCH_PID_FILE")" 2>/dev/null
    rm -f "$WATCH_PID_FILE"
fi

if is_running; then
    kill "$(cat "$PID_FILE")"  # dashboard.sh の trap が画面を戻す
else
    release_screen  # 異常終了していた場合でも UI を戻す
    rm -f "$PID_FILE"
fi
