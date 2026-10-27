#!/bin/sh
# 共通の変数と関数。各スクリプトから `. "$(dirname "$0")/common.sh"` で読み込む。

EXT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$EXT_DIR/config.sh"

PID_FILE=/var/tmp/kindle-dashboard.pid
WATCH_PID_FILE=/var/tmp/kindle-dashboard-watch.pid
IMG=/var/tmp/kindle-dashboard.png

log() {
    # 100KB を超えたら古いログを捨てる
    if [ -f "$LOG_FILE" ] && [ "$(wc -c <"$LOG_FILE")" -gt 102400 ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"
}

fbink_bin() {
    for f in fbink /mnt/us/libkh/bin/fbink /mnt/us/usbnet/bin/fbink /usr/local/bin/fbink; do
        if command -v "$f" >/dev/null 2>&1; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

# 画像を表示する。$1 = ファイル, $2 = 1 なら全面リフレッシュ
show_image() {
    if FBINK="$(fbink_bin)"; then
        if [ "$2" = 1 ]; then
            "$FBINK" -q -c -f -g file="$1"
        else
            "$FBINK" -q -g file="$1"
        fi
    else
        if [ "$2" = 1 ]; then
            eips -f -g "$1" >/dev/null
        else
            eips -g "$1" >/dev/null
        fi
    fi
}

# 画面に 1 行メッセージを出す（標準フォントは日本語不可なので英数字で）
show_text() {
    if FBINK="$(fbink_bin)"; then
        "$FBINK" -q -y -2 "$1"
    else
        eips 1 38 "$1" >/dev/null
    fi
}

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

battery_level() {
    lipc-get-prop com.lab126.powerd battLevel 2>/dev/null
}

is_charging() {
    lipc-get-prop com.lab126.powerd isCharging 2>/dev/null
}

wifi_connected() {
    [ "$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)" = "CONNECTED" ]
}

wait_for_wifi() {
    wifi_connected && return 0
    lipc-set-prop com.lab126.wifid enable 1 2>/dev/null
    i=0
    while [ $i -lt 30 ]; do
        sleep 1
        wifi_connected && return 0
        i=$((i + 1))
    done
    return 1
}

# $1 の URL を $2 に保存。BusyBox の wget はタイムアウト指定が無い版があるので自前で打ち切る
download() {
    rm -f "$2.part"
    wget -q -O "$2.part" "$1" 2>/dev/null &
    dl_pid=$!
    (sleep 40 && kill "$dl_pid" 2>/dev/null) &
    killer=$!
    wait "$dl_pid"
    rc=$?
    kill "$killer" 2>/dev/null
    # PNG の先頭 4 バイトが "\x89PNG" であることを確認してから置き換える
    if [ $rc -eq 0 ] && [ -s "$2.part" ] && head -c 4 "$2.part" | grep -q PNG; then
        mv "$2.part" "$2"
        return 0
    fi
    rm -f "$2.part"
    return 1
}

# Kindle の UI を止めて画面を占有する
take_screen() {
    lipc-set-prop com.lab126.powerd preventScreenSaver 1
    lipc-set-prop com.lab126.pillow disableEnablePillow disable 2>/dev/null
    if [ "$STOP_MODE" = stop ]; then
        stop lab126_gui 2>/dev/null || /etc/init.d/framework stop
    else
        killall -STOP cvm 2>/dev/null
    fi
    if [ -n "$FRONTLIGHT" ]; then
        lipc-set-prop com.lab126.powerd flIntensity "$FRONTLIGHT" 2>/dev/null
    fi
}

# 画面を Kindle の UI に返す
release_screen() {
    if [ "$STOP_MODE" = stop ]; then
        start lab126_gui 2>/dev/null || /etc/init.d/framework start
    else
        killall -CONT cvm 2>/dev/null
    fi
    lipc-set-prop com.lab126.pillow disableEnablePillow enable 2>/dev/null
    lipc-set-prop com.lab126.powerd preventScreenSaver 0
}
