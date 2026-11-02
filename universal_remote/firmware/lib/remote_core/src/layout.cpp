#include "layout.h"

#include <ArduinoJson.h>

namespace rc {

static int findByName(const std::vector<DeviceRef>& v, const std::string& name) {
  for (size_t i = 0; i < v.size(); i++)
    if (v[i].name == name) return int(i);
  return -1;
}

bool parseColor(const std::string& s, uint32_t& out) {
  if (s.size() != 7 || s[0] != '#') return false;
  uint32_t v = 0;
  for (size_t i = 1; i < 7; i++) {
    char c = s[i];
    int d = (c >= '0' && c <= '9') ? c - '0'
          : (c >= 'a' && c <= 'f') ? c - 'a' + 10
          : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : -1;
    if (d < 0) return false;
    v = v << 4 | uint32_t(d);
  }
  out = v;
  return true;
}

namespace {

struct Ctx {
  const std::vector<DeviceRef>& remotes;
  const std::vector<DeviceRef>& scenes;
  std::vector<std::string>& errors;
};

std::string str(JsonVariantConst v) { return v.is<const char*>() ? v.as<const char*>() : ""; }

// アクション 1 つを読む。where はエラー表示用（「スピーカー の top」など）
Action parseAction(JsonVariantConst j, int pageRemote, const std::string& where, Ctx& c) {
  Action a;
  if (!j.is<JsonObjectConst>()) {
    c.errors.push_back(where + ": ボタンの書き方が違います");
    return a;
  }
  std::string cmd = str(j["cmd"]), btn = str(j["btn"]), scene = str(j["scene"]);
  int kinds = !cmd.empty() + !btn.empty() + !scene.empty();
  if (kinds != 1) {
    c.errors.push_back(where + ": cmd・btn・scene のどれか 1 つを書いてください");
    return a;
  }
  if (!scene.empty()) {
    int s = findByName(c.scenes, scene);
    if (s < 0) {
      c.errors.push_back(where + ": シーン「" + scene + "」がありません");
      return a;
    }
    a.cmd.deviceId = c.scenes[s].id;
    a.cmd.command = "execute";
    a.cmd.scene = true;
    a.label = scene;
  } else {
    int r = pageRemote;
    std::string target = str(j["remote"]);
    if (!target.empty()) {
      r = findByName(c.remotes, target);
      if (r < 0) {
        c.errors.push_back(where + ": リモコン「" + target + "」がありません");
        return a;
      }
    }
    if (r < 0) {
      c.errors.push_back(where + ": どのリモコンに送るか（remote）がありません");
      return a;
    }
    a.cmd.deviceId = c.remotes[r].id;
    a.cmd.command = cmd.empty() ? btn : cmd;
    a.cmd.customize = !btn.empty();
    if (!str(j["param"]).empty()) a.cmd.parameter = str(j["param"]);
    a.label = a.cmd.command;
  }
  if (!str(j["label"]).empty()) a.label = str(j["label"]);
  a.valid = true;
  return a;
}

}  // namespace

LayoutResult parseLayout(const char* json, const std::vector<DeviceRef>& remotes,
                         const std::vector<DeviceRef>& scenes) {
  LayoutResult res;
  if (!json || !*json) return res;
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, json);
  if (err) {
    res.errors.push_back(std::string("layout.h の JSON が読めません: ") + err.c_str());
    return res;
  }
  JsonArrayConst pages = doc["pages"];
  if (pages.isNull()) return res;
  res.usePages = true;
  Ctx c{remotes, scenes, res.errors};

  int n = 0;
  for (JsonVariantConst pj : pages) {
    n++;
    PageSpec p;
    std::string remoteName = str(pj["remote"]);
    p.title = str(pj["title"]);
    p.scenes = pj["scenes"] | false;
    std::string where = !remoteName.empty() ? remoteName
                      : !p.title.empty()    ? p.title
                                            : std::to_string(n) + " ページ目";
    if (!remoteName.empty()) {
      p.remote = findByName(remotes, remoteName);
      if (p.remote < 0) {
        res.errors.push_back("リモコン「" + remoteName + "」がありません");
        continue;
      }
    }
    std::string color = str(pj["color"]);
    if (!color.empty()) {
      p.hasColor = parseColor(color, p.color);
      if (!p.hasColor) res.errors.push_back(where + ": color は \"#RRGGBB\" で書いてください");
    }

    if (!pj["dial"].isNull()) {
      JsonVariantConst d = pj["dial"];
      p.custom = true;
      p.dialLabel = str(d["label"]);
      p.dialUp = parseAction(d["up"], p.remote, where + " の dial.up", c);
      p.dialDown = parseAction(d["down"], p.remote, where + " の dial.down", c);
    }
    static const char* zones[] = {"top", "center", "bottom"};
    Action* slots[] = {&p.top, &p.center, &p.bottom};
    for (int z = 0; z < 3; z++) {
      if (pj[zones[z]].isNull()) continue;
      p.custom = true;
      *slots[z] = parseAction(pj[zones[z]], p.remote, where + " の " + zones[z], c);
    }
    if (!pj["list"].isNull()) {
      p.hasList = true;
      int i = 0;
      for (JsonVariantConst lj : pj["list"].as<JsonArrayConst>()) {
        i++;
        Action a = parseAction(lj, p.remote, where + " の list " + std::to_string(i) + " 番目", c);
        if (a.valid) p.list.push_back({a.label, a.cmd});
      }
    }
    if (p.remote < 0 && !p.scenes && !p.custom && !p.hasList) {
      res.errors.push_back(where + ": remote・scenes・ボタンのどれもありません");
      continue;
    }
    res.pages.push_back(std::move(p));
  }
  return res;
}

}  // namespace rc
