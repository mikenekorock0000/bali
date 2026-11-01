#include "settings.h"

#include <Preferences.h>

// 初回起動時の初期値。secrets.h があればその値、なければ空（設定モードで入力する）
#if __has_include("secrets.h")
#include "secrets.h"
#endif
#ifndef WIFI_SSID
#define WIFI_SSID ""
#define WIFI_PASS ""
#endif
#ifndef HOSTNAME
#define HOSTNAME "hijet-monitor"
#endif
#ifndef OTA_PASS
#define OTA_PASS ""
#endif
#ifndef NTFY_SERVER
#define NTFY_SERVER "https://ntfy.sh"
#endif
#ifndef NTFY_TOPIC
#define NTFY_TOPIC ""
#endif
#ifndef NTFY_CMD_TOPIC
#define NTFY_CMD_TOPIC ""
#endif
#ifndef NTFY_STATE_TOPIC
#define NTFY_STATE_TOPIC ""
#endif
#ifndef NTFY_TOKEN
#define NTFY_TOKEN ""
#endif
#ifndef CMD_PIN
#define CMD_PIN ""
#endif
#ifndef BEACON_RULES
#define BEACON_RULES {""}
#endif

Settings settings;

namespace {
Preferences p;
const char* NS = "settings";
}  // namespace

void Settings::load() {
  p.begin(NS, true);
  bool have = p.isKey("ssid1");
  if (have) {
    ssid1 = p.getString("ssid1", "");
    pass1 = p.getString("pass1", "");
    ssid2 = p.getString("ssid2", "");
    pass2 = p.getString("pass2", "");
    ntfyServer = p.getString("server", NTFY_SERVER);
    topic = p.getString("topic", "");
    cmdTopic = p.getString("cmdtopic", "");
    stateTopic = p.getString("sttopic", "");
    token = p.getString("token", "");
    notifyServer = p.getString("nserver", "");
    notifyToken = p.getString("ntoken", "");
    pin = p.getString("pin", "");
    otaPass = p.getString("otapass", "");
    hostname = p.getString("host", HOSTNAME);
    for (int i = 0; i < MAX_BEACONS; ++i) beacons[i] = p.getString(("bcn" + String(i)).c_str(), "");
    vbatCal = p.getFloat("vcal", 1.0f);
    cmdKey = p.getString("cmdkey", "");
    tlsInsecure = p.getBool("tlsins", false);
    maint = p.getString("maint", "");
    odoKm = p.getInt("odokm", 0);
    odoGpsKm = p.getFloat("odogps", 0);
  }
  p.end();
  if (have) return;

  // 初回：secrets.h の値（なければ空）
  ssid1 = WIFI_SSID;
  pass1 = WIFI_PASS;
  ntfyServer = NTFY_SERVER;
  topic = NTFY_TOPIC;
  cmdTopic = NTFY_CMD_TOPIC;
  stateTopic = NTFY_STATE_TOPIC;
  if (stateTopic.isEmpty() && topic.length()) stateTopic = topic + "-state";
  token = NTFY_TOKEN;
  pin = CMD_PIN;
  otaPass = OTA_PASS;
  hostname = HOSTNAME;
  const char* rules[] = BEACON_RULES;
  int n = 0;
  for (const char* r : rules) {
    if (n < MAX_BEACONS && r[0]) beacons[n++] = r;
  }
  vbatCal = 1.0f;
}

void Settings::save() const {
  p.begin(NS, false);
  p.putString("ssid1", ssid1);
  p.putString("pass1", pass1);
  p.putString("ssid2", ssid2);
  p.putString("pass2", pass2);
  p.putString("server", ntfyServer);
  p.putString("topic", topic);
  p.putString("cmdtopic", cmdTopic);
  p.putString("sttopic", stateTopic);
  p.putString("token", token);
  p.putString("nserver", notifyServer);
  p.putString("ntoken", notifyToken);
  p.putString("pin", pin);
  p.putString("otapass", otaPass);
  p.putString("host", hostname);
  for (int i = 0; i < MAX_BEACONS; ++i) p.putString(("bcn" + String(i)).c_str(), beacons[i]);
  p.putFloat("vcal", vbatCal);
  p.putString("cmdkey", cmdKey);
  p.putBool("tlsins", tlsInsecure);
  p.putString("maint", maint);
  p.putInt("odokm", odoKm);
  p.putFloat("odogps", odoGpsKm);
  p.end();
}

void Settings::ensureKey() {
  if (cmdKey.length() == 32) return;
  cmdKey = newKey();
  p.begin(NS, false);
  p.putString("cmdkey", cmdKey);
  p.end();
}

String Settings::newKey() {
  char b[33];
  for (int i = 0; i < 4; ++i) snprintf(b + 8 * i, 9, "%08lx", (unsigned long)esp_random());
  return String(b);
}

int Settings::beaconCount() const {
  int n = 0;
  for (const String& b : beacons) {
    if (b.length()) ++n;
  }
  return n;
}
