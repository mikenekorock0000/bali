#pragma once
// 基板（HIJET MONITOR v4）の配線と、動作のしきい値。実機に合わせてここを変更する。
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

// ---- バッテリー電圧（12V ─ 100k ─ GPIO34 ─ 10k ─ GND。16V で 1.45V＝ADC の精度のよい範囲内） ----
// R2 を変えたら下の分圧比も変えること（R2 は 18k 以下。それより大きいと 16V で ADC の精度範囲を超える）
constexpr int PIN_VBAT = 34;
constexpr float VBAT_DIVIDER = (100.0f + 10.0f) / 10.0f;
// 電圧の補正係数（テスターの実測値 ÷ 表示値）は設定画面で入力する（settings.vbatCal）
constexpr float VBAT_RUNNING_ON = 13.2f;  // OBD が無いときのエンジン稼働判定（発電中の電圧）
constexpr float VBAT_RUNNING_OFF = 12.9f;
constexpr float VBAT_LOW = 11.8f;          // この電圧が 1 分続いたら低電圧通知・省電力
constexpr float VBAT_LOW_RECOVER = 12.4f;
constexpr uint32_t VBAT_LOW_HOLD_MS = 60000;
constexpr float VBAT_SLEEP = 11.5f;          // これ以下でエンジン停止中ならディープスリープ
constexpr float VBAT_BENCH = 6.0f;           // これ未満は 12V をつないでいない（USB だけの机の上）。基板の 5V レギュレータは約 7V 以上で動くので、実車ではありえない
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

// ---- 駐車モード（キーが離れて施錠した後はディープスリープして、駐車中の消費電流を減らす） ----
// 眠っている間：ドアが開く・ACC ON で即座に起きる。PARK_WAKE_SEC ごとに起きて指示の確認・電圧の確認をする。
// 振動検知（MPU6050）は眠っている間は働かない。
constexpr bool PARK_SLEEP_DEFAULT = true;            // 初期値（指示 "park on|off" で切り替え）
constexpr uint32_t PARK_IDLE_MS = 10 * 60000UL;      // キーが離れてからこの時間たったら眠る
constexpr uint32_t PARK_WAKE_SEC = 15 * 60;          // 眠っている間に起きる間隔（指示の反映はこの分だけ遅れる）
constexpr uint32_t PARK_KEY_SCAN_MS = 10000;         // 時間で起きたとき、キーを探す時間
constexpr uint32_t PARK_AWAKE_MAX_MS = 45000;        // 時間で起きたときに起きている最長時間（Wi-Fi が無くても眠る）
constexpr uint32_t DOOR_WAKE_GRACE_MS = 15000;       // ドアで起きたとき、キーが見つかるまで待つ時間

// ---- 設定モード（ESP32 が Wi-Fi「HIJET-SETUP-xxxx」を出し、スマホから設定する） ----
#define SETUP_AP_PASS "hijet-setup"                 // 設定モードの Wi-Fi のパスワード（8 文字以上）
constexpr uint32_t SETUP_TIMEOUT_MS = 10 * 60000UL;  // 設定済みなら、この時間で設定モードを終える
constexpr int PIN_MAX_FAILS = 5;                     // 設定画面で暗証番号をこの回数続けて間違えたらロック
constexpr uint32_t PIN_LOCK_MS = 5 * 60000UL;        // ロックの時間（ロックのたびに倍、上限 1 時間）
constexpr uint32_t PIN_LOCK_MAX_MS = 60 * 60000UL;
constexpr int PIN_SETUP_BUTTON = 0;                  // DevKit の BOOT ボタン（押すと LOW）
constexpr uint32_t SETUP_HOLD_MS = 3000;             // この時間押し続けると設定モード
constexpr uint32_t WIFI_FAIL_SETUP_MS = 3 * 60000UL; // ACC ON のままこの時間 Wi-Fi につながらなければ設定モード
constexpr uint32_t WIFI_SWITCH_MS = 20000;           // つながらないとき、予備の Wi-Fi と交互に試す間隔

// ---- ダッシュボード（状態のトピックに JSON を送る） ----
#define FW_VERSION "1.2.2"
// ntfy.sh の無料の範囲は 1 日 250 件（送り元の IP ごと）。通知を優先し、状態の送信はその内に収める
constexpr uint32_t STATE_PUBLISH_MS = 15 * 60000UL;  // 起きている間に状態を送る間隔（1 日 96 件）
constexpr uint32_t STATE_MIN_GAP_MS = 60000;         // 出来事のたびに送るときの最短間隔
constexpr int NTFY_DAILY_SOFT = 180;                 // 24 時間にこの件数を送ったら、状態の送信を減らす
constexpr uint32_t STATE_SLOW_MS = 60 * 60000UL;     // そのときの状態の送信間隔
constexpr uint32_t HIST_INTERVAL_SEC = 15 * 60;      // 電圧・温度の履歴を記録する間隔
constexpr int HIST_POINTS = 96;                      // 履歴の点数（15 分 × 96 ＝ 24 時間）

// ---- 見張り（ウォッチドッグ）・ファームウェア更新の確認 ----
constexpr uint32_t WDT_TIMEOUT_S = 30;               // main loop がこの時間止まったら再起動する
constexpr uint32_t OTA_VERIFY_MS = 10 * 60000UL;     // 更新後、この時間内に ntfy と通信できなければ前の版に戻す
constexpr uint32_t OTA_MIN_RUN_MS = 60000;           // 少なくともこの時間は動いてから「正常」とする

// ---- 指示の署名（ダッシュボードから送る指示は、時刻と署名付き） ----
constexpr uint32_t CMD_MAX_AGE_SEC = 30 * 60;        // これより古い指示は無視（駐車モードの 15 分の遅れを見込む）
constexpr uint32_t CMD_MAX_FUTURE_SEC = 5 * 60;      // 時計のずれの許容

// ---- 盗難の検知 ----
constexpr uint32_t ACC_NO_KEY_GRACE_MS = 30000;      // ACC ON からこの時間キーが見つからなければ盗難の疑い
constexpr uint32_t TRACK_STATE_MS = 3 * 60000UL;    // 追跡中に状態（位置）を送る間隔（30 秒ごとでは ntfy.sh の 1 日の上限を 2 時間で使い切る）
constexpr uint32_t TRACK_NOTIFY_MS = 3 * 60000UL;    // 追跡中に位置を通知する間隔
constexpr bool PARK_GPS_CHECK = true;                // 駐車モードで起きるたびに GPS（J8 のもの）で位置を確かめる
constexpr uint32_t PARK_GPS_WAIT_MS = 45000;         // そのとき測位を待つ最長時間
constexpr float MOVE_ALERT_M = 150.0f;               // 駐車位置からこれ以上離れたら移動とみなす
constexpr uint16_t NMEA_UDP_PORT = 10110;            // Ottocast などから Wi-Fi で NMEA を受け取るポート

// ---- 点検の予定・凍結の注意 ----
constexpr int MAX_MAINT = 8;
constexpr float FREEZE_WARN_C = 1.0f;                // 朝、車内がこれ以下なら凍結に注意
constexpr int FREEZE_HOUR_FROM = 5;                  // 凍結の注意を出す時間帯（日本時間）
constexpr int FREEZE_HOUR_TO = 9;

// ---- エンジン稼働時間とメンテナンス ----
constexpr float OIL_CHANGE_HOURS = 150.0f;  // 前回リセットからこの稼働時間で交換時期を通知

// ---- 通知（ntfy） ----
constexpr uint32_t CMD_POLL_MS = 30000;          // コマンド用トピックを読みに行く間隔
constexpr int DAILY_REPORT_HOUR = 20;  // 毎日この時刻（日本時間）に状態を報告。-1 で無効
#define TZ_JAPAN "JST-9"
#define NTP_SERVER1 "ntp.nict.jp"
#define NTP_SERVER2 "pool.ntp.org"

constexpr int MAX_BEACONS = 4;
