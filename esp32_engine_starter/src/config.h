#pragma once
// 配線・動作の固定設定。実機に合わせてここを変更する。
#include <stdint.h>

// ---- リモコンのボタン（フォトカプラ経由） ----
// 起動時に勝手にパルスが出ないピン（25/26/27/32/33 など）を使うこと。
// GPIO0/2/12/15（ストラップピン）と GPIO14（起動時に PWM が出る）は避ける。
struct ButtonSpec {
  int pin;
  uint16_t pressMs;  // 押している時間
  uint8_t count;     // 押す回数
  uint16_t gapMs;    // 複数回押すときの間隔
};

// ESL55 の取扱説明書のリモコン操作（長押し秒数など）に合わせて調整する。
// 始動と停止が同じボタンの機種は、同じ pin を指定する。
constexpr ButtonSpec BTN_START = {25, 2500, 1, 0};
constexpr ButtonSpec BTN_STOP = {26, 2500, 1, 0};
constexpr ButtonSpec BTN_LOCK = {27, 400, 1, 0};
constexpr ButtonSpec BTN_UNLOCK = {32, 400, 1, 0};

// 次の操作までの最低間隔（リモコンの送信完了待ち）
constexpr uint32_t ACTION_GAP_MS = 1500;

// ---- バッテリー電圧 ----
// 12V ─ 100kΩ ─┬─ GPIO34
//              22kΩ
//              GND        （15V で約 2.7V。0.1µF を GPIO34-GND 間に入れる）
constexpr int PIN_VBAT = 34;
constexpr float VBAT_DIVIDER = (100.0f + 22.0f) / 22.0f;

constexpr float VBAT_RUNNING_ON = 13.2f;   // オルタネーター発電中 → エンジン稼働とみなす
constexpr float VBAT_RUNNING_OFF = 12.9f;
constexpr float VBAT_LOW = 11.8f;          // この電圧が続いたら低電圧モード
constexpr float VBAT_LOW_RECOVER = 12.4f;
constexpr uint32_t VBAT_LOW_HOLD_MS = 60000;

// 始動後、この時間で稼働判定できなければ「始動未確認」としてログに残す
constexpr uint32_t START_VERIFY_MS = 45000;

// ---- 予備入力（基板 J3、PC817 で絶縁。信号ありで LOW） ----
constexpr int PIN_AUX_IN1 = 33;
constexpr int PIN_AUX_IN2 = 35;  // 内部プルアップなし（基板の 10k でプルアップ）

// ---- I2C（基板 J4） ----
constexpr int PIN_I2C_SDA = 21;
constexpr int PIN_I2C_SCL = 22;

// ---- 時刻 ----
#define TZ_JAPAN "JST-9"
#define NTP_SERVER1 "ntp.nict.jp"
#define NTP_SERVER2 "pool.ntp.org"

// ---- 上限 ----
constexpr int MAX_SCHEDULES = 8;
constexpr int MAX_BEACONS = 4;
