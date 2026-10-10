#pragma once
// secrets.h にコピーして値を書き換える（secrets.h は git 管理外）。

// 車載 Wi-Fi
#define WIFI_SSID "car-wifi-ssid"
#define WIFI_PASS "car-wifi-password"
#define HOSTNAME "hijet-monitor"

// Wi-Fi 経由のファームウェア更新（ArduinoOTA）のパスワード。必ず変更すること。
#define OTA_PASS "change-me"

// ntfy：通知を受け取るトピックと、スマホから指示を送るトピック。
// トピック名を知っている人は誰でも読み書きできるので、推測されない長いランダムな文字列にする。
#define NTFY_SERVER "https://ntfy.sh"
#define NTFY_TOPIC "hijet-xxxxxxxxxxxxxxxx"
#define NTFY_CMD_TOPIC "hijet-cmd-xxxxxxxxxxxxxxxx"
// 指示の先頭に付ける暗証番号（例："1234 status"）。トピック名が漏れたときの保険。
#define CMD_PIN "1234"

// キーホルダーの BLE ビーコン。MAC アドレス（固定のもの）か iBeacon の UUID で指定する。
//   "aa:bb:cc:dd:ee:ff"
//   "uuid:e2c56db5-dffb-48d2-b060-d0f5a71096e0:1:2"   （:major:minor は省略可）
#define BEACON_RULES {"aa:bb:cc:dd:ee:ff"}
