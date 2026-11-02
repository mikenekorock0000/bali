// リモコンの「中身」— 画面や通信に依存しない部分。PC 上でテストできる（test/test_core）。
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace rc {

// ---------------------------------------------------------------- 機器の種類

// 画面の作りで分ける。SwitchBot の remoteType から決める。
enum class Kind {
  AirCon,   // 温度・モード・風量（エアコン）
  TV,       // 音量・チャンネル（テレビ・ストリーミング・セットトップボックス）
  Media,    // 音量・再生（スピーカー・DVD）
  Light,    // 明るさ・ON/OFF（照明）
  Fan,      // 風量・首振り（扇風機）
  Generic,  // ボタン一覧（DIY・その他・プロジェクターなど）
  Scenes,   // SwitchBot のシーン一覧（機器ではない）
};

Kind kindFromRemoteType(const std::string& remoteType);
const char* kindLabel(Kind k);  // 画面に出す日本語（"エアコン" など）

// ---------------------------------------------------------------- エアコン

// 赤外線は一方通行なので、エアコンの状態はリモコン側で覚えておく（本物のリモコンと同じ）。
struct AcState {
  static constexpr int kMinTemp = 16;
  static constexpr int kMaxTemp = 30;

  int temp = 26;
  int mode = 2;  // SwitchBot の値: 1 自動 / 2 冷房 / 3 除湿 / 4 送風 / 5 暖房
  int fan = 1;   // 1 自動 / 2 弱 / 3 中 / 4 強
  bool power = false;

  // 温度を delta 度変える。範囲外は端で止まる。変わったら true。
  bool addTemp(int delta);
  void nextMode();
  void nextFan();
  // setAll コマンドの parameter（例 "26,2,1,on"）
  std::string toParameter() const;
  // NVS に 1 つの整数で保存するため
  uint32_t pack() const;
  static AcState unpack(uint32_t v);
};

const char* acModeLabel(int mode);  // "冷房" など
const char* acFanLabel(int fan);    // "自動" など

// ---------------------------------------------------------------- 送るもの

struct Command {
  std::string deviceId;  // シーンのときは sceneId
  std::string command;   // "turnOn" / "setAll" / ボタン名（customize）
  std::string parameter = "default";
  bool customize = false;  // 学習ボタン（アプリで付けた名前）
  bool scene = false;      // シーン実行（POST /scenes/{id}/execute）
};

// POST /devices/{id}/commands に送る JSON
std::string commandJson(const Command& c);
std::string jsonEscape(const std::string& s);

// ボタン一覧画面の 1 行
struct ListItem {
  std::string label;
  Command cmd;
};

// Generic 画面に並べるボタン。電源 ON/OFF（「その他」以外）＋ config.h で書いた学習ボタン。
std::vector<ListItem> genericItems(const std::string& deviceId, const std::string& remoteType,
                                   const std::vector<std::string>& customButtons);

// ---------------------------------------------------------------- 入力の間引き

// ダイヤルを回している間は送らず、止めて少し経ってから 1 回だけ送る（エアコンの温度など）。
class Debouncer {
 public:
  explicit Debouncer(uint32_t waitMs) : wait_(waitMs) {}
  void touch(uint32_t now) { last_ = now; pending_ = true; }
  // 送るタイミングなら true を返して保留を消す
  bool due(uint32_t now) {
    if (pending_ && now - last_ >= wait_) { pending_ = false; return true; }
    return false;
  }
  bool pending() const { return pending_; }
  void cancel() { pending_ = false; }

 private:
  uint32_t wait_;
  uint32_t last_ = 0;
  bool pending_ = false;
};

// ---------------------------------------------------------------- 画面の消灯

enum class Backlight { On, Dim, Off };

class IdleTimer {
 public:
  IdleTimer(uint32_t dimMs, uint32_t offMs) : dim_(dimMs), off_(offMs) {}
  // 操作があったとき。消灯中だったら true（＝その操作は「起こす」だけに使う）
  bool activity(uint32_t now) {
    bool wasOff = state(now) == Backlight::Off;
    last_ = now;
    return wasOff;
  }
  Backlight state(uint32_t now) const {
    uint32_t idle = now - last_;
    if (idle >= off_) return Backlight::Off;
    if (idle >= dim_) return Backlight::Dim;
    return Backlight::On;
  }

 private:
  uint32_t dim_, off_;
  uint32_t last_ = 0;
};

// 丸い画面のどこを触ったか（上・真ん中・下）。y は 0〜239。
enum class Zone { Top, Center, Bottom };
inline Zone zoneOf(int y) { return y < 80 ? Zone::Top : (y < 160 ? Zone::Center : Zone::Bottom); }

// 一覧の選択位置を回す（端でループ）
inline int wrapIndex(int i, int n) { return n <= 0 ? 0 : ((i % n) + n) % n; }

}  // namespace rc
