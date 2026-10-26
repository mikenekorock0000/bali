#!/bin/sh
# 電源ボタン（スリープへ移る通知）を待ち、来たらダッシュボードを終了する。
. "$(dirname "$0")/common.sh"

echo $$ >"$WATCH_PID_FILE"
lipc-wait-event com.lab126.powerd goingToScreenSaver >/dev/null 2>&1
rm -f "$WATCH_PID_FILE"
if is_running; then
    log "power button: exit"
    sh "$EXT_DIR/bin/stop.sh"
fi
