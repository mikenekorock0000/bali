#include "remote_core.h"

#include <cstdio>

namespace rc {

Kind kindFromRemoteType(const std::string& t) {
  // DIY の機器は学習ボタン（＋電源）しか使えないので一覧画面にする
  if (t.rfind("DIY", 0) == 0) return Kind::Generic;
  if (t == "Air Conditioner") return Kind::AirCon;
  if (t == "TV" || t == "IPTV" || t == "Streamer" || t == "Set Top Box") return Kind::TV;
  if (t == "Speaker" || t == "DVD") return Kind::Media;
  if (t == "Light") return Kind::Light;
  if (t == "Fan") return Kind::Fan;
  return Kind::Generic;
}

const char* kindLabel(Kind k) {
  switch (k) {
    case Kind::AirCon: return "エアコン";
    case Kind::TV: return "テレビ";
    case Kind::Media: return "オーディオ";
    case Kind::Light: return "照明";
    case Kind::Fan: return "扇風機";
    case Kind::Scenes: return "シーン";
    case Kind::Generic: break;
  }
  return "リモコン";
}

// ---------------------------------------------------------------- エアコン

bool AcState::addTemp(int delta) {
  int t = temp + delta;
  if (t < kMinTemp) t = kMinTemp;
  if (t > kMaxTemp) t = kMaxTemp;
  bool changed = t != temp;
  temp = t;
  return changed;
}

void AcState::nextMode() {
  // 冷房 → 暖房 → 除湿 → 送風 → 自動 → 冷房（よく使う順）
  static const int order[] = {2, 5, 3, 4, 1};
  int i = 0;
  while (i < 5 && order[i] != mode) i++;
  mode = i < 5 ? order[(i + 1) % 5] : 2;  // 想定外の値なら冷房へ
}

void AcState::nextFan() { fan = fan >= 4 ? 1 : fan + 1; }

std::string AcState::toParameter() const {
  char buf[32];
  snprintf(buf, sizeof buf, "%d,%d,%d,%s", temp, mode, fan, power ? "on" : "off");
  return buf;
}

uint32_t AcState::pack() const {
  return 0xAC000000u | (uint32_t(temp) << 16) | (uint32_t(mode) << 8) | (uint32_t(fan) << 4) |
         (power ? 1u : 0u);
}

AcState AcState::unpack(uint32_t v) {
  AcState s;
  if ((v & 0xFF000000u) != 0xAC000000u) return s;  // 未保存・壊れた値は初期値
  int t = (v >> 16) & 0xFF, m = (v >> 8) & 0xFF, f = (v >> 4) & 0xF;
  if (t >= kMinTemp && t <= kMaxTemp) s.temp = t;
  if (m >= 1 && m <= 5) s.mode = m;
  if (f >= 1 && f <= 4) s.fan = f;
  s.power = v & 1;
  return s;
}

const char* acModeLabel(int mode) {
  switch (mode) {
    case 1: return "自動";
    case 2: return "冷房";
    case 3: return "除湿";
    case 4: return "送風";
    case 5: return "暖房";
  }
  return "?";
}

const char* acFanLabel(int fan) {
  switch (fan) {
    case 1: return "自動";
    case 2: return "弱";
    case 3: return "中";
    case 4: return "強";
  }
  return "?";
}

// ---------------------------------------------------------------- 送るもの

std::string jsonEscape(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 2);
  for (unsigned char ch : s) {
    switch (ch) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (ch < 0x20) {
          char buf[8];
          snprintf(buf, sizeof buf, "\\u%04x", ch);
          out += buf;
        } else {
          out += char(ch);  // 日本語（UTF-8）はそのまま
        }
    }
  }
  return out;
}

std::string commandJson(const Command& c) {
  return "{\"command\":\"" + jsonEscape(c.command) + "\",\"parameter\":\"" +
         jsonEscape(c.parameter) + "\",\"commandType\":\"" +
         (c.customize ? "customize" : "command") + "\"}";
}

std::vector<ListItem> genericItems(const std::string& deviceId, const std::string& remoteType,
                                   const std::vector<std::string>& customButtons) {
  std::vector<ListItem> items;
  // 「その他」は電源コマンドも無い（学習ボタンだけ）
  if (remoteType != "Others") {
    items.push_back({"電源 ON", {deviceId, "turnOn"}});
    items.push_back({"電源 OFF", {deviceId, "turnOff"}});
  }
  for (const auto& b : customButtons) {
    Command c{deviceId, b};
    c.customize = true;
    items.push_back({b, c});
  }
  return items;
}

}  // namespace rc
