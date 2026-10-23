// HIJET MONITOR：ハイゼット ジャンボの見守り装置（ESP32 DevKit V1 ＋ 専用基板 v4）
//
// - キー（BLE ビーコン）が離れたら、ドアが閉まっていれば自動で施錠信号を出す
// - キーが無いのにドアが開いた・車体が揺れたら通知（ブザー警報は任意）
// - バッテリー：低電圧、始動時の電圧の落ち込み、走行中の充電不良を通知
// - OBD-II：水温・回転数・車速・警告灯。エンジン稼働時間とオイル交換時期
// - GPS：走行ごとの距離・最高速度、駐車位置
// - 車内の温度・湿度
// 通知は ntfy、スマホからの指示は ntfy の指示用トピック（"<暗証番号> <指示>"）で受け取る。
#include <Arduino.h>
#include <ArduinoJson.h>
#include <ArduinoOTA.h>
#include <Preferences.h>
#include <WiFi.h>
#include <driver/gpio.h>
#include <esp_sleep.h>
#include <time.h>

#include <algorithm>
#include <vector>

#include "battery.h"
#include "battery_health.h"
#include "ble_presence.h"
#include "buzzer.h"
#include "config.h"
#include "cooldown.h"
#include "gps.h"
#include "io.h"
#include "notifier.h"
#include "obd.h"
#include "park_sleep.h"
#include "presence.h"
#include "secrets_select.h"
#include "sensors.h"

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
                   CD_LOW, CD_COUNT };
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

// ---- スマホからの指示（"<暗証番号> <指示> [引数]"） ----
void handleCommand(String line, uint32_t now) {
  line.trim();
  String pin = String(CMD_PIN) + " ";
  if (!line.startsWith(pin)) return;  // 暗証番号が違うものは黙って無視
  String cmd = line.substring(pin.length());
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
  } else if (cmd == "oilreset") {
    oilBaseSec = engineSec;
    prefs.putUInt("oilbase", oilBaseSec);
    cooldown.reset(CD_OIL);
    notifier.send(Prio::Low, "オイル交換を記録", "次回まで " + fmt1(OIL_CHANGE_HOURS) + "h");
  } else {
    notifier.send(Prio::Low, "不明な指示",
                  "status / scan / lock / pause [分] / resume / autolock on|off / alarm on|off / "
                  "siren on|off / park on|off / beep / silence / oilreset");
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
  rtcHaveLast = gps.lastKnown(rtcLat, rtcLon);
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
  uint32_t until = millis() + 20000;
  while (millis() < until && !notifier.idle()) {
    notifier.loop(millis());
    delay(50);
  }
  enterDeepSleep(kind);
}

void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  configTzTime(TZ_JAPAN, NTP_SERVER1, NTP_SERVER2);
  ArduinoOTA.setHostname(HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASS);
  ArduinoOTA.begin();
}

void setupBeacons() {
  const char* rules[] = BEACON_RULES;
  BeaconRule parsed[MAX_BEACONS];
  int n = 0;
  for (const char* r : rules) {
    if (n < MAX_BEACONS && parseBeaconRule(r, parsed[n])) {
      ++n;
    } else {
      Serial.printf("beacon rule ignored: %s\n", r);
    }
  }
  ble.setRules(parsed, n);
}

}  // namespace

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
    if (rtcHaveLast) gps.setLastKnown(rtcLat, rtcLon);
  }

  // 時間で起きたとき：電圧が低ければ、Wi-Fi も BLE も使わずにすぐ眠り直す
  if (cause == ESP_SLEEP_WAKEUP_TIMER) {
    pinMode(PIN_ACC, INPUT);
    float v = (battery.sampleNow() + battery.sampleNow()) / 2;
    bool accOff = digitalRead(PIN_ACC) == HIGH;
    if (accOff && slept == SLEEP_LOW_VOLTAGE && v < VBAT_LOW_RECOVER) enterDeepSleep(SLEEP_LOW_VOLTAGE);
    if (accOff && slept == SLEEP_PARK && v < VBAT_SLEEP) enterDeepSleep(SLEEP_LOW_VOLTAGE);
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

  wakeMs = millis();
  if (cause == ESP_SLEEP_WAKEUP_EXT1) {
    doorWake = true;  // キーが見つかるまで少し待ってから、侵入かどうか判断する
  } else if (cause == ESP_SLEEP_WAKEUP_TIMER && slept == SLEEP_PARK) {
    parkTimerWake = true;  // 指示の確認などが済んだらまた眠る
    notifier.pollSoon();
  } else if (cause != ESP_SLEEP_WAKEUP_EXT0 && cause != ESP_SLEEP_WAKEUP_TIMER) {
    notifier.send(Prio::Min, "起動しました",
                  String("BME280 ") + (sensors.hasEnv() ? "あり" : "なし") + " / MPU6050 " +
                      (sensors.hasMotion() ? "あり" : "なし"));
  }
  lastEngineTickMs = millis();
}

void loop() {
  uint32_t now = millis();
  ArduinoOTA.handle();

  inputs.loop(now);
  battery.loop(now);
  ble.loop();
  sensors.loop(now);
  gps.loop(now);
  obd.loop(now);
  lockOut.loop(now);
  out2.loop(now);
  out3.loop(now);
  out4.loop(now);
  buzzer.loop(now);
  notifier.loop(now);

  // ---- キー（ビーコン）の在・不在 ----
  int rssi;
  if (ble.takeMatch(rssi)) presence.onSeen(rssi, now);
  PresenceEvent pev = presence.update(now);
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
      crank.start(now);
      obd.setActive(true, now);
      gps.startTrip(now);
      cooldown.reset(CD_MIL);
      buzzer.stop();
    } else {
      obd.setActive(false, now);
      saveEngine();
      TripSummary t = gps.endTrip(now);
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
  ble.setEnabled(!battery.lowVoltage() || inputs.acc());
  if (battery.valid() && battery.volts() < VBAT_SLEEP && !inputs.acc() && now > 120000) {
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
  while (notifier.takeCommand(cmd)) handleCommand(cmd, now);

  // ---- 毎日の報告 ----
  struct tm t;
  if (DAILY_REPORT_HOUR >= 0 && time(nullptr) > 1700000000 && getLocalTime(&t, 0)) {
    if (t.tm_hour == DAILY_REPORT_HOUR && t.tm_yday != lastReportDay) {
      lastReportDay = t.tm_yday;
      notifier.send(Prio::Min, "毎日の報告", statusText(now));
    }
  }

  // ---- 駐車モード ----
  bool outputsOn = lockOut.on() || out2.on() || out3.on() || out4.on();
  bool busy = lockPending || buzzer.alarming() || !notifier.idle() || pauseUntilMs != 0 || doorWake || outputsOn;
  ParkInputs park{parkOn, inputs.acc(), engineRunning, presence.state() == PresenceState::Absent,
                  inputs.doorOpen(), busy};
  if (parkTimerWake) {
    // 時間で起きたとき：キーが近くに来ている・ACC ON・ドアが開いていれば、普段どおり動く
    if (presence.state() == PresenceState::Present || inputs.acc() || inputs.doorOpen() || !parkOn) {
      parkTimerWake = false;
      parkTimer.restart();
    } else {
      bool done = now - wakeMs >= PARK_KEY_SCAN_MS && notifier.pollCount() > pollsAtWake && notifier.idle();
      if (done || now - wakeMs > PARK_AWAKE_MAX_MS) enterDeepSleep(SLEEP_PARK);
    }
  } else if (parkTimer.update(park, now)) {
    saveEngine();
    enterDeepSleep(SLEEP_PARK);
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
