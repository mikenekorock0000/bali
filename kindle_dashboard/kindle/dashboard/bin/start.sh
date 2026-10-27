#!/bin/sh
# ライブラリの「Dashboard 開始」（Scriptlet）から呼ばれる。ダッシュボードを裏で起動する。
. "$(dirname "$0")/common.sh"

if is_running; then
    log "already running"
    exit 0
fi

# Scriptlet の起動元はこのスクリプトが終わると戻るので、切り離して裏で動かす
detach() {
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$@" </dev/null >>"$LOG_FILE" 2>&1 &
    else
        nohup sh "$@" </dev/null >>"$LOG_FILE" 2>&1 &
    fi
}

detach "$EXT_DIR/bin/dashboard.sh"
if [ "$EXIT_ON_POWER_BUTTON" = 1 ]; then
    detach "$EXT_DIR/bin/watch_power.sh"
fi
