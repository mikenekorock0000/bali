// このファイルを config.h という名前でコピーして書き換える（config.h は git に入らない）。
//   cp include/config.example.h include/config.h
// tool/remote_setup.py を使うと、トークンを貼るだけで config.h を作れる。
#pragma once

// ---- Wi-Fi（2.4GHz のみ。5GHz の SSID にはつながらない）
#define WIFI_SSID "your-ssid"
#define WIFI_PASS "your-password"

// ---- SwitchBot（アプリ: プロフィール → 設定 → アプリバージョンを 10 回タップ → 開発者向けオプション）
#define SWITCHBOT_TOKEN "your-token"
#define SWITCHBOT_SECRET "your-secret"

// 室温を表示する機器の deviceId。空ならハブ2（無ければ温湿度計）を自動で探す
#define SENSOR_DEVICE_ID ""

// ---- 学習ボタン（簡易版。ボタンの名前・配置まで決めるなら include/my_layout.h を使う）
// { "アプリでのリモコン名", "ボタン名" } を並べる。名前はアプリの表示と 1 文字も違わないように。
// DIY・その他のリモコンはここに書いたボタンが一覧に出る。
// エアコン・テレビなどの画面でも、画面を長押しすると電源と学習ボタンの一覧になる。
static const char* const CUSTOM_BUTTONS[][2] = {
    // {"リビングの照明", "常夜灯"},
    // {"テレビ", "入力切替"},
    {nullptr, nullptr},  // 最後の印（消さない）
};

// ---- 細かい設定
#define TIMEZONE "JST-9"           // 時計の時刻帯
#define DIM_AFTER_MS 20000         // 操作しないと暗くするまで
#define SLEEP_AFTER_MS 60000       // 画面を消すまで
#define BRIGHTNESS 160             // 画面の明るさ（0〜255）
#define ENCODER_STEPS_PER_CLICK 4  // ダイヤル 1 カチッあたりのカウント（回し方が鈍い/速いときに変える）
#define ENCODER_DIRECTION 1        // 右に回して温度が下がるなら -1
#define SENSOR_INTERVAL_MS 300000  // 室温を取りに行く間隔（5 分）
#define BEEP 1                     // 操作音（0 で無音）
