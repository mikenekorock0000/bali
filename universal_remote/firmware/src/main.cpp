// まとめリモコン — M5Stack Dial ＋ SwitchBot ハブ2
//
// ダイヤルで温度・音量・明るさ、画面タップで電源やモード。赤外線はハブ2 が出す。
// 画面:
//   ホーム   … ダイヤルで機器を選ぶ → タップかボタンで開く。ボタン長押しで再読み込み
//   機器画面 … ダイヤル・タップ（上/真ん中/下）で操作。左右にはらうと隣の機器、ボタンで戻る
//              画面を長押しすると「電源＋学習ボタン」の一覧
#include <M5Dial.h>
#include <Preferences.h>
#include <WiFi.h>
#include <time.h>

#include <cmath>

#include "config.h"
#include "remote_core.h"
#include "switchbot.h"
#include "layout.h"

// 画面の並び・ボタンの名前と配置（無ければ全部自動）
#if __has_include("my_layout.h")
#include "my_layout.h"
#else
static const char LAYOUT_JSON[] = "";
#endif

#ifndef ENCODER_DIRECTION
#define ENCODER_DIRECTION 1
#endif

using rc::Kind;
using rc::Zone;

// ---------------------------------------------------------------- 色

static constexpr uint32_t C_BG = 0x000000;
static constexpr uint32_t C_TEXT = 0xFFFFFF;
static constexpr uint32_t C_SUB = 0x8A8F98;
static constexpr uint32_t C_TRACK = 0x22262C;
static constexpr uint32_t C_OFF = 0x4A4F57;
static constexpr uint32_t C_OK = 0x2E7D4F;
static constexpr uint32_t C_ERR = 0xC0392B;

static uint32_t acModeColor(int mode) {
  switch (mode) {
    case 2: return 0x3AA0FF;  // 冷房
    case 5: return 0xFF8A3D;  // 暖房
    case 3: return 0x2EC4B6;  // 除湿
    case 4: return 0x8BD450;  // 送風
  }
  return 0xB18CFF;  // 自動
}

static uint32_t kindColor(Kind k) {
  switch (k) {
    case Kind::AirCon: return 0x3AA0FF;
    case Kind::TV: return 0xE056FD;
    case Kind::Media: return 0xFF6B81;
    case Kind::Light: return 0xFFC93C;
    case Kind::Fan: return 0x8BD450;
    case Kind::Scenes: return 0xFF8A3D;
    case Kind::Generic: break;
  }
  return 0x9AA5B1;
}

// ---------------------------------------------------------------- 状態

struct Page {
  int remote = -1;  // remotes の添字。シーンは -1
  Kind kind = Kind::Generic;
  rc::AcState ac;
  bool on = false;    // 照明・扇風機の ON/OFF（こちらで覚えているだけ）
  int fanSpeed = 1;   // 1 弱 / 2 中 / 3 強
  int sel = 0;        // 一覧の選択位置
  bool list = false;  // 長押しで出す一覧モード
  std::vector<rc::ListItem> items;
  rc::PageSpec spec;  // my_layout.h で決めた名前・色・ボタン配置
};

static SwitchBot api(SWITCHBOT_TOKEN, SWITCHBOT_SECRET);
static std::vector<Remote> remotes;
static std::vector<Scene> scenes;
static std::vector<Page> pages;
static std::string sensorId = SENSOR_DEVICE_ID;
static std::vector<std::string> layoutErrors;
static Preferences prefs;
static M5Canvas canvas(&M5Dial.Display);

enum class Screen { Home, Device };
static Screen screen = Screen::Home;
static int cur = 0;  // 選んでいるページ
static bool dirty = true;

static rc::Debouncer pending(700);  // エアコン・扇風機の設定変更をまとめて送る
static int pendingPage = -1;
static rc::IdleTimer idle(DIM_AFTER_MS, SLEEP_AFTER_MS);
static rc::Backlight backlight = rc::Backlight::On;

static String toast;
static uint32_t toastColor = C_OK;
static uint32_t toastUntil = 0;

// 室温（通信タスクが書き、画面が読む）
static volatile float roomTemp = NAN;
static volatile int roomHum = -1;

// ---------------------------------------------------------------- 通信タスク
// HTTPS は 1 回 0.5〜2 秒かかるので、画面が固まらないよう別タスクで送る。

struct Job {
  rc::Command cmd;
};
struct JobResult {
  bool ok;
  char msg[48];
};
static QueueHandle_t jobQ, resQ;

static void worker(void*) {
  uint32_t lastSensor = 0;
  bool first = true;
  for (;;) {
    Job* job = nullptr;
    if (xQueueReceive(jobQ, &job, pdMS_TO_TICKS(500)) == pdTRUE && job) {
      JobResult r{false, ""};
      if (WiFi.status() != WL_CONNECTED) {
        strlcpy(r.msg, "Wi-Fi 切断中", sizeof r.msg);
      } else {
        ApiResult a = api.send(job->cmd);
        r.ok = a.ok;
        strlcpy(r.msg, a.message.c_str(), sizeof r.msg);
        if (!a.ok) Serial.printf("send %s failed: %d %d %s\n", job->cmd.command.c_str(),
                                 a.httpCode, a.statusCode, a.message.c_str());
      }
      xQueueSend(resQ, &r, 0);
      delete job;
    }
    uint32_t now = millis();
    if (!sensorId.empty() && WiFi.status() == WL_CONNECTED &&
        (first || now - lastSensor >= SENSOR_INTERVAL_MS)) {
      first = false;
      lastSensor = now;
      float t;
      int h;
      if (api.readSensor(sensorId, t, h).ok) {
        roomTemp = t;
        roomHum = h;
      }
    }
  }
}

static void beep(int hz = 4000, int ms = 15) {
#if BEEP
  M5Dial.Speaker.tone(hz, ms);
#endif
}

static void showToast(const String& s, uint32_t color = C_OK, uint32_t ms = 1500) {
  toast = s;
  toastColor = color;
  toastUntil = millis() + ms;
  dirty = true;
}

static void sendCmd(const rc::Command& c, const String& label) {
  Job* j = new Job{c};
  if (xQueueSend(jobQ, &j, 0) != pdTRUE) {
    delete j;
    showToast("混雑中", C_ERR);
    return;
  }
  beep();
  if (label.length()) showToast(label);
}

// ---------------------------------------------------------------- ページ

static std::vector<std::string> customButtonsFor(const std::string& remoteName) {
  std::vector<std::string> out;
  for (size_t i = 0; CUSTOM_BUTTONS[i][0]; i++)
    if (remoteName == CUSTOM_BUTTONS[i][0]) out.push_back(CUSTOM_BUTTONS[i][1]);
  return out;
}

static String acKey(const std::string& id) {
  uint32_t h = 2166136261u;  // FNV-1a（NVS のキーは 15 文字まで）
  for (char c : id) h = (h ^ uint8_t(c)) * 16777619u;
  char buf[12];
  snprintf(buf, sizeof buf, "ac%08lx", (unsigned long)h);
  return buf;
}

static Page remotePage(int i) {
  Page p;
  p.remote = i;
  p.kind = remotes[i].kind;
  p.items = rc::genericItems(remotes[i].id, remotes[i].remoteType, customButtonsFor(remotes[i].name));
  if (p.kind == Kind::AirCon)
    p.ac = rc::AcState::unpack(prefs.getUInt(acKey(remotes[i].id).c_str(), 0));
  return p;
}

static Page scenesPage() {
  Page p;
  p.kind = Kind::Scenes;
  for (auto& s : scenes) {
    rc::Command c{s.id, "execute"};
    c.scene = true;
    p.items.push_back({s.name, c});
  }
  return p;
}

static void buildPages() {
  pages.clear();
  std::vector<rc::DeviceRef> rr, ss;
  for (auto& r : remotes) rr.push_back({r.id, r.name, r.remoteType});
  for (auto& s : scenes) ss.push_back({s.id, s.name, ""});
  rc::LayoutResult lay = rc::parseLayout(LAYOUT_JSON, rr, ss);
  layoutErrors = lay.errors;
  for (auto& e : layoutErrors) Serial.printf("layout: %s\n", e.c_str());

  if (!lay.usePages) {  // 自動: 登録順に全部 ＋ シーン
    for (size_t i = 0; i < remotes.size(); i++) pages.push_back(remotePage(i));
    if (!scenes.empty()) pages.push_back(scenesPage());
    return;
  }
  for (auto& spec : lay.pages) {
    Page p = spec.scenes ? scenesPage() : spec.remote >= 0 ? remotePage(spec.remote) : Page{};
    if (!spec.scenes && spec.remote < 0) p.kind = Kind::Generic;  // リモコンに結びつかないページ
    if (spec.hasList) p.items = spec.list;
    p.spec = spec;
    pages.push_back(p);
  }
}

static const char* pageName(const Page& p) {
  if (!p.spec.title.empty()) return p.spec.title.c_str();
  return p.remote >= 0 ? remotes[p.remote].name.c_str() : "シーン";
}
static const std::string& pageId(const Page& p) { return remotes[p.remote].id; }
static bool showsList(const Page& p) {
  if (p.spec.custom) return p.list;  // 自由配置の画面は長押しのときだけ一覧
  return p.list || p.kind == Kind::Generic || p.kind == Kind::Scenes;
}
static uint32_t pageColor(const Page& p) { return p.spec.hasColor ? p.spec.color : kindColor(p.kind); }

// ---------------------------------------------------------------- 描画

static const lgfx::IFont* jp(int size) {
  switch (size) {
    case 12: return &fonts::lgfxJapanGothic_12;
    case 16: return &fonts::lgfxJapanGothic_16;
    case 20: return &fonts::lgfxJapanGothic_20;
    case 24: return &fonts::lgfxJapanGothic_24;
    case 28: return &fonts::lgfxJapanGothic_28;
    case 32: return &fonts::lgfxJapanGothic_32;
  }
  return &fonts::lgfxJapanGothic_16;
}

// 幅に収まるまで文字を小さくして中央に書く
static void text(const char* s, int y, int size, uint32_t color, int maxW = 200) {
  canvas.setTextColor(color);
  canvas.setTextDatum(middle_center);
  for (int sz = size; sz >= 12; sz -= 4) {
    canvas.setFont(jp(sz));
    if (canvas.textWidth(s) <= maxW || sz <= 12) break;
  }
  canvas.drawString(s, 120, y);
}

static void powerIcon(int cx, int cy, int r, uint32_t color) {
  canvas.fillArc(cx, cy, r - 3, r + 3, 300, 360, color);
  canvas.fillArc(cx, cy, r - 3, r + 3, 0, 240, color);
  canvas.drawWideLine(cx, cy - r - 4, cx, cy - 2, 3, color);
}

static void roomLine(int y) {
  float t = roomTemp;
  int h = roomHum;
  if (std::isnan(t)) return;
  char buf[40];
  if (h >= 0) snprintf(buf, sizeof buf, "室温 %.1f℃  %d%%", t, h);
  else snprintf(buf, sizeof buf, "室温 %.1f℃", t);
  text(buf, y, 16, C_SUB);
}

static void drawHome() {
  // 時計
  time_t now = time(nullptr);
  struct tm tm;
  localtime_r(&now, &tm);
  char hm[8];
  strftime(hm, sizeof hm, "%H:%M", &tm);
  canvas.setFont(&fonts::Font4);
  canvas.setTextDatum(middle_center);
  canvas.setTextColor(C_SUB);
  canvas.drawString(hm, 120, 34);

  if (pages.empty()) {
    text("リモコンが", 105, 20, C_TEXT);
    text("ありません", 135, 20, C_TEXT);
    return;
  }
  const Page& p = pages[cur];
  uint32_t col = pageColor(p);
  canvas.fillSmoothCircle(120, 102, 40, col);
  canvas.setTextColor(C_BG);
  canvas.setFont(jp(16));
  canvas.drawString(rc::kindLabel(p.kind), 120, 102);
  text(pageName(p), 165, 24, C_TEXT, 190);
  roomLine(194);

  // 位置の点（下の縁に沿って）
  int n = pages.size();
  float span = std::min(80.0f, 10.0f * (n - 1));
  for (int i = 0; i < n; i++) {
    float a = (90 + span / 2 - (n > 1 ? span * i / (n - 1) : 0)) * M_PI / 180;
    int x = 120 + cosf(a) * 108, y = 120 + sinf(a) * 108;
    canvas.fillSmoothCircle(x, y, i == cur ? 4 : 2, i == cur ? col : C_OFF);
  }
}

static void drawAirCon(const Page& p) {
  const rc::AcState& s = p.ac;
  uint32_t col = s.power ? acModeColor(s.mode) : C_OFF;
  // 温度のリング（左下 135° から右下 405° まで）
  float frac = float(s.temp - rc::AcState::kMinTemp) / (rc::AcState::kMaxTemp - rc::AcState::kMinTemp);
  canvas.fillArc(120, 120, 108, 118, 135, 405, C_TRACK);
  canvas.fillArc(120, 120, 108, 118, 135, 135 + 270 * frac, col);

  // タップの範囲に合わせて並べる: 上=モード / 真ん中=温度・電源 / 下=風量
  text(pageName(p), 36, 16, C_SUB, 116);  // リングの内側に収める
  text(rc::acModeLabel(s.mode), 58, 24, col);

  char t[4];
  snprintf(t, sizeof t, "%d", s.temp);
  canvas.setFont(&fonts::Font7);  // 7 セグ（エアコンのリモコン風）
  canvas.setTextSize(1.3);
  canvas.setTextDatum(middle_center);
  canvas.setTextColor(s.power ? C_TEXT : C_SUB);
  int tw = canvas.textWidth(t);
  canvas.drawString(t, 114, 106);
  canvas.setTextSize(1);
  canvas.setFont(jp(20));
  canvas.setTextDatum(top_left);
  canvas.drawString("℃", 114 + tw / 2 + 3, 80);
  canvas.setTextDatum(middle_center);
  text(s.power ? "● 運転中" : "○ 停止中", 146, 16, s.power ? col : C_SUB);

  char f[24];
  snprintf(f, sizeof f, "風量 %s", rc::acFanLabel(s.fan));
  text(f, 178, 20, C_TEXT);
  roomLine(206);
}

// 上・真ん中（電源）・下の 3 つのボタンがある画面（テレビ・照明など）
static void drawThreeButtons(const Page& p, const char* top, const char* bottom,
                             const char* dial, bool power, bool poweredKnown) {
  uint32_t col = pageColor(p);
  canvas.fillArc(120, 120, 112, 118, 0, 360, C_TRACK);
  text(pageName(p), 32, 16, C_SUB, 150);
  text(top, 62, 20, C_TEXT);
  uint32_t pc = poweredKnown ? (power ? col : C_OFF) : col;
  canvas.fillSmoothCircle(120, 120, 32, 0x15181C);
  powerIcon(120, 122, 16, pc);
  text(bottom, 176, 20, C_TEXT);
  char d[40];
  snprintf(d, sizeof d, "ダイヤル: %s", dial);
  text(d, 204, 16, C_SUB);
}

static void drawFan(const Page& p) {
  static const char* sp[] = {"", "弱", "中", "強"};
  uint32_t col = p.on ? kindColor(Kind::Fan) : C_OFF;
  canvas.fillArc(120, 120, 108, 118, 135, 405, C_TRACK);
  canvas.fillArc(120, 120, 108, 118, 135, 135 + 90 * p.fanSpeed, col);
  text(pageName(p), 32, 16, C_SUB, 150);
  text("首振り", 62, 20, C_TEXT);
  canvas.fillSmoothCircle(120, 108, 28, 0x15181C);
  powerIcon(120, 110, 14, col);
  char s[24];
  snprintf(s, sizeof s, "風量 %s", sp[p.fanSpeed]);
  text(s, 150, 16, C_SUB);
  text("タイマー", 182, 20, C_TEXT);
}

// my_layout.h で決めた 上・真ん中・下・ダイヤル の画面
static void drawCustom(const Page& p) {
  const rc::PageSpec& sp = p.spec;
  uint32_t col = pageColor(p);
  canvas.fillArc(120, 120, 112, 118, 0, 360, C_TRACK);
  text(pageName(p), 32, 16, C_SUB, 150);
  if (sp.top.valid) text(sp.top.label.c_str(), 62, 20, C_TEXT);
  if (sp.center.valid) {
    const auto& c = sp.center;
    bool power = (c.cmd.command == "turnOn" || c.cmd.command == "turnOff") && c.label == c.cmd.command;
    if (power) {
      canvas.fillSmoothCircle(120, 120, 32, 0x15181C);
      powerIcon(120, 122, 16, col);
    } else {
      canvas.fillSmoothCircle(120, 120, 36, col);
      text(c.label.c_str(), 120, 20, C_BG, 64);
    }
  }
  if (sp.bottom.valid) text(sp.bottom.label.c_str(), 176, 20, C_TEXT);
  if (sp.dialUp.valid || sp.dialDown.valid) {
    char d[48];
    snprintf(d, sizeof d, "ダイヤル: %s", sp.dialLabel.empty() ? "−／＋" : sp.dialLabel.c_str());
    text(d, 198, 16, C_SUB);
  }
  if (!p.items.empty()) text("長押しで一覧", 216, 12, C_OFF);
}

static void drawList(const Page& p) {
  text(pageName(p), 32, 16, C_SUB, 150);
  int n = p.items.size();
  if (n == 0) {
    text("ボタンがありません", 110, 16, C_TEXT);
    text("my_layout.h に書いてください", 136, 16, C_SUB);
    return;
  }
  uint32_t col = pageColor(p);
  // 上下に前後の項目、真ん中に選択中（ホイール風）
  for (int d = -1; d <= 1; d++) {
    if (n < 2 && d != 0) continue;
    const auto& it = p.items[rc::wrapIndex(p.sel + d, n)];
    int y = 124 + d * 46;
    if (d == 0) {
      canvas.fillSmoothRoundRect(22, y - 22, 196, 44, 22, col);
      text(it.label.c_str(), y, 24, C_BG, 176);
    } else {
      text(it.label.c_str(), y, 20, C_SUB, 170);
    }
  }
  char pos[16];
  snprintf(pos, sizeof pos, "%d / %d", p.sel + 1, n);
  canvas.setFont(&fonts::Font2);
  canvas.setTextColor(C_SUB);
  canvas.setTextDatum(middle_center);
  canvas.drawString(pos, 120, 222);
}

static void drawToast() {
  if (!toast.length() || millis() > toastUntil) return;
  canvas.setFont(jp(16));
  int w = std::min(200, (int)canvas.textWidth(toast.c_str()) + 28);
  canvas.fillSmoothRoundRect(120 - w / 2, 192, w, 28, 14, toastColor);
  canvas.setTextColor(C_TEXT);
  canvas.setTextDatum(middle_center);
  canvas.drawString(toast.c_str(), 120, 206);
}

static void render() {
  canvas.fillScreen(C_BG);
  if (screen == Screen::Home) {
    drawHome();
  } else {
    const Page& p = pages[cur];
    if (showsList(p)) drawList(p);
    else if (p.spec.custom) drawCustom(p);
    else switch (p.kind) {
      case Kind::AirCon: drawAirCon(p); break;
      case Kind::TV: drawThreeButtons(p, "チャンネル ＋", "チャンネル −", "音量", false, false); break;
      case Kind::Media: drawThreeButtons(p, "再生", "一時停止", "音量", false, false); break;
      case Kind::Light: drawThreeButtons(p, "全灯", "消灯", "明るさ", p.on, true); break;
      case Kind::Fan: drawFan(p); break;
      default: drawList(p);
    }
  }
  drawToast();
  canvas.pushSprite(0, 0);
}

static void message(const char* l1, const char* l2 = "", uint32_t color = C_TEXT) {
  canvas.fillScreen(C_BG);
  text(l1, 108, 20, color);
  text(l2, 138, 16, C_SUB);
  canvas.pushSprite(0, 0);
}

// ---------------------------------------------------------------- 操作

static void saveAc(const Page& p) { prefs.putUInt(acKey(pageId(p)).c_str(), p.ac.pack()); }

static void sendAc(Page& p, const char* why) {
  saveAc(p);
  char label[40];
  if (!p.ac.power) snprintf(label, sizeof label, "%s", why);
  else snprintf(label, sizeof label, "%s%s%s %d℃", why, *why ? " " : "", rc::acModeLabel(p.ac.mode), p.ac.temp);
  sendCmd({pageId(p), "setAll", p.ac.toParameter()}, label);
}

// 回したあと少し待ってから送る
static void schedule(int page) {
  pending.touch(millis());
  pendingPage = page;
}

static void flushPending() {
  if (pendingPage < 0 || !pending.due(millis())) return;
  Page& p = pages[pendingPage];
  pendingPage = -1;
  if (p.kind == Kind::AirCon) {
    if (p.ac.power) sendAc(p, "");
    else saveAc(p);  // 止まっているときは覚えるだけ（次に入れたときこの設定で動く）
  } else if (p.kind == Kind::Fan) {
    static const char* cmd[] = {"", "lowSpeed", "middleSpeed", "highSpeed"};
    sendCmd({pageId(p), cmd[p.fanSpeed]}, "");
  }
}

static void onDial(int clicks) {
  if (screen == Screen::Home) {
    cur = rc::wrapIndex(cur + clicks, pages.size());
    beep(3000, 5);
    return;
  }
  Page& p = pages[cur];
  if (showsList(p)) {
    p.sel = rc::wrapIndex(p.sel + clicks, p.items.size());
    beep(3000, 5);
    return;
  }
  if (p.spec.custom) {
    const rc::Action& a = clicks > 0 ? p.spec.dialUp : p.spec.dialDown;
    if (!a.valid) return;
    String label = String(p.spec.dialLabel.empty() ? a.label.c_str() : p.spec.dialLabel.c_str()) +
                   (clicks > 0 ? " ＋" : " −");
    for (int i = 0, n = std::min(5, std::abs(clicks)); i < n; i++) sendCmd(a.cmd, label);
    return;
  }
  const char* up = nullptr;
  const char* down = nullptr;
  switch (p.kind) {
    case Kind::AirCon:
      if (p.ac.addTemp(clicks)) schedule(cur);
      beep(3000, 5);
      return;
    case Kind::Fan: {
      int s = std::max(1, std::min(3, p.fanSpeed + (clicks > 0 ? 1 : -1)));
      if (s != p.fanSpeed) { p.fanSpeed = s; schedule(cur); }
      beep(3000, 5);
      return;
    }
    case Kind::TV:
    case Kind::Media: up = "volumeAdd"; down = "volumeSub"; break;
    case Kind::Light: up = "brightnessUp"; down = "brightnessDown"; break;
    default: return;
  }
  // 1 カチッ = 1 回送る（音量など）。回しすぎは 5 回まで
  int n = std::min(5, std::abs(clicks));
  for (int i = 0; i < n; i++) {
    bool isUp = clicks > 0;
    String label = p.kind == Kind::Light ? (isUp ? "明るく" : "暗く") : (isUp ? "音量 ＋" : "音量 −");
    sendCmd({pageId(p), isUp ? up : down}, label);
  }
}

static void onTap(Zone z) {
  if (screen == Screen::Home) {
    if (pages.empty()) return;
    screen = Screen::Device;
    beep();
    return;
  }
  Page& p = pages[cur];
  if (showsList(p)) {
    if (p.items.empty()) return;
    const auto& it = p.items[p.sel];
    sendCmd(it.cmd, it.label.c_str());
    return;
  }
  if (p.spec.custom) {
    const rc::Action& a = z == Zone::Top ? p.spec.top : z == Zone::Center ? p.spec.center : p.spec.bottom;
    if (a.valid) sendCmd(a.cmd, a.label.c_str());
    return;
  }
  const std::string& id = pageId(p);
  switch (p.kind) {
    case Kind::AirCon:
      if (z == Zone::Center) {
        p.ac.power = !p.ac.power;
        pending.cancel();
        pendingPage = -1;
        sendAc(p, p.ac.power ? "運転" : "停止");
      } else {
        if (z == Zone::Top) p.ac.nextMode(); else p.ac.nextFan();
        schedule(cur);
        beep(3000, 5);
      }
      break;
    case Kind::TV:
      if (z == Zone::Top) sendCmd({id, "channelAdd"}, "チャンネル ＋");
      else if (z == Zone::Bottom) sendCmd({id, "channelSub"}, "チャンネル −");
      else sendCmd({id, "turnOn"}, "電源");
      break;
    case Kind::Media:
      if (z == Zone::Top) sendCmd({id, "Play"}, "再生");
      else if (z == Zone::Bottom) sendCmd({id, "Pause"}, "一時停止");
      else sendCmd({id, "turnOn"}, "電源");
      break;
    case Kind::Light:
      if (z == Zone::Top) p.on = true;
      else if (z == Zone::Bottom) p.on = false;
      else p.on = !p.on;
      sendCmd({id, p.on ? "turnOn" : "turnOff"}, p.on ? "点灯" : "消灯");
      break;
    case Kind::Fan:
      if (z == Zone::Top) sendCmd({id, "swing"}, "首振り");
      else if (z == Zone::Bottom) sendCmd({id, "timer"}, "タイマー");
      else {
        p.on = !p.on;
        sendCmd({id, p.on ? "turnOn" : "turnOff"}, p.on ? "運転" : "停止");
      }
      break;
    default: break;
  }
}

static void onLongPress() {
  if (screen != Screen::Device) return;
  Page& p = pages[cur];
  if (!p.spec.custom && (p.kind == Kind::Generic || p.kind == Kind::Scenes)) return;
  if (p.items.empty()) return;
  p.list = !p.list;
  p.sel = 0;
  beep(2000, 30);
}

static void onBack() {
  if (screen != Screen::Device) {
    onTap(Zone::Center);
    return;
  }
  Page& p = pages[cur];
  if (p.list) p.list = false;
  else screen = Screen::Home;
  beep(2500, 10);
}

static void onFlick(int dx) {
  if (screen != Screen::Device || pages.size() < 2) return;
  pages[cur].list = false;
  cur = rc::wrapIndex(cur + (dx < 0 ? 1 : -1), pages.size());
  beep(3000, 5);
}

// ---------------------------------------------------------------- 起動

static void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  for (;;) {
    message("Wi-Fi 接続中…", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) delay(500);
    if (WiFi.status() == WL_CONNECTED) return;
    message("Wi-Fi につながりません", "SSID・パスワード・2.4GHz を確認", C_ERR);
    WiFi.disconnect();
    delay(10000);
  }
}

static void syncClock() {
  // SwitchBot の署名に正しい時刻が要る
  configTzTime(TIMEZONE, "ntp.nict.jp", "pool.ntp.org", "time.google.com");
  message("時刻を合わせています…");
  for (int i = 0; i < 40 && time(nullptr) < 1700000000; i++) delay(250);
}

static void loadDevices() {
  for (;;) {
    message("SwitchBot から", "リモコン一覧を読み込み中…");
    ApiResult r = api.listDevices(remotes, sensorId);
    if (r.ok) break;
    Serial.printf("listDevices: http=%d status=%d %s\n", r.httpCode, r.statusCode, r.message.c_str());
    message("読み込めませんでした", r.message.c_str(), C_ERR);
    delay(15000);
  }
  api.listScenes(scenes);  // 失敗してもシーンが出ないだけ
  Serial.printf("remotes=%u scenes=%u sensor=%s\n", (unsigned)remotes.size(),
                (unsigned)scenes.size(), sensorId.c_str());
  buildPages();
  if (!layoutErrors.empty()) {  // 書き間違いは起動時に知らせる（その部分だけ飛ばして動く）
    char n[40];
    snprintf(n, sizeof n, "my_layout.h に %u か所の誤り", (unsigned)layoutErrors.size());
    message(n, layoutErrors[0].c_str(), C_ERR);
    delay(5000);
  }
}

void setup() {
  auto cfg = M5.config();
  M5Dial.begin(cfg, true, false);
  Serial.begin(115200);
  M5Dial.Display.setBrightness(BRIGHTNESS);
  canvas.setColorDepth(16);
  canvas.createSprite(240, 240);
  M5Dial.Speaker.setVolume(80);
  prefs.begin("remote", false);

  connectWifi();
  syncClock();
  loadDevices();

  jobQ = xQueueCreate(16, sizeof(Job*));
  resQ = xQueueCreate(8, sizeof(JobResult));
  xTaskCreatePinnedToCore(worker, "switchbot", 12288, nullptr, 1, nullptr, 0);

  idle.activity(millis());
  dirty = true;
}

static int32_t lastEnc = 0;
static uint32_t lastClockDraw = 0;

void loop() {
  M5Dial.update();
  uint32_t now = millis();

  // ---- 入力を集める
  int clicks = 0;
  int32_t enc = M5Dial.Encoder.read();
  if (std::abs(enc - lastEnc) >= ENCODER_STEPS_PER_CLICK) {
    clicks = (enc - lastEnc) / ENCODER_STEPS_PER_CLICK;
    lastEnc += clicks * ENCODER_STEPS_PER_CLICK;
    clicks *= ENCODER_DIRECTION;
  }
  auto t = M5Dial.Touch.getDetail();
  bool tap = t.wasClicked(), hold = t.wasHold(), flick = t.wasFlicked() && std::abs(t.distanceX()) > 40;
  bool btn = M5Dial.BtnA.wasClicked(), btnHold = M5Dial.BtnA.wasHold();
  bool any = clicks || tap || hold || flick || btn || btnHold || t.wasPressed() || M5Dial.BtnA.wasPressed();

  // 消えている画面を起こした操作は、指を離すまで操作として扱わない
  static bool swallow = false;
  if (any && idle.activity(now)) {
    swallow = true;
    dirty = true;
  }
  if (swallow) {
    clicks = 0;
    tap = hold = flick = btn = btnHold = false;
    if (!t.isPressed() && !M5Dial.BtnA.isPressed()) swallow = false;
  }

  // ---- 操作
  if (!pages.empty()) {
    if (clicks) { onDial(clicks); dirty = true; }
    if (tap) { onTap(rc::zoneOf(t.y)); dirty = true; }
    if (hold) { onLongPress(); dirty = true; }
    if (flick) { onFlick(t.distanceX()); dirty = true; }
    if (btn) { onBack(); dirty = true; }
  }
  if (btnHold && screen == Screen::Home) {
    message("再読み込みします…");
    delay(500);
    ESP.restart();
  }
  flushPending();

  // ---- 送信結果
  JobResult r;
  while (xQueueReceive(resQ, &r, 0) == pdTRUE) {
    if (!r.ok) {
      showToast(r.msg, C_ERR, 3000);
      beep(800, 120);
    }
  }

  // ---- 画面の明るさ
  rc::Backlight b = idle.state(now);
  if (b != backlight) {
    if (b == rc::Backlight::Off) M5Dial.Display.sleep();
    else {
      if (backlight == rc::Backlight::Off) M5Dial.Display.wakeup();
      M5Dial.Display.setBrightness(b == rc::Backlight::Dim ? BRIGHTNESS / 6 : BRIGHTNESS);
    }
    backlight = b;
    dirty = true;
  }

  // ---- 描画（変化があったとき、トーストが消えるとき、時計・室温の更新）
  if (toast.length() && now > toastUntil) { toast = ""; dirty = true; }
  if (now - lastClockDraw > 10000) { lastClockDraw = now; dirty = true; }
  if (dirty && backlight != rc::Backlight::Off) {
    render();
    dirty = false;
  }
  delay(10);
}
