#include "switchbot.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <esp_system.h>
#include <mbedtls/base64.h>
#include <mbedtls/md.h>
#include <sys/time.h>

#include "root_ca.h"

static const char* kApi = "https://api.switch-bot.com/v1.1";

void SwitchBot::signHeaders(String& t, String& nonce, String& sign) {
  // sign = Base64(HMAC-SHA256(secret, token + t + nonce))。t はミリ秒の UNIX 時刻（NTP 必須）
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  char tbuf[24];
  snprintf(tbuf, sizeof tbuf, "%llu", (unsigned long long)tv.tv_sec * 1000ULL + tv.tv_usec / 1000);
  t = tbuf;
  char nbuf[17];
  snprintf(nbuf, sizeof nbuf, "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
  nonce = nbuf;

  String data = String(token_) + t + nonce;
  uint8_t mac[32];
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256),
                  (const uint8_t*)secret_, strlen(secret_),
                  (const uint8_t*)data.c_str(), data.length(), mac);
  unsigned char b64[64];
  size_t olen = 0;
  mbedtls_base64_encode(b64, sizeof b64, &olen, mac, sizeof mac);
  sign = String((const char*)b64).substring(0, olen);
}

ApiResult SwitchBot::request(const char* method, const String& path, const String& body,
                             String& response) {
  ApiResult r;
  WiFiClientSecure client;
  client.setCACert(SWITCHBOT_ROOT_CA);
  HTTPClient http;
  http.setTimeout(10000);
  if (!http.begin(client, String(kApi) + path)) {
    r.message = "接続できません";
    return r;
  }
  String t, nonce, sign;
  signHeaders(t, nonce, sign);
  http.addHeader("Authorization", token_);
  http.addHeader("sign", sign);
  http.addHeader("t", t);
  http.addHeader("nonce", nonce);
  http.addHeader("Content-Type", "application/json; charset=utf8");

  r.httpCode = strcmp(method, "POST") == 0 ? http.POST(body) : http.GET();
  if (r.httpCode <= 0) {
    r.message = "通信エラー";
    http.end();
    return r;
  }
  response = http.getString();
  http.end();

  if (r.httpCode == 401) { r.message = "トークンが違います"; return r; }
  if (r.httpCode == 429) { r.message = "回数制限(1日1万回)"; return r; }
  if (r.httpCode != 200) { r.message = "HTTP " + String(r.httpCode); return r; }

  // statusCode だけ先に見る（本文は呼び出し側で読む）
  JsonDocument filter;
  filter["statusCode"] = true;
  filter["message"] = true;
  JsonDocument doc;
  if (deserializeJson(doc, response, DeserializationOption::Filter(filter))) {
    r.message = "応答が読めません";
    return r;
  }
  r.statusCode = doc["statusCode"] | 0;
  r.ok = r.statusCode == 100;
  if (!r.ok) {
    switch (r.statusCode) {
      case 161: r.message = "機器がオフライン"; break;
      case 171: r.message = "ハブがオフライン"; break;
      case 152: r.message = "機器が見つかりません"; break;
      case 160: r.message = "未対応のコマンド"; break;
      default: r.message = "エラー " + String(r.statusCode);
    }
  }
  return r;
}

static bool isSensorType(const char* t) {
  static const char* types[] = {"Hub 2", "Hub 3", "Meter", "MeterPlus", "Meter Pro",
                                "Meter Pro(CO2)", "WoIOSensor"};
  for (auto s : types)
    if (strcmp(t, s) == 0) return true;
  return false;
}

ApiResult SwitchBot::listDevices(std::vector<Remote>& remotes, std::string& sensorId) {
  String res;
  ApiResult r = request("GET", "/devices", "", res);
  if (!r.ok) return r;

  JsonDocument filter;
  filter["body"]["deviceList"][0]["deviceId"] = true;
  filter["body"]["deviceList"][0]["deviceType"] = true;
  filter["body"]["infraredRemoteList"][0]["deviceId"] = true;
  filter["body"]["infraredRemoteList"][0]["deviceName"] = true;
  filter["body"]["infraredRemoteList"][0]["remoteType"] = true;
  JsonDocument doc;
  deserializeJson(doc, res, DeserializationOption::Filter(filter));

  remotes.clear();
  for (JsonObject d : doc["body"]["infraredRemoteList"].as<JsonArray>()) {
    Remote rm;
    rm.id = d["deviceId"] | "";
    rm.name = d["deviceName"] | "";
    rm.remoteType = d["remoteType"] | "";
    rm.kind = rc::kindFromRemoteType(rm.remoteType);
    if (!rm.id.empty()) remotes.push_back(rm);
  }
  // ハブ2 を優先（リモコンを置く部屋にある）
  std::string fallback;
  for (JsonObject d : doc["body"]["deviceList"].as<JsonArray>()) {
    const char* type = d["deviceType"] | "";
    if (!isSensorType(type)) continue;
    if (strncmp(type, "Hub", 3) == 0 && sensorId.empty()) sensorId = d["deviceId"] | "";
    if (fallback.empty()) fallback = d["deviceId"] | "";
  }
  if (sensorId.empty()) sensorId = fallback;
  return r;
}

ApiResult SwitchBot::listScenes(std::vector<Scene>& scenes) {
  String res;
  ApiResult r = request("GET", "/scenes", "", res);
  if (!r.ok) return r;
  JsonDocument doc;
  deserializeJson(doc, res);
  scenes.clear();
  for (JsonObject s : doc["body"].as<JsonArray>()) {
    Scene sc{s["sceneId"] | "", s["sceneName"] | ""};
    if (!sc.id.empty()) scenes.push_back(sc);
  }
  return r;
}

ApiResult SwitchBot::send(const rc::Command& cmd) {
  String res;
  if (cmd.scene) return request("POST", "/scenes/" + String(cmd.deviceId.c_str()) + "/execute", "", res);
  return request("POST", "/devices/" + String(cmd.deviceId.c_str()) + "/commands",
                 String(rc::commandJson(cmd).c_str()), res);
}

ApiResult SwitchBot::readSensor(const std::string& deviceId, float& temp, int& humidity) {
  String res;
  ApiResult r = request("GET", "/devices/" + String(deviceId.c_str()) + "/status", "", res);
  if (!r.ok) return r;
  JsonDocument doc;
  deserializeJson(doc, res);
  JsonVariant b = doc["body"];
  if (b["temperature"].isNull()) {
    r.ok = false;
    r.message = "温度が読めない機器";
    return r;
  }
  temp = b["temperature"].as<float>();
  humidity = b["humidity"] | -1;
  return r;
}
