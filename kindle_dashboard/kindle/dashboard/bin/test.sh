#!/bin/sh
# 1 回だけ取得して表示する（接続確認用）。UI は止めないので数秒後に元に戻ることがある。
. "$(dirname "$0")/common.sh"

if ! wait_for_wifi; then
    show_text "Wi-Fi not connected (check airplane mode)"
    exit 1
fi
if download "$SERVER_URL?battery=$(battery_level)&charging=$(is_charging)" "$IMG"; then
    show_image "$IMG" 1
    log "test: ok"
else
    show_text "download failed: $SERVER_URL"
    log "test: download failed"
fi
