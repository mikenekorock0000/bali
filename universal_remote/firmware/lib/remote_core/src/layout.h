// 画面の並び・ボタンの名前と配置を JSON（include/layout.h）で決める。
//
// 例:
// {
//   "pages": [
//     {"remote": "リビングのエアコン"},
//     {"remote": "スピーカー", "title": "オーディオ", "color": "#ff6b81",
//      "dial":   {"label": "音量", "up": {"cmd": "volumeAdd"}, "down": {"cmd": "volumeSub"}},
//      "top":    {"label": "入力", "btn": "入力切替"},
//      "center": {"label": "電源", "cmd": "turnOn"},
//      "bottom": {"label": "ミュート", "cmd": "setMute"},
//      "list":   [{"label": "Bluetooth", "btn": "BT"}, {"label": "低音＋", "btn": "BASS+"}]},
//     {"title": "おでかけ", "center": {"label": "全部OFF", "scene": "外出"}},
//     {"scenes": true}
//   ]
// }
//
// ボタン 1 つ（アクション）の書き方:
//   {"cmd": "turnOn"}          SwitchBot の標準コマンド（volumeAdd・setMute・channelAdd など）
//   {"btn": "入力切替"}         アプリでリモコンに追加した学習ボタン（名前はアプリと同じに）
//   {"scene": "おやすみ"}       シーンを実行
//   "label"  画面に出す名前（省略するとボタン名）
//   "remote" 別のリモコンに送る（省略するとそのページのリモコン）
//   "param"  コマンドの引数（setAll・SetChannel など。省略時 "default"）
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "remote_core.h"

namespace rc {

struct DeviceRef {  // SwitchBot から読んだリモコン・シーン
  std::string id;
  std::string name;
  std::string type;  // リモコンの remoteType（シーンは空）
};

struct Action {
  bool valid = false;
  std::string label;
  Command cmd;
};

struct PageSpec {
  int remote = -1;        // remotes の添字（無ければ -1）
  bool scenes = false;    // シーン一覧ページ
  std::string title;      // 空ならリモコン名
  bool hasColor = false;
  uint32_t color = 0;     // 0xRRGGBB
  bool custom = false;    // dial/top/center/bottom のどれかがある → 自由配置の画面
  std::string dialLabel;
  Action dialUp, dialDown, top, center, bottom;
  bool hasList = false;   // "list" を書いた（空でも「一覧なし」として扱う）
  std::vector<ListItem> list;
};

struct LayoutResult {
  bool usePages = false;  // "pages" があった（無ければ今まで通り全部自動）
  std::vector<PageSpec> pages;
  std::vector<std::string> errors;  // 見つからない名前など（そのボタン・ページだけ飛ばす）
};

LayoutResult parseLayout(const char* json, const std::vector<DeviceRef>& remotes,
                         const std::vector<DeviceRef>& scenes);

bool parseColor(const std::string& s, uint32_t& out);

}  // namespace rc
