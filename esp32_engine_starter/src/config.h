#pragma once
// 基板（HIJET MONITOR v3）の配線と、動作のしきい値。実機に合わせてここを変更する。
#include <stdint.h>

// ---- 絶縁出力（基板 J2、PC817。HIGH で出力 ON） ----
constexpr int PIN_OUT_LOCK = 25;  // 車両の施錠信号
constexpr int PIN_OUT2 = 26;
constexpr int PIN_OUT3 = 27;
constexpr int PIN_OUT4 = 32;
constexpr uint32_t LOCK_PULSE_MS = 400;  // 施錠信号を出す時間（車両の施錠スイッチを押す時間に相当）

// ---- 絶縁入力（基板 J3、PC817。信号ありで LOW） ----
constexpr int PIN_DOOR = 33;  // IN1：ドア開閉（開で信号あり）
constexpr int PIN_IN2 = 35;   // IN2：予備（内部プルアップなし、基板の 10k でプルアップ）
constexpr int PIN_ACC = 36;   // IN3：ACC（キー ON で信号あり。内部プルアップなし）
// GPIO36 は Wi-Fi/ADC 使用中に一瞬ノイズが乗る既知の不具合があるため、長めに確定させる
constexpr uint32_t DOOR_DEBOUNCE_MS = 80;
constexpr uint32_t ACC_DEBOUNCE_MS = 300;

// ---- バッテリー電圧（12V ─ 100k ─ GPIO34 ─ 18k ─ GND。16V で 2.44V＝ADC の精度のよい範囲内） ----
constexpr int PIN_VBAT = 34;
constexpr float VBAT_DIVIDER = (100.0f + 18.0f) / 18.0f;
constexpr float VBAT_CAL = 1.00f;  // テスターの実測値 ÷ 表示値 で補正する
constexpr float VBAT_RUNNING_ON = 13.2f;  // OBD が無いときのエンジン稼働判定（発電中の電圧）
constexpr float VBAT_RUNNING_OFF = 12.9f;
constexpr float VBAT_LOW = 11.8f;          // この電圧が 1 分続いたら低電圧通知・省電力
constexpr float VBAT_LOW_RECOVER = 12.4f;
constexpr uint32_t VBAT_LOW_HOLD_MS = 60000;
constexpr float VBAT_SLEEP = 11.5f;          // これ以下でエンジン停止中ならディープスリープ
constexpr uint32_t SLEEP_WAKE_SEC = 30 * 60; // スリープ中に電圧を見に起きる間隔
constexpr float CRANK_WEAK_V = 9.6f;         // 始動時にこれを下回ったら「バッテリーが弱っている」
constexpr float CHARGE_MIN_V = 13.0f;        // 稼働中にこれ未満が 1 分続いたら充電不良

// ---- OBD-II（CAN、基板 U9 MCP2562） ----
constexpr int PIN_CAN_TX = 18;
constexpr int PIN_CAN_RX = 19;
constexpr int PIN_CAN_STBY = 4;  // LOW で動作、HIGH（基板の 10k で既定）で待機＝バスに関与しない
constexpr bool OBD_ENABLED = true;
constexpr uint32_t OBD_POLL_MS = 500;         // 1 要求あたりの間隔（車両への負担を抑える）
constexpr float COOLANT_WARN_C = 105.0f;      // 水温がこれを超えたら緊急通知

// ---- ブザー（基板 BZ1、HIGH で鳴る） ----
constexpr int PIN_BUZZER = 13;

// ---- GPS（UART2、基板 J8） ----
constexpr int PIN_GPS_TX = 17;  // ESP32 → GPS の RX
constexpr int PIN_GPS_RX = 16;  // GPS の TX → ESP32
constexpr uint32_t GPS_BAUD = 9600;

// ---- I2C（基板 J4）：BME280（温湿度）、MPU6050（振動） ----
constexpr int PIN_I2C_SDA = 21;
constexpr int PIN_I2C_SCL = 22;
constexpr float CABIN_HOT_C = 45.0f;   // 車内がこれを超えたら通知
constexpr float CABIN_COLD_C = -5.0f;  // これを下回ったら通知（凍結注意）
constexpr float MOTION_G = 0.12f;      // 警戒中、加速度の変化がこれを超えたら振動とみなす

// ---- 自動ロック・防犯 ----
constexpr uint32_t ABSENT_TIMEOUT_MS = 30000;  // キーの電波が弱いまま 30 秒で「離れた」
constexpr int NEAR_RSSI = -75;                 // これより強く受信したら「近くに来た」
constexpr int FAR_RSSI = -90;                  // これより弱い受信は圏外扱い
constexpr uint32_t DOOR_OPEN_WARN_MS = 5 * 60 * 1000UL;  // キーが無いままドアが開いている時間
constexpr uint32_t ALARM_SOUND_MS = 20000;               // 侵入検知時にブザーを鳴らす時間

// ---- エンジン稼働時間とメンテナンス ----
constexpr float OIL_CHANGE_HOURS = 150.0f;  // 前回リセットからこの稼働時間で交換時期を通知

// ---- 通知（ntfy） ----
constexpr uint32_t CMD_POLL_MS = 30000;          // コマンド用トピックを読みに行く間隔
constexpr int DAILY_REPORT_HOUR = 20;  // 毎日この時刻（日本時間）に状態を報告。-1 で無効
#define TZ_JAPAN "JST-9"
#define NTP_SERVER1 "ntp.nict.jp"
#define NTP_SERVER2 "pool.ntp.org"

constexpr int MAX_BEACONS = 4;
