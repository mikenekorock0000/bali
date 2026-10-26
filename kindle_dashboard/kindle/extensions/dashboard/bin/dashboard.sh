#!/bin/sh
# ダッシュボード本体。start.sh から裏で起動される。
. "$(dirname "$0")/common.sh"

echo $$ >"$PID_FILE"
log "start: $SERVER_URL every ${INTERVAL}s"
take_screen

cleanup() {
    log "stop"
    release_screen
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup TERM INT

n=0
fails=0
while true; do
    if wait_for_wifi; then
        url="$SERVER_URL?battery=$(battery_level)&charging=$(is_charging)"
        if download "$url" "$IMG"; then
            full=0
            [ $((n % FULL_REFRESH_EVERY)) -eq 0 ] && full=1
            show_image "$IMG" "$full"
            n=$((n + 1))
            fails=0
        else
            fails=$((fails + 1))
            log "download failed ($fails)"
        fi
    else
        fails=$((fails + 1))
        log "wifi not connected ($fails)"
    fi
    [ $fails -eq 5 ] && show_text "offline: $SERVER_URL"

    if [ "$INTERVAL" -eq 60 ]; then
        # 次の分の 1 秒すぎまで待つ（サーバーが新しい時刻で描く）
        sec=$(date +%S)
        sec=${sec#0}
        sleep $((61 - sec)) &
    else
        sleep "$INTERVAL" &
    fi
    # trap がすぐ動くように sleep を裏で動かして wait する
    wait $!
done
