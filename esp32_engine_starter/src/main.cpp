// HIJET MONITOR：ハイゼット ジャンボの見守り装置（ESP32 DevKit V1 ＋ 専用基板 v4）
//
// - キー（BLE ビーコン）が離れたら、ドアが閉まっていれば自動で施錠信号を出す
// - キーが無いのにドアが開いた・車体が揺れたら通知（ブザー警報は任意）
// - バッテリー：低電圧、始動時の電圧の落ち込み、走行中の充電不良を通知
// - OBD-II：水温・回転数・車速・警告灯。エンジン稼働時間とオイル交換時期
// - GPS：走行ごとの距離・最高速度、駐車位置
// - 車内の温度・湿度
// 通知は ntfy、スマホからの指示は ntfy の指示用トピック（"<暗証番号> <指示>"）で受け取る。
// ダッシュボード用に、状態と電圧・温度の履歴を JSON で状態のトピックに送る。
// Wi-Fi などの設定は、設定モード（ESP32 が出す Wi-Fi「HIJET-SETUP-xxxx」）の画面で行い、NVS に保存する。
#include <Arduino.h>
#include <ArduinoJson.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <driver/gpio.h>
#include <esp_ota_ops.h>
#include <esp_sleep.h>
#include <esp_task_wdt.h>
#include <time.h>

#include <algorithm>
#include <vector>

#include "battery.h"
#include "logic/battery_health.h"
#include "ble_presence.h"
#include "buzzer.h"
#include "config.h"
#include "logic/cooldown.h"
#include "gps.h"
#include "io.h"
#include "notifier.h"
#include "obd.h"
#include "logic/history.h"
#include "logic/hmac_sha256.h"
#include "logic/maintenance.h"
#include "logic/nmea.h"
#include "logic/park_sleep.h"
#include "portal.h"
#include "remote_ota.h"
#include "logic/presence.h"
#include "sensors.h"
#include "settings.h"

using namespace starter;

namespace {

Battery battery;
BlePresence ble;
Inputs inputs;
PulseOutput lockOut(PIN_OUT_LOCK), out2(PIN_OUT2), out3(PIN_OUT3), out4(PIN_OUT4);
Buzzer buzzer;
Sensors sensors;
Obd obd;
Gps gps;
Notifier notifier;
Preferences prefs;

PresenceTracker presence;
CrankMonitor crank(60000);
ChargeCheck charge(CHARGE_MIN_V, 60000);

enum CooldownKey { CD_INTRUSION, CD_MOTION, CD_DOOR_OPEN, CD_HOT, CD_COLD, CD_COOLANT, CD_MIL, CD_OIL,
                   CD_LOW, CD_BADSIG, CD_COUNT };
Cooldown<CD_COUNT> cooldown;

// 設定（NVS に保存。指示で切り替え）
bool autoLockOn = true;
bool alarmOn = true;    // 侵入・振動の通知
bool sirenOn = false;   // 侵入時にブザーを鳴らす
uint32_t engineSec = 0;   // 累計エンジン稼働秒
uint32_t oilBaseSec = 0;  // 前回オイル交換時の engineSec

uint32_t pauseUntilMs = 0;   // 自動ロックの一時停止
bool lockPending = false;     // 離れたがドアが開いていたので、閉まったら施錠する
uint32_t lockPendingSince = 0;
bool armed = false;
bool engineRunning = false;
float lastCrankV = NAN;
uint32_t lastEngineTickMs = 0;
uint32_t lastSaveMs = 0;
int lastReportDay = -1;
bool lowNotified = false;

constexpr uint32_t PAUSE_FOREVER = 0xFFFFFFFF;

// ---- 駐車モード ----
bool parkOn = PARK_SLEEP_DEFAULT;
ParkSleepTimer parkTimer(PARK_IDLE_MS);
bool parkTimerWake = false;  // 駐車モード中に時間で起きた（用が済んだらまた眠る）
bool doorWake = false;       // ドアが開いて起きた（キーが見つかるまで待つ）
uint32_t wakeMs = 0;
uint32_t pollsAtWake = 0;

// ディープスリープをまたいで残す値（RTC メモリ。電源を切ると消える）
enum SleepKind : uint8_t { SLEEP_NONE = 0, SLEEP_LOW_VOLTAGE = 1, SLEEP_PARK = 2 };
RTC_DATA_ATTR uint8_t rtcSleepKind = SLEEP_NONE;
RTC_DATA_ATTR char rtcSince[32] = "";
RTC_DATA_ATTR int rtcLastReportDay = -1;
RTC_DATA_ATTR bool rtcHaveLast = false;
RTC_DATA_ATTR double rtcLat = 0, rtcLon = 0;
RTC_DATA_ATTR float rtcLastCrankV = NAN;
RTC_DATA_ATTR History<HIST_POINTS> rtcHist;  // ダッシュボードのグラフ用（電源を切ると消える）

// ---- Wi-Fi・ダッシュボード ----
uint32_t wifiTryMs = 0;
bool wifiOnSecond = false;
uint32_t wifiDownSince = 0;  // ACC ON で Wi-Fi が切れている時間を測る（0 なら測っていない）
uint32_t lastStateMs = 0;
uint32_t stateEverySec = STATE_PUBLISH_MS / 1000;  // 状態を送る間隔（ダッシュボードが「応答なし」を判断するのに使う）
bool stateDirty = true;       // 出来事があったので状態を送りたい
bool sleepingSoon = false;    // これから眠る（状態に入れて、ダッシュボードに休止中と出す）
uint32_t setupBtnSince = 0;

// ---- 見張り・更新の確認 ----
String cmdAttachUrl;        // いま処理している指示に付いていた添付ファイル（遠隔更新のファームウェア）
bool otaPending = false;     // OTA で更新した直後（正常に動くと確かめるまで前の版に戻せる）
const char* resetReason = "";
uint32_t lastCmdTs = 0;      // 最後に受け付けた署名付き指示の時刻（使い回しを防ぐ）

// ---- 盗難の検知・追跡 ----
bool tracking = false;       // 盗難の疑い：位置を頻繁に送る
uint32_t accOnMs = 0;
bool theftChecked = false;   // この ACC ON ではもう判断した
uint32_t lastTrackNotifyMs = 0;
bool parkGpsCheck = false;   // 駐車モードで起きたとき、GPS で位置を確かめている
double parkedLat = 0, parkedLon = 0;
RTC_DATA_ATTR bool rtcUartGps = false;  // J8 に GPS モジュールがある
WiFiUDP nmeaUdp;

// ---- 点検の予定・凍結 ----
MaintItem maintItems[MAX_MAINT];
int maintCount = 0;
float gpsKm = 0;             // GPS で測った累計の走行距離
uint32_t lastMaintCheckMs = 0;
int lastFreezeDay = -1;
RTC_DATA_ATTR int rtcFreezeDay = -1;

void publishState(uint32_t now);  // 下で定義

// 眠っている間 LOW に固定する出力（フォトカプラの LED とブザー）
const gpio_num_t HOLD_PINS[] = {(gpio_num_t)PIN_OUT_LOCK, (gpio_num_t)PIN_OUT2, (gpio_num_t)PIN_OUT3,
                                (gpio_num_t)PIN_OUT4, (gpio_num_t)PIN_BUZZER};

String fmt1(float v) { return isnan(v) ? String("-") : String(v, 1); }

String mapLink() {
  double lat, lon;
  if (!gps.lastKnown(lat, lon)) return "";
  return "\nhttps://maps.google.com/?q=" + String(lat, 6) + "," + String(lon, 6);
}

void loadPrefs() {
  prefs.begin("monitor", false);
  autoLockOn = prefs.getBool("autolock", true);
  alarmOn = prefs.getBool("alarm", true);
  sirenOn = prefs.getBool("siren", false);
  engineSec = prefs.getUInt("engsec", 0);
  gpsKm = prefs.getFloat("gpskm", 0);
  lastCmdTs = prefs.getUInt("cmdts", 0);
  oilBaseSec = prefs.getUInt("oilbase", 0);
  parkOn = prefs.getBool("park", PARK_SLEEP_DEFAULT);
}

void saveEngine() {
  prefs.putUInt("engsec", engineSec);
  lastSaveMs = millis();
}

float oilRemainHours() { return OIL_CHANGE_HOURS - (engineSec - oilBaseSec) / 3600.0f; }

const char* presenceName() {
  switch (presence.state()) {
    case PresenceState::Present: return "車の近く";
    case PresenceState::Absent: return "離れている";
    default: return "未確認";
  }
}

String statusText(uint32_t now) {
  String s;
  s += "バッテリー " + fmt1(battery.volts()) + "V";
  if (!isnan(lastCrankV)) s += "（前回始動時 " + fmt1(lastCrankV) + "V）";
  s += "\nエンジン " + String(engineRunning ? "稼働中" : "停止");
  if (obd.fresh(now)) s += "  水温 " + fmt1(obd.coolantC) + "℃  " + String((int)obd.rpm) + "rpm";
  if (sensors.hasEnv()) s += "\n車内 " + fmt1(sensors.tempC()) + "℃  湿度 " + fmt1(sensors.humidity()) + "%";
  s += "\nキー " + String(presenceName()) + "  ドア " + (inputs.doorOpen() ? "開" : "閉");
  s += "\n自動ロック " + String(!autoLockOn ? "OFF" : (pauseUntilMs ? "一時停止中" : "ON"));
  s += "  警戒 " + String(alarmOn ? (armed ? "警戒中" : "待機") : "OFF");
  s += "\n駐車モード " + String(parkOn ? "ON" : "OFF");
  s += "\n稼働 " + fmt1(engineSec / 3600.0f) + "h  オイル交換まで " + fmt1(oilRemainHours()) + "h";
  return s;
}

void doLock(uint32_t now, const char* why) {
  // 通知の送信（数秒かかることがある）でパルスが延びないよう、ここで決まった時間だけ出す
  lockOut.set(true);
  delay(LOCK_PULSE_MS);
  lockOut.set(false);
  (void)now;
  buzzer.beep(1);
  notifier.send(Prio::Low, "施錠しました", why, "lock");
  lockPending = false;
}

// 暗証番号だけで受け付ける指示（読むだけのもの・施錠）。それ以外は署名が必要
bool plainAllowed(const String& cmd) {
  return cmd == "status" || cmd == "state" || cmd == "scan" || cmd == "beep" || cmd == "lock";
}

bool clockValid();
void dispatchCommand(String cmd, uint32_t now);

// ---- スマホ・ダッシュボードからの指示 ----
// ダッシュボード："sig1 <時刻> <署名> <指示>"（署名で本物か・使い回しでないかを確かめる）
// ntfy アプリから手で送る："<暗証番号> <指示>"（読むだけの指示と施錠だけ）
void handleCommand(String line, uint32_t now) {
  line.trim();
  Serial.printf("[cmd] %s\n", line.startsWith("sig1 ") ? line.substring(line.lastIndexOf(' ') + 1).c_str() : "(暗証番号つき)");
  if (line.startsWith("sig1 ")) {
    SignedCommand sc;
    if (!parseSigned(line.c_str(), sc)) return;
    uint32_t nowTs = clockValid() ? (uint32_t)time(nullptr) : 0;
    SigVerdict v = verifyCommand(settings.cmdKey.c_str(), sc, nowTs, lastCmdTs, CMD_MAX_AGE_SEC, CMD_MAX_FUTURE_SEC);
    Serial.printf("[cmd] 署名の判定 %d（0=OK）時計=%u 指示の時刻=%u\n", (int)v, (unsigned)nowTs, (unsigned)sc.ts);
    if (v == SigVerdict::BadSignature) {
      if (cooldown.allow(CD_BADSIG, now, 3600000UL)) {
        notifier.send(Prio::Default, "署名が合わない指示を無視しました",
                      "ダッシュボードの「指示の鍵」が古いか、他人が送った可能性があります", "warning");
      }
      return;
    }
    if (v == SigVerdict::TooOld) {
      notifier.send(Prio::Low, "古い指示を無視しました", String(sc.cmd) + "（30 分以上前に送られたもの）");
      return;
    }
    if (v != SigVerdict::Ok) return;  // 使い回し・未来の時刻は黙って無視
    lastCmdTs = sc.ts;
    prefs.putUInt("cmdts", lastCmdTs);
    dispatchCommand(String(sc.cmd), now);
    return;
  }
  if (settings.pin.isEmpty()) return;
  String pin = settings.pin + " ";
  if (!line.startsWith(pin)) return;  // 暗証番号が違うものは黙って無視
  String cmd = line.substring(pin.length());
  cmd.trim();
  cmd.toLowerCase();
  String head = cmd.indexOf(' ') > 0 ? cmd.substring(0, cmd.indexOf(' ')) : cmd;
  if (!plainAllowed(head)) {
    notifier.send(Prio::Low, "ダッシュボードから送ってください",
                  "\"" + head + "\" は、なりすまし防止のため署名が必要です（ダッシュボードの操作ボタンから送れます）");
    return;
  }
  dispatchCommand(cmd, now);
}

void dispatchCommand(String cmd, uint32_t now) {
  stateDirty = true;  // 指示を受けたら、結果をダッシュボードにも反映する
  cmd.trim();
  cmd.toLowerCase();
  String arg;
  int sp = cmd.indexOf(' ');
  if (sp > 0) {
    arg = cmd.substring(sp + 1);
    cmd = cmd.substring(0, sp);
  }

  if (cmd == "status") {
    notifier.send(Prio::Low, "状態", statusText(now) + mapLink());
  } else if (cmd == "state") {
    // ダッシュボードの「更新」：通知は出さず、状態だけ送る
  } else if (cmd == "setup") {
    portal.start("スマホからの指示で設定モードに入りました。", now);
    notifier.send(Prio::Low, "設定モード",
                  "車の近くで Wi-Fi「" + portal.apName() + "」につなぐと設定画面が開きます（" +
                      String(SETUP_TIMEOUT_MS / 60000) + " 分で終了）");
  } else if (cmd == "lock") {
    doLock(now, "スマホからの指示");
  } else if (cmd == "pause") {
    int min = arg.toInt();
    pauseUntilMs = min > 0 ? now + min * 60000UL : PAUSE_FOREVER;
    if (pauseUntilMs == 0) pauseUntilMs = 1;
    notifier.send(Prio::Low, "自動ロック一時停止", min > 0 ? String(min) + " 分間止めます" : String("resume まで止めます"));
  } else if (cmd == "resume") {
    pauseUntilMs = 0;
    notifier.send(Prio::Low, "自動ロック再開", "");
  } else if (cmd == "autolock" || cmd == "alarm" || cmd == "siren" || cmd == "park") {
    bool on = arg != "off";
    const char* key = cmd == "autolock" ? "autolock" : cmd == "alarm" ? "alarm" : cmd == "siren" ? "siren" : "park";
    if (cmd == "autolock") autoLockOn = on;
    if (cmd == "alarm") alarmOn = on;
    if (cmd == "siren") sirenOn = on;
    if (cmd == "park") parkOn = on;
    prefs.putBool(key, on);
    notifier.send(Prio::Low, "設定変更", cmd + " = " + (on ? "on" : "off"));
  } else if (cmd == "scan") {
    // 近くの BLE 機器（ビーコン登録用）。電波の強い順
    JsonDocument doc;
    JsonArray arr = doc.to<JsonArray>();
    ble.nearbyToJson(arr, now);
    std::vector<JsonObject> items;
    for (JsonObject o : arr) items.push_back(o);
    std::sort(items.begin(), items.end(),
              [](const JsonObject& a, const JsonObject& b) { return (int)a["rssi"] > (int)b["rssi"]; });
    String body;
    for (size_t i = 0; i < items.size() && i < 10; ++i) {
      JsonObject o = items[i];
      body += String((const char*)o["mac"]) + "  " + String((int)o["rssi"]) + "dBm";
      const char* name = o["name"] | "";
      if (name[0]) body += "  " + String(name);
      if (o["uuid"].is<const char*>()) {
        body += "\n  uuid:" + String((const char*)o["uuid"]) + ":" + String((int)o["major"]) + ":" +
                String((int)o["minor"]);
      }
      body += "\n";
    }
    notifier.send(Prio::Low, "近くの BLE 機器", body.isEmpty() ? String("見つかりません") : body);
  } else if (cmd == "beep") {
    buzzer.beep(3);
  } else if (cmd == "silence") {
    buzzer.stop();
  } else if (cmd == "track") {
    if (arg == "off") {
      tracking = false;
      notifier.send(Prio::Low, "追跡を終わりました", "");
    } else {
      tracking = true;
      lastTrackNotifyMs = 0;
      notifier.send(Prio::Low, "追跡を始めました", "位置を " + String(TRACK_NOTIFY_MS / 60000) + " 分ごとに通知します");
    }
  } else if (cmd == "ota") {
    // 遠隔更新（署名付きの指示だけ。arg はファームウェアの SHA-256）
    if (cmdAttachUrl.isEmpty()) {
      notifier.send(Prio::Default, "更新できません", "ファームウェアのファイルが添付されていません", "warning");
      return;
    }
    Serial.printf("[ota] %s\n", cmdAttachUrl.c_str());
    ble.setEnabled(false);  // ダウンロード中は Bluetooth を止める（メモリと無線を空ける）
    String err;
    if (remoteOtaUpdate(notifier, cmdAttachUrl, arg, err)) {
      Serial.println("[ota] 書き込み完了。再起動します");
      saveEngine();
      delay(200);
      ESP.restart();  // 新しい版が ntfy と通信できれば確定、できなければ 10 分で前の版に戻る
    }
    Serial.printf("[ota] 失敗：%s\n", err.c_str());
    notifier.send(Prio::Default, "更新に失敗しました", err + "。今の版のまま動いています", "warning");
  } else if (cmd == "oilreset") {
    oilBaseSec = engineSec;
    prefs.putUInt("oilbase", oilBaseSec);
    cooldown.reset(CD_OIL);
    notifier.send(Prio::Low, "オイル交換を記録", "次回まで " + fmt1(OIL_CHANGE_HOURS) + "h");
  } else {
    notifier.send(Prio::Low, "不明な指示",
                  "status / scan / lock / pause [分] / resume / autolock on|off / alarm on|off / "
                  "siren on|off / park on|off / track on|off / beep / silence / oilreset / setup / ota（ダッシュボードから）");
  }
}

// ---- ディープスリープ（ACC ON かドアが開いたら起きる。時間でも起きる） ----
// kind：低電圧（SLEEP_WAKE_SEC ごとに電圧だけ見る）か駐車モード（PARK_WAKE_SEC ごとに指示と電圧を見る）
void enterDeepSleep(SleepKind kind) {
  Serial.printf("deep sleep kind=%d\n", (int)kind);
  rtcSleepKind = kind;
  String since = notifier.since();
  strlcpy(rtcSince, since.c_str(), sizeof(rtcSince));
  rtcLastReportDay = lastReportDay;
  rtcLastCrankV = lastCrankV;
  // 駐車位置は、駐車してから最初に眠るときの位置のまま保つ（起きるたびの測位のぶれで動かさない）
  if (!parkTimerWake || !rtcHaveLast) rtcHaveLast = gps.lastKnown(rtcLat, rtcLon);
  rtcUartGps = rtcUartGps || gps.uartPresent();
  rtcFreezeDay = lastFreezeDay;
  ble.setEnabled(false);
  sensors.sleep();
  gps.standby();
  digitalWrite(PIN_CAN_STBY, HIGH);
  for (gpio_num_t p : HOLD_PINS) {
    pinMode(p, OUTPUT);
    digitalWrite(p, LOW);
    gpio_hold_en(p);
  }
  gpio_deep_sleep_hold_en();
  uint32_t sec = kind == SLEEP_PARK ? PARK_WAKE_SEC : SLEEP_WAKE_SEC;
  esp_sleep_enable_timer_wakeup((uint64_t)sec * 1000000ULL);
  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_ACC, 0);                      // ACC ON（LOW）
  esp_sleep_enable_ext1_wakeup(1ULL << PIN_DOOR, ESP_EXT1_WAKEUP_ALL_LOW);   // ドアが開いた（LOW）
  esp_deep_sleep_start();
}

void flushThenSleep(SleepKind kind) {
  sleepingSoon = kind == SLEEP_PARK;
  if (sleepingSoon) publishState(millis());  // ダッシュボードに「休止中」と出す
  uint32_t until = millis() + 20000;
  while (millis() < until && !notifier.idle()) {
    esp_task_wdt_reset();
    notifier.loop(millis());
    delay(50);
  }
  enterDeepSleep(kind);
}

void wifiBegin(bool second) {
  wifiOnSecond = second;
  wifiTryMs = millis();
  if (second) {
    WiFi.begin(settings.ssid2.c_str(), settings.pass2.c_str());
  } else {
    WiFi.begin(settings.ssid1.c_str(), settings.pass1.c_str());
  }
}

void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(settings.hostname.c_str());
  WiFi.setAutoReconnect(true);
  if (settings.ssid1.length()) wifiBegin(false);
  configTzTime(TZ_JAPAN, NTP_SERVER1, NTP_SERVER2);
  if (settings.otaPass.length() >= 8) {  // パスワードなしの OTA は受け付けない
    ArduinoOTA.setHostname(settings.hostname.c_str());
    ArduinoOTA.setPassword(settings.otaPass.c_str());
    ArduinoOTA.begin();
  }
}

// つながらないとき、予備の Wi-Fi があれば交互に試す
void wifiLoop(uint32_t now) {
  if (WiFi.status() == WL_CONNECTED || settings.ssid1.isEmpty() || portal.active()) return;
  if (now - wifiTryMs < WIFI_SWITCH_MS) return;
  wifiBegin(settings.ssid2.length() ? !wifiOnSecond : false);
}

void setupBeacons() {
  BeaconRule parsed[MAX_BEACONS];
  int n = 0;
  for (const String& r : settings.beacons) {
    if (r.isEmpty()) continue;
    if (n < MAX_BEACONS && parseBeaconRule(r.c_str(), parsed[n])) {
      ++n;
    } else {
      Serial.printf("beacon rule ignored: %s\n", r.c_str());
    }
  }
  ble.setRules(parsed, n);
}

void nearbyForPortal(JsonArray arr) { ble.nearbyToJson(arr, millis()); }
float gpsKmForPortal() { return gpsKm; }

bool clockValid() { return time(nullptr) > 1700000000; }

void recordHistory(float volts) {
  if (!clockValid() || volts <= 0) return;
  rtcHist.maybeAdd((uint32_t)time(nullptr), volts, sensors.hasEnv() ? sensors.tempC() : NAN, HIST_INTERVAL_SEC);
}

const char* presenceKey() {
  switch (presence.state()) {
    case PresenceState::Present: return "present";
    case PresenceState::Absent: return "absent";
    default: return "unknown";
  }
}

// ダッシュボード用の状態（ntfy のメッセージは 4KB までなので、履歴は詰めて入れる）
String stateJson(uint32_t now) {
  JsonDocument d;
  d["fw"] = FW_VERSION;
  d["up"] = now / 1000;
  if (clockValid()) d["t"] = (uint32_t)time(nullptr);
  d["v"] = serialized(String(battery.volts(), 2));
  d["acc"] = inputs.acc();
  d["eng"] = engineRunning;
  d["door"] = inputs.doorOpen();
  d["in2"] = inputs.in2();
  d["key"] = presenceKey();
  if (presence.everSeen()) d["rssi"] = presence.lastRssi();
  d["armed"] = armed;
  d["al"] = autoLockOn;
  d["paused"] = pauseUntilMs != 0;
  d["alarm"] = alarmOn;
  d["siren"] = sirenOn;
  d["park"] = parkOn;
  d["lowv"] = battery.lowVoltage();
  d["lockp"] = lockPending;
  if (sleepingSoon) {
    d["sleep"] = true;
    d["wake"] = PARK_WAKE_SEC;
  }
  d["engh"] = serialized(String(engineSec / 3600.0f, 1));
  d["oil"] = serialized(String(oilRemainHours(), 1));
  if (!isnan(lastCrankV)) d["crank"] = serialized(String(lastCrankV, 2));
  if (sensors.hasEnv() && !isnan(sensors.tempC())) {
    d["temp"] = serialized(String(sensors.tempC(), 1));
    d["hum"] = serialized(String(sensors.humidity(), 0));
  }
  if (obd.fresh(now)) {
    if (!isnan(obd.coolantC)) d["cool"] = serialized(String(obd.coolantC, 0));
    if (!isnan(obd.rpm)) d["rpm"] = (int)obd.rpm;
    if (obd.statusKnown) {
      d["mil"] = obd.milOn;
      d["dtc"] = obd.dtcCount;
    }
  }
  double lat, lon;
  if (gps.lastKnown(lat, lon)) {
    d["lat"] = serialized(String(lat, 6));
    d["lon"] = serialized(String(lon, 6));
  }
  d["fix"] = gps.hasFix(now);
  if (tracking) d["trk"] = true;
  if (lastCmdTs) d["cts"] = lastCmdTs;  // ダッシュボードは、これより後の時刻で署名する
  d["si"] = tracking ? TRACK_STATE_MS / 1000 : stateEverySec;  // 状態を送る間隔（秒）
  if (resetReason[0]) d["rst"] = resetReason;
  if (otaPending) d["ota"] = "verifying";
  if (gps.present()) d["gsrc"] = gps.source();
  if (settings.odoKm > 0) d["odo"] = (int)(settings.odoKm + gpsKm - settings.odoGpsKm);
  if (maintCount > 0 && clockValid()) {
    JsonArray mt = d["mt"].to<JsonArray>();
    struct tm lt;
    time_t tt = time(nullptr);
    localtime_r(&tt, &lt);
    int32_t today = daysFromCivil(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday);
    for (int i = 0; i < maintCount; ++i) {
      JsonObject o = mt.add<JsonObject>();
      o["n"] = maintItems[i].name;
      if (maintItems[i].byDate) {
        o["d"] = maintItems[i].day - today;
      } else if (settings.odoKm > 0) {
        o["k"] = (int)(maintItems[i].km - (settings.odoKm + gpsKm - settings.odoGpsKm));
      }
    }
  }
  JsonObject dev = d["dev"].to<JsonObject>();
  if (WiFi.status() == WL_CONNECTED) dev["ip"] = WiFi.localIP().toString();
  dev["bme"] = sensors.hasEnv();
  dev["mpu"] = sensors.hasMotion();
  dev["gps"] = gps.present();
  dev["obd"] = obd.fresh(now);
  dev["keys"] = ble.ruleCount();
  if (WiFi.status() == WL_CONNECTED) dev["wifi"] = WiFi.RSSI();
  // 履歴：最初の時刻と、そこからの分・電圧（0.01V）・温度（0.1℃、不明は null）
  if (rtcHist.size() > 0) {
    JsonObject h = d["h"].to<JsonObject>();
    uint32_t t0 = rtcHist.at(0).t;
    h["t0"] = t0;
    JsonArray m = h["m"].to<JsonArray>();
    JsonArray v = h["v"].to<JsonArray>();
    JsonArray c = h["c"].to<JsonArray>();
    for (int i = 0; i < rtcHist.size(); ++i) {
      const HistPoint& p = rtcHist.at(i);
      m.add((p.t - t0) / 60);
      v.add(p.cv);
      if (p.temp10 == TEMP_NONE) {
        c.add(nullptr);
      } else {
        c.add(p.temp10);
      }
    }
  }
  String out;
  serializeJson(d, out);
  return out;
}

void publishState(uint32_t now) {
  notifier.publishState(stateJson(now));
  lastStateMs = now;
  stateDirty = false;
}

const char* resetReasonName(esp_reset_reason_t r) {
  switch (r) {
    case ESP_RST_POWERON: return "電源投入";
    case ESP_RST_SW: return "再起動の指示";
    case ESP_RST_PANIC: return "プログラムの異常";
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT: return "応答なし（ウォッチドッグ）";
    case ESP_RST_BROWNOUT: return "電圧の瞬断";
    case ESP_RST_DEEPSLEEP: return "";
    default: return "その他";
  }
}

bool abnormalReset(esp_reset_reason_t r) {
  return r == ESP_RST_PANIC || r == ESP_RST_INT_WDT || r == ESP_RST_TASK_WDT || r == ESP_RST_WDT ||
         r == ESP_RST_BROWNOUT;
}

void loadMaint() {
  maintCount = 0;
  String all = settings.maint;
  int start = 0;
  while (start <= (int)all.length() && maintCount < MAX_MAINT) {
    int nl = all.indexOf('\n', start);
    if (nl < 0) nl = all.length();
    String l = all.substring(start, nl);
    l.trim();
    if (l.length() && parseMaintLine(l.c_str(), maintItems[maintCount])) ++maintCount;
    start = nl + 1;
  }
}

int32_t odometerKm() { return settings.odoKm + (int32_t)(gpsKm - settings.odoGpsKm); }

int32_t todayDays() {
  struct tm lt;
  time_t tt = time(nullptr);
  localtime_r(&tt, &lt);
  return daysFromCivil(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday);
}

// 点検の予定：段階が上がったときだけ通知（段階は項目の名前と期日ごとに NVS に覚える）
void checkMaint(uint32_t now) {
  if (maintCount == 0 || !clockValid() || (lastMaintCheckMs && now - lastMaintCheckMs < 10 * 60000UL)) return;
  lastMaintCheckMs = now;
  int32_t today = todayDays();
  bool odoKnown = settings.odoKm > 0;
  for (int i = 0; i < maintCount; ++i) {
    const MaintItem& it = maintItems[i];
    int level = maintLevel(it, today, odometerKm(), odoKnown);
    // 項目ごとの鍵（名前と期日から作る）。項目を書き換えたら数え直しになる
    uint8_t h[32];
    char tag[48];
    snprintf(tag, sizeof(tag), "%s|%ld|%ld", it.name, (long)it.day, (long)it.km);
    Sha256 sh;
    sh.update(tag);
    sh.finish(h);
    char key[16];
    snprintf(key, sizeof(key), "mt%02x%02x%02x%02x", h[0], h[1], h[2], h[3]);
    int done = prefs.getInt(key, 0);
    if (level <= done) {
      if (level < done) prefs.putInt(key, level);
      continue;
    }
    prefs.putInt(key, level);
    String body;
    if (it.byDate) {
      int32_t left = it.day - today;
      body = left > 0 ? "あと " + String(left) + " 日です" : (left == 0 ? String("今日です") : "期日を " + String(-left) + " 日過ぎています");
    } else {
      int32_t left = it.km - odometerKm();
      body = left > 0 ? "あと " + String(left) + "km です" : "予定の距離を " + String(-left) + "km 過ぎています";
    }
    notifier.send(level >= 4 ? Prio::High : Prio::Default, String(it.name) + "の時期です", body, "calendar");
  }
}

// 冬の朝、車内が氷点下近くなら凍結に注意（1 日 1 回）
void checkFreeze() {
  if (!sensors.hasEnv() || isnan(sensors.tempC()) || !clockValid()) return;
  struct tm lt;
  time_t tt = time(nullptr);
  localtime_r(&tt, &lt);
  if (lt.tm_hour < FREEZE_HOUR_FROM || lt.tm_hour >= FREEZE_HOUR_TO || lt.tm_yday == lastFreezeDay) return;
  if (sensors.tempC() > FREEZE_WARN_C) return;
  lastFreezeDay = lt.tm_yday;
  notifier.send(Prio::Default, "凍結に注意", "車内 " + fmt1(sensors.tempC()) + "℃。窓の凍結や路面の凍結に気を付けてください",
                "snowflake");
}

}  // namespace

// 更新後の新しい版を、正常に動くと確かめるまで「仮」のままにする（Arduino の既定ではすぐ「正常」になる）
extern "C" bool verifyRollbackLater() { return true; }

void setup() {
  Serial.begin(115200);
  // 眠っている間に固定していた出力を解放する
  gpio_deep_sleep_hold_dis();
  for (gpio_num_t p : HOLD_PINS) gpio_hold_dis(p);
  battery.begin();

  esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  SleepKind slept = cause == ESP_SLEEP_WAKEUP_UNDEFINED ? SLEEP_NONE : (SleepKind)rtcSleepKind;
  rtcSleepKind = SLEEP_NONE;
  if (slept != SLEEP_NONE) {  // スリープ前の状態を戻す（すぐ眠り直すときも引き継げるよう、最初に戻す）
    notifier.resumeFrom(String(rtcSince));
    lastReportDay = rtcLastReportDay;
    lastCrankV = rtcLastCrankV;
    lastFreezeDay = rtcFreezeDay;
    if (rtcHaveLast) {
      gps.setLastKnown(rtcLat, rtcLon);
      parkedLat = rtcLat;
      parkedLon = rtcLon;
    }
  }

  if (slept == SLEEP_NONE || !rtcHist.sane()) rtcHist.clear();
  settings.load();

  // 時間で起きたとき：電圧が低ければ、Wi-Fi も BLE も使わずにすぐ眠り直す
  if (cause == ESP_SLEEP_WAKEUP_TIMER) {
    pinMode(PIN_ACC, INPUT);
    float v = (battery.sampleNow() + battery.sampleNow()) / 2;
    recordHistory(v);
    bool accOff = digitalRead(PIN_ACC) == HIGH;
    if (accOff && slept == SLEEP_LOW_VOLTAGE && v < VBAT_LOW_RECOVER) enterDeepSleep(SLEEP_LOW_VOLTAGE);
    if (accOff && slept == SLEEP_PARK && v < VBAT_SLEEP) enterDeepSleep(SLEEP_LOW_VOLTAGE);
  }

  // 見張り：main loop が WDT_TIMEOUT_S 止まったら再起動する
  esp_task_wdt_init(WDT_TIMEOUT_S, true);
  esp_task_wdt_add(nullptr);
  esp_reset_reason_t rr = esp_reset_reason();
  resetReason = resetReasonName(rr);
  // OTA で更新した直後か
  esp_ota_img_states_t ost;
  if (esp_ota_get_state_partition(esp_ota_get_running_partition(), &ost) == ESP_OK &&
      ost == ESP_OTA_IMG_PENDING_VERIFY) {
    otaPending = true;
  }

  lockOut.begin();
  out2.begin();
  out3.begin();
  out4.begin();
  buzzer.begin();
  inputs.begin();
  sensors.begin();
  obd.begin();
  gps.begin();
  loadPrefs();

  PresenceConfig pc;
  pc.nearRssi = NEAR_RSSI;
  pc.farRssi = FAR_RSSI;
  pc.absentTimeoutMs = ABSENT_TIMEOUT_MS;
  presence.setConfig(pc);
  ble.begin();
  setupBeacons();
  setupWifi();
  settings.ensureKey();  // 無線が動き始めてから鍵を作る（乱数のため）
  loadMaint();
  nmeaUdp.begin(NMEA_UDP_PORT);
  pinMode(PIN_SETUP_BUTTON, INPUT_PULLUP);
  portal.setNearbyProvider(nearbyForPortal);
  portal.setGpsKmProvider(gpsKmForPortal);
  if (!settings.configured()) portal.start("初期設定です。Wi-Fi と通知先を入力してください。", millis());

  wakeMs = millis();
  if (cause == ESP_SLEEP_WAKEUP_EXT1) {
    doorWake = true;  // キーが見つかるまで少し待ってから、侵入かどうか判断する
  } else if (cause == ESP_SLEEP_WAKEUP_TIMER && slept == SLEEP_PARK) {
    parkTimerWake = true;  // 指示の確認などが済んだらまた眠る
    notifier.pollSoon();
    // J8 の GPS で、駐車位置から動いていないか確かめる（Ottocast は駐車中は電源が切れているので使えない）
    parkGpsCheck = PARK_GPS_CHECK && rtcUartGps && rtcHaveLast;
  } else if (cause != ESP_SLEEP_WAKEUP_EXT0 && cause != ESP_SLEEP_WAKEUP_TIMER) {
    if (abnormalReset(rr)) {
      notifier.send(Prio::Default, "異常で再起動しました", String("理由：") + resetReason, "warning");
    } else {
      notifier.send(Prio::Min, "起動しました",
                    String("ファームウェア ") + FW_VERSION + " / BME280 " + (sensors.hasEnv() ? "あり" : "なし") +
                        " / MPU6050 " + (sensors.hasMotion() ? "あり" : "なし"));
    }
  }
  if (cause == ESP_SLEEP_WAKEUP_EXT0) {
    accOnMs = millis();  // ACC ON で起きた：盗難の判断を始める
  }
  lastEngineTickMs = millis();
}

void loop() {
  uint32_t now = millis();
  esp_task_wdt_reset();
  ArduinoOTA.handle();
  wifiLoop(now);
  portal.loop(now);

  inputs.loop(now);
  battery.loop(now);
  ble.loop();
  sensors.loop(now);
  gps.loop(now);
  // Wi-Fi 経由の GPS（Ottocast などから UDP で届く NMEA。1 つのパケットに複数行のことがある）
  for (int n = nmeaUdp.parsePacket(); n > 0; n = nmeaUdp.parsePacket()) {
    static char pkt[512];
    int len = nmeaUdp.read(pkt, sizeof(pkt) - 1);
    if (len <= 0) break;
    pkt[len] = '\0';
    char* save = nullptr;
    for (char* line = strtok_r(pkt, "\r\n", &save); line; line = strtok_r(nullptr, "\r\n", &save)) {
      gps.feedLine(line, now);
    }
  }
  obd.loop(now);
  lockOut.loop(now);
  out2.loop(now);
  out3.loop(now);
  out4.loop(now);
  buzzer.loop(now);
  notifier.loop(now);

  // ---- 設定モードに入る：BOOT ボタン長押し、ACC ON なのに Wi-Fi につながらない ----
  if (digitalRead(PIN_SETUP_BUTTON) == LOW) {
    if (!setupBtnSince) setupBtnSince = now ? now : 1;
    if (now - setupBtnSince > SETUP_HOLD_MS && !portal.active()) {
      portal.start("BOOT ボタンで設定モードに入りました。", now);
      buzzer.beep(2);
    }
  } else {
    setupBtnSince = 0;
  }
  if (inputs.acc() && WiFi.status() != WL_CONNECTED && settings.configured()) {
    if (!wifiDownSince) wifiDownSince = now ? now : 1;
    if (now - wifiDownSince > WIFI_FAIL_SETUP_MS && !portal.active()) {
      // スマートキーが車内にあるとき（ACC ON）だけなので、持ち主が車にいる
      portal.start("Wi-Fi につながりません。Wi-Fi の設定を確認してください。", now);
      buzzer.beep(2);
    }
  } else {
    wifiDownSince = 0;
  }

  // ---- キー（ビーコン）の在・不在 ----
  int rssi;
  if (ble.takeMatch(rssi)) presence.onSeen(rssi, now);
  PresenceEvent pev = presence.update(now);
  if (pev != PresenceEvent::None) stateDirty = true;
  if (inputs.doorChanged || inputs.accChanged) stateDirty = true;
  if (pev == PresenceEvent::Arrived) {
    lockPending = false;
    buzzer.stop();
  }

  // ---- エンジン稼働の判定（OBD があれば回転数、なければ電圧） ----
  bool wasRunning = engineRunning;
  if (obd.fresh(now) && !isnan(obd.rpm)) {
    engineRunning = obd.rpm > 400;
  } else {
    engineRunning = inputs.acc() && battery.chargingVoltage();
  }

  // ---- ACC ON / OFF ----
  if (inputs.accChanged) {
    if (inputs.acc()) {
      accOnMs = now ? now : 1;
      theftChecked = false;
      crank.start(now);
      obd.setActive(true, now);
      gps.startTrip(now);
      cooldown.reset(CD_MIL);
      buzzer.stop();
    } else {
      obd.setActive(false, now);
      saveEngine();
      TripSummary t = gps.endTrip(now);
      if (t.distanceKm > 0) {
        gpsKm += t.distanceKm;
        prefs.putFloat("gpskm", gpsKm);
      }
      if (tracking) {
        notifier.send(Prio::High, "ACC が切れました（追跡中）", "最後の位置" + mapLink(), "rotating_light");
        tracking = false;
      }
      if (t.durationSec >= 60) {
        notifier.send(Prio::Min, "走行記録",
                      String(t.durationSec / 60) + " 分  " + String(t.distanceKm, 1) + "km  最高 " +
                          String((int)t.maxSpeedKmh) + "km/h" + mapLink(),
                      "truck");
      }
    }
  }

  // ---- 始動時の電圧の落ち込み ----
  if (crank.active()) {
    crank.feed(battery.sampleNow(), now);  // 60 秒たっても始動しなければ自然に終わる
    if (engineRunning && !wasRunning && crank.finish()) {
      lastCrankV = crank.minVolts();
      if (lastCrankV < CRANK_WEAK_V && lastCrankV > 5.0f) {
        notifier.send(Prio::High, "バッテリーが弱っている可能性",
                      "始動時に " + fmt1(lastCrankV) + "V まで下がりました（目安 " + fmt1(CRANK_WEAK_V) +
                          "V 以上）",
                      "battery");
      }
    }
  }

  // ---- 充電不良・低電圧 ----
  if (charge.update(engineRunning, battery.volts(), now)) {
    notifier.send(Prio::High, "充電されていない可能性",
                  "エンジン稼働中なのに " + fmt1(battery.volts()) + "V です。発電機（オルタネーター）を点検してください",
                  "warning");
  }
  if (battery.lowVoltage() && !lowNotified) {
    lowNotified = true;
    notifier.send(Prio::High, "バッテリー電圧低下", fmt1(battery.volts()) + "V。しばらく乗らない場合は充電を",
                  "battery");
  }
  if (!battery.lowVoltage()) lowNotified = false;
  ble.setEnabled((!battery.lowVoltage() || inputs.acc()) && (!portal.active() || portal.wantsBle(now)));
  if (battery.valid() && battery.volts() < VBAT_SLEEP && battery.volts() >= VBAT_BENCH && !inputs.acc() &&
      now > 120000 && !otaPending && !portal.active()) {
    notifier.send(Prio::Urgent, "省電力モードに入ります",
                  fmt1(battery.volts()) + "V。ACC ON かドアが開くと復帰します", "zzz");
    saveEngine();
    flushThenSleep(SLEEP_LOW_VOLTAGE);
  }

  // ---- エンジン稼働時間・オイル交換 ----
  if (engineRunning) {
    engineSec += (now - lastEngineTickMs) / 1000;
    lastEngineTickMs += ((now - lastEngineTickMs) / 1000) * 1000;
    if (now - lastSaveMs > 10 * 60000UL) saveEngine();
  } else {
    lastEngineTickMs = now;
  }
  if (oilRemainHours() <= 0 && cooldown.allow(CD_OIL, now, 24 * 3600000UL)) {
    notifier.send(Prio::Default, "オイル交換の時期です",
                  "前回から " + fmt1((engineSec - oilBaseSec) / 3600.0f) + "h 稼働。交換したら \"oilreset\" を送ってください",
                  "wrench");
  }

  // ---- OBD の警告 ----
  if (obd.fresh(now)) {
    if (!isnan(obd.coolantC) && obd.coolantC > COOLANT_WARN_C && cooldown.allow(CD_COOLANT, now, 600000)) {
      notifier.send(Prio::Urgent, "水温が高すぎます", fmt1(obd.coolantC) + "℃。安全な場所に止めてください",
                    "fire");
    }
    if (obd.statusKnown && obd.milOn && cooldown.allow(CD_MIL, now, 24 * 3600000UL)) {
      notifier.send(Prio::High, "エンジン警告灯が点灯",
                    "故障コード " + String(obd.dtcCount) + " 件。早めに点検を", "warning");
    }
  }

  // ---- 自動ロック ----
  bool paused = pauseUntilMs != 0 && (pauseUntilMs == PAUSE_FOREVER || static_cast<int32_t>(now - pauseUntilMs) < 0);
  if (pauseUntilMs != 0 && !paused) pauseUntilMs = 0;
  // 施錠はほとんど電気を使わないので、低電圧でも止めない
  AutoLockInputs al{autoLockOn && !paused, engineRunning || inputs.acc(), false, false};
  if (decideAutoLock(pev, al) == AutoLockDecision::Lock) {
    if (inputs.doorOpen()) {
      lockPending = true;  // 閉まったら施錠する
      lockPendingSince = now;
    } else {
      doLock(now, "キーが離れたため");
    }
  }
  if (lockPending) {
    if (presence.state() == PresenceState::Present || inputs.acc() || now - lockPendingSince > 10 * 60000UL) {
      lockPending = false;
    } else if (inputs.doorChanged && !inputs.doorOpen()) {
      doLock(now, "キーが離れた後、ドアが閉まったため");
    }
  }

  // ---- ドアで起きたとき：猶予時間内にキーが見つからなければ侵入 ----
  if (doorWake) {
    DoorWakeVerdict v = judgeDoorWake(presence.state() == PresenceState::Present, inputs.acc(), now - wakeMs,
                                      DOOR_WAKE_GRACE_MS);
    if (v != DoorWakeVerdict::Waiting) {
      doorWake = false;
      if (v == DoorWakeVerdict::Intrusion) {
        presence.assumeAbsent();
        if (alarmOn && cooldown.allow(CD_INTRUSION, now, 120000)) {
          notifier.send(Prio::Urgent, "キーが無いのにドアが開きました",
                        "駐車中にドアが開き、キーが見つかりません" + mapLink(), "rotating_light");
          if (sirenOn) buzzer.alarm(ALARM_SOUND_MS);
        }
      }
    }
  }
  // 起動してからずっとキーが見つからないとき（キーを登録済みなら）は「離れている」とみなす
  if (presence.state() == PresenceState::Unknown && !presence.everSeen() && ble.ruleCount() > 0 &&
      now - wakeMs > (parkTimerWake ? PARK_KEY_SCAN_MS : PARK_IDLE_MS) && !doorWake) {
    presence.assumeAbsent();
  }

  // ---- 防犯（キーが離れていて ACC OFF のとき警戒） ----
  bool nowArmed = alarmOn && !inputs.acc() && presence.state() == PresenceState::Absent;
  if (nowArmed != armed) stateDirty = true;
  if (nowArmed && !armed) sensors.rebaseline();
  armed = nowArmed;
  if (armed && inputs.doorChanged && inputs.doorOpen() && cooldown.allow(CD_INTRUSION, now, 120000)) {
    notifier.send(Prio::Urgent, "キーが無いのにドアが開きました", "心当たりがなければ確認してください" + mapLink(),
                  "rotating_light");
    if (sirenOn) buzzer.alarm(ALARM_SOUND_MS);
  }
  bool shaken = sensors.takeMotion();
  if (armed && shaken && cooldown.allow(CD_MOTION, now, 300000)) {
    notifier.send(Prio::High, "車体の揺れを検知", "変化 " + String(sensors.lastShakeG(), 2) + "g" + mapLink(),
                  "warning");
  }
  if (inputs.doorOpen() && !inputs.acc() && presence.state() != PresenceState::Present &&
      now - inputs.doorChangedAt() > DOOR_OPEN_WARN_MS && cooldown.allow(CD_DOOR_OPEN, now, 1800000)) {
    notifier.send(Prio::High, "ドアが開いたままです", "キーが近くにありません", "door");
  }

  // ---- 車内の温度 ----
  if (sensors.hasEnv() && !isnan(sensors.tempC())) {
    if (sensors.tempC() > CABIN_HOT_C && cooldown.allow(CD_HOT, now, 3 * 3600000UL)) {
      notifier.send(Prio::Default, "車内が高温です", fmt1(sensors.tempC()) + "℃", "hot_face");
    }
    if (sensors.tempC() < CABIN_COLD_C && cooldown.allow(CD_COLD, now, 3 * 3600000UL)) {
      notifier.send(Prio::Default, "車内が低温です", fmt1(sensors.tempC()) + "℃。凍結に注意", "cold_face");
    }
  }

  // ---- スマホからの指示 ----
  String cmd;
  while (notifier.takeCommand(cmd, cmdAttachUrl)) handleCommand(cmd, now);
  cmdAttachUrl = "";

  // ---- 毎日の報告 ----
  struct tm t;
  if (DAILY_REPORT_HOUR >= 0 && time(nullptr) > 1700000000 && getLocalTime(&t, 0)) {
    if (t.tm_hour == DAILY_REPORT_HOUR && t.tm_yday != lastReportDay) {
      lastReportDay = t.tm_yday;
      notifier.send(Prio::Min, "毎日の報告", statusText(now));
    }
  }

  // ---- 盗難の疑い：キー（ビーコン）が無いのに ACC が入った（リレーアタックなど） ----
  if (inputs.acc() && accOnMs && !theftChecked && now - accOnMs > ACC_NO_KEY_GRACE_MS) {
    theftChecked = true;
    if (alarmOn && ble.ruleCount() > 0 && presence.state() != PresenceState::Present) {
      tracking = true;
      lastTrackNotifyMs = now;
      notifier.send(Prio::Urgent, "キーが無いのに ACC が入りました",
                    "盗難の可能性があります。位置を追跡します（キーのビーコンの電池切れでも起きます）" + mapLink(),
                    "rotating_light");
      if (sirenOn) buzzer.alarm(ALARM_SOUND_MS);
    }
  }
  // 駐車モードで起きたとき：GPS で駐車位置から動いていないか（レッカー移動など）
  if (parkGpsCheck) {
    if (gps.hasFix(now)) {
      double lat, lon;
      gps.lastKnown(lat, lon);
      double d = haversineM(parkedLat, parkedLon, lat, lon);
      parkGpsCheck = false;
      if (d > MOVE_ALERT_M && alarmOn) {
        tracking = true;
        parkTimerWake = false;  // 眠らずに追跡する
        lastTrackNotifyMs = now;
        notifier.send(Prio::Urgent, "駐車位置から移動しています",
                      String((int)d) + "m 離れています。位置を追跡します" + mapLink(), "rotating_light");
      }
    } else if (now - wakeMs > PARK_GPS_WAIT_MS) {
      parkGpsCheck = false;  // 測位できなかった（屋内など）
    }
  }
  // 追跡中：キーが戻れば終わり。位置を定期的に通知し、状態も頻繁に送る
  if (tracking) {
    if (pev == PresenceEvent::Arrived) {
      tracking = false;
      notifier.send(Prio::Default, "キーが見つかりました", "追跡を終わります");
    } else if (now - lastTrackNotifyMs >= TRACK_NOTIFY_MS) {
      lastTrackNotifyMs = now;
      notifier.send(Prio::High, "追跡中の位置", (gps.hasFix(now) ? String("測位中") : String("最後に測位した位置")) + mapLink(),
                    "round_pushpin");
    }
    if (now - lastStateMs >= TRACK_STATE_MS) stateDirty = true;
  }

  // ---- 点検の予定・凍結 ----
  checkMaint(now);
  checkFreeze();

  // ---- 更新の確認：ntfy と通信でき、しばらく正常に動いたら「正常」にする。だめなら前の版に戻す ----
  if (otaPending) {
    if (now > OTA_MIN_RUN_MS && (notifier.pollCount() > 0 || notifier.sentCount() > 0)) {
      esp_ota_mark_app_valid_cancel_rollback();
      otaPending = false;
      notifier.send(Prio::Low, "ファームウェアを更新しました", String("版 ") + FW_VERSION);
    } else if (now > OTA_VERIFY_MS) {
      Serial.println("OTA verify failed, rolling back");
      esp_ota_mark_app_invalid_rollback_and_reboot();
    }
  }

  // ---- ダッシュボード：電圧・温度の履歴と、状態の送信 ----
  if (battery.valid()) recordHistory(battery.volts());
  // 起動して Wi-Fi につながったら、すぐ 1 回送る（そのあとは 5 分ごとと、出来事のたび）
  bool firstState = lastStateMs == 0 && !parkTimerWake && WiFi.status() == WL_CONNECTED;
  // ntfy.sh の 1 日の上限に近づいたら、状態の送信を 1 時間ごとに減らす（通知の分を残す）
  bool slowState = notifier.sentLast24h(now) >= NTFY_DAILY_SOFT;
  uint32_t stateEvery = slowState ? STATE_SLOW_MS : STATE_PUBLISH_MS;
  stateEverySec = stateEvery / 1000;
  uint32_t stateGap = slowState ? STATE_SLOW_MS : STATE_MIN_GAP_MS;
  if (firstState || now - lastStateMs >= stateEvery || (stateDirty && now - lastStateMs >= stateGap) ||
      (parkTimerWake && lastStateMs == 0 && now - wakeMs >= PARK_KEY_SCAN_MS)) {
    publishState(now);
  }

  // ---- 駐車モード ----
  bool outputsOn = lockOut.on() || out2.on() || out3.on() || out4.on();
  bool busy = lockPending || buzzer.alarming() || !notifier.idle() || pauseUntilMs != 0 || doorWake || outputsOn ||
              portal.active() || otaPending || tracking;
  ParkInputs park{parkOn, inputs.acc(), engineRunning, presence.state() == PresenceState::Absent,
                  inputs.doorOpen(), busy};
  if (parkTimerWake) {
    // 時間で起きたとき：キーが近くに来ている・ACC ON・ドアが開いていれば、普段どおり動く
    if (presence.state() == PresenceState::Present || inputs.acc() || inputs.doorOpen() || !parkOn) {
      parkTimerWake = false;
      parkTimer.restart();
    } else {
      bool done = now - wakeMs >= PARK_KEY_SCAN_MS && notifier.pollCount() > pollsAtWake && notifier.idle() &&
                  lastStateMs != 0 && !portal.active() && !parkGpsCheck && !otaPending;
      uint32_t maxAwake = PARK_AWAKE_MAX_MS + (parkGpsCheck ? PARK_GPS_WAIT_MS : 0);
      if (done || (now - wakeMs > maxAwake && !portal.active() && !otaPending)) enterDeepSleep(SLEEP_PARK);
    }
  } else if (parkTimer.update(park, now)) {
    saveEngine();
    flushThenSleep(SLEEP_PARK);
  }

  // ---- シリアルに状態を出す（動作確認用） ----
  static uint32_t lastPrint = 0;
  if (now - lastPrint > 10000) {
    lastPrint = now;
    Serial.printf("V=%.2f acc=%d eng=%d door=%d key=%s rssi=%d armed=%d wifi=%d gps=%d obd=%d\n",
                  battery.volts(), inputs.acc(), engineRunning, inputs.doorOpen(), presenceName(),
                  presence.lastRssi(), armed, WiFi.status() == WL_CONNECTED, gps.hasFix(now), obd.fresh(now));
  }
  delay(2);
}
