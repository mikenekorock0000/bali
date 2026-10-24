#pragma once
// 初めて起動したときの設定の初期値（なくてもよい）。
// 設定は、ESP32 の設定モード（Wi-Fi「HIJET-SETUP-xxxx」につないで開く画面）から入力・変更できる。
// 机の上で何度も書き込み直すときに毎回入力しなくて済むよう、ここに書いておくこともできる。
// 使うときは secrets.h にコピーして値を書き換える（secrets.h は git 管理外）。
// 一度保存された設定は ESP32 の中に残り、このファイルの値では上書きされない。

// Wi-Fi（車内のテザリングなど）
#define WIFI_SSID "car-wifi-ssid"
#define WIFI_PASS "car-wifi-password"
#define HOSTNAME "hijet-monitor"

// Wi-Fi 経由のファームウェア更新（ArduinoOTA）のパスワード（8 文字以上）。必ず変更すること。
#define OTA_PASS "change-me-please"

// ntfy：通知のトピック（スマホのアプリで購読）、指示のトピック、状態のトピック（ダッシュボード用）。
// トピック名を知っている人は誰でも読み書きできるので、推測されない長いランダムな文字列にする。
#define NTFY_SERVER "https://ntfy.sh"
#define NTFY_TOPIC "hijet-xxxxxxxxxxxxxxxx"
#define NTFY_CMD_TOPIC "hijet-cmd-xxxxxxxxxxxxxxxx"
#define NTFY_STATE_TOPIC "hijet-state-xxxxxxxxxxxxxxxx"
// ntfy のアカウントのアクセストークン（使わなければ空のまま）
#define NTFY_TOKEN ""
// 指示の先頭に付ける暗証番号（数字 4〜8 桁。例："1234 status"）。設定画面の保存にも使う。
#define CMD_PIN "1234"

// キーホルダーの BLE ビーコン。MAC アドレス（固定のもの）か iBeacon の UUID で指定する。
//   "aa:bb:cc:dd:ee:ff"
//   "uuid:e2c56db5-dffb-48d2-b060-d0f5a71096e0:1:2"   （:major:minor は省略可）
#define BEACON_RULES {"aa:bb:cc:dd:ee:ff"}
