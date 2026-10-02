#include "settings.h"

#include <Preferences.h>

using namespace starter;

static const char* NVS_NS = "starter";
static const char* NVS_KEY = "settings";

PresenceConfig Settings::presenceConfig() const {
  PresenceConfig c;
  c.nearRssi = nearRssi;
  c.farRssi = farRssi;
  c.absentTimeoutMs = absentSec * 1000UL;
  return c;
}

void Settings::toJson(JsonDocument& doc) const {
  JsonArray sch = doc["schedules"].to<JsonArray>();
  for (int i = 0; i < scheduleCount; ++i) {
    const ScheduleEntry& e = schedules[i];
    JsonObject o = sch.add<JsonObject>();
    o["enabled"] = e.enabled;
    o["days"] = e.days;
    char t[6];
    snprintf(t, sizeof(t), "%02u:%02u", e.hour, e.minute);
    o["time"] = t;
  }

  JsonObject al = doc["autoLock"].to<JsonObject>();
  al["enabled"] = autoLockEnabled;
  al["lockWhileRunning"] = lockWhileRunning;
  al["nearRssi"] = nearRssi;
  al["farRssi"] = farRssi;
  al["absentSec"] = absentSec;

  JsonArray bs = doc["beacons"].to<JsonArray>();
  for (int i = 0; i < beaconCount; ++i) {
    const BeaconRule& r = beacons[i];
    JsonObject o = bs.add<JsonObject>();
    if (r.type == BeaconRule::Mac) {
      char m[18];
      snprintf(m, sizeof(m), "%02x:%02x:%02x:%02x:%02x:%02x", r.mac[0], r.mac[1], r.mac[2], r.mac[3],
               r.mac[4], r.mac[5]);
      o["mac"] = m;
    } else {
      char u[37];
      formatUuid(r.uuid, u);
      o["uuid"] = u;
      o["major"] = r.major;
      o["minor"] = r.minor;
    }
  }

  JsonObject bat = doc["battery"].to<JsonObject>();
  bat["cal"] = vbatCal;
  bat["minStartV"] = minStartV;
}

bool Settings::fromJson(const JsonDocument& doc, String& err) {
  Settings n = *this;

  if (doc["schedules"].is<JsonArrayConst>()) {
    JsonArrayConst sch = doc["schedules"];
    if (sch.size() > MAX_SCHEDULES) {
      err = "スケジュールは最大 " + String(MAX_SCHEDULES) + " 件です";
      return false;
    }
    n.scheduleCount = 0;
    for (JsonObjectConst o : sch) {
      ScheduleEntry e;
      e.enabled = o["enabled"] | false;
      e.days = (o["days"] | 0) & 0x7F;
      const char* t = o["time"] | "";
      int h, m;
      if (sscanf(t, "%d:%d", &h, &m) != 2 || h < 0 || h > 23 || m < 0 || m > 59) {
        err = String("時刻の形式が不正です: ") + t;
        return false;
      }
      e.hour = h;
      e.minute = m;
      n.schedules[n.scheduleCount++] = e;
    }
  }

  if (doc["autoLock"].is<JsonObjectConst>()) {
    JsonObjectConst al = doc["autoLock"];
    n.autoLockEnabled = al["enabled"] | n.autoLockEnabled;
    n.lockWhileRunning = al["lockWhileRunning"] | n.lockWhileRunning;
    n.nearRssi = al["nearRssi"] | n.nearRssi;
    n.farRssi = al["farRssi"] | n.farRssi;
    n.absentSec = al["absentSec"] | n.absentSec;
    if (n.nearRssi < n.farRssi || n.nearRssi > -20 || n.farRssi < -110) {
      err = "RSSI は -110〜-20 で、近距離 ≧ 圏外 にしてください";
      return false;
    }
    if (n.absentSec < 5 || n.absentSec > 600) {
      err = "離脱判定時間は 5〜600 秒にしてください";
      return false;
    }
  }

  if (doc["beacons"].is<JsonArrayConst>()) {
    JsonArrayConst bs = doc["beacons"];
    if (bs.size() > MAX_BEACONS) {
      err = "ビーコンは最大 " + String(MAX_BEACONS) + " 個です";
      return false;
    }
    n.beaconCount = 0;
    for (JsonObjectConst o : bs) {
      BeaconRule r;
      if (o["mac"].is<const char*>()) {
        r.type = BeaconRule::Mac;
        if (!parseMac(o["mac"].as<const char*>(), r.mac)) {
          err = "MAC アドレスが不正です";
          return false;
        }
      } else if (o["uuid"].is<const char*>()) {
        r.type = BeaconRule::IBeaconId;
        if (!parseUuid(o["uuid"].as<const char*>(), r.uuid)) {
          err = "UUID が不正です";
          return false;
        }
        r.major = o["major"] | -1;
        r.minor = o["minor"] | -1;
      } else {
        err = "ビーコンには mac か uuid が必要です";
        return false;
      }
      n.beacons[n.beaconCount++] = r;
    }
  }

  if (doc["battery"].is<JsonObjectConst>()) {
    JsonObjectConst bat = doc["battery"];
    n.vbatCal = bat["cal"] | n.vbatCal;
    n.minStartV = bat["minStartV"] | n.minStartV;
    if (n.vbatCal < 0.8f || n.vbatCal > 1.2f) {
      err = "電圧補正係数は 0.8〜1.2 にしてください";
      return false;
    }
    if (n.minStartV < 11.0f || n.minStartV > 13.0f) {
      err = "始動許可電圧は 11.0〜13.0V にしてください";
      return false;
    }
  }

  *this = n;
  return true;
}

void Settings::load() {
  Preferences p;
  p.begin(NVS_NS, true);
  String s = p.getString(NVS_KEY, "");
  p.end();
  if (s.isEmpty()) return;
  JsonDocument doc;
  String err;
  if (deserializeJson(doc, s) || !fromJson(doc, err)) {
    log_e("settings load failed: %s", err.c_str());
  }
}

void Settings::save() const {
  JsonDocument doc;
  toJson(doc);
  String s;
  serializeJson(doc, s);
  Preferences p;
  p.begin(NVS_NS, false);
  p.putString(NVS_KEY, s);
  p.end();
}
