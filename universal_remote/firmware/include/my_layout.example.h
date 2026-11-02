// 画面の並び・ボタンの名前と配置。my_layout.h という名前でコピーして書き換える（無ければ全部自動）。
//   cp include/my_layout.example.h include/my_layout.h
// tool/remote_setup.py を使うと、登録済みのリモコンを並べたひな形を作れる。
//
// ■ ページ（"pages" に並べた順にダイヤルで回る。書かなかったリモコンは出てこない）
//   {"remote": "アプリでのリモコン名"}   … いつもの画面（エアコン・テレビなど種類ごと）
//   {"scenes": true}                       … シーン一覧
//   "title"  画面に出す名前（省略するとリモコン名）
//   "color"  色 "#RRGGBB"
//
// ■ 自由配置（書いた所だけ使われる。1 つでも書くとその画面は自由配置になる）
//   "top"    画面の上をタップ      "center" 真ん中をタップ      "bottom" 下をタップ
//   "dial"   {"label": "音量", "up": 右に回したとき, "down": 左に回したとき}
//   "list"   [ボタン, ボタン, …]   … 長押しで出る一覧（DIY・その他のリモコンはこれがメイン画面）
//
// ■ ボタン 1 つの書き方
//   {"label": "入力", "btn": "入力切替"}   アプリでリモコンに追加した学習ボタン（名前はアプリと 1 文字も違わずに）
//   {"label": "電源", "cmd": "turnOn"}      標準コマンド（下の表）
//   {"label": "寝る", "scene": "おやすみ"}  シーンを実行
//   "remote": "テレビ"  を足すと、別のリモコンに送れる（1 ページで 2 台を操作するなど）
//   "param": "1"        コマンドの引数（SetChannel のチャンネル番号など）
//   label を省くとボタン名がそのまま出る。center を {"cmd": "turnOn"} だけにすると電源マークになる。
//
// ■ 標準コマンド（リモコンの種類ごとに使えるもの。SwitchBot API v1.1）
//   共通（その他 以外）: turnOn / turnOff
//   テレビ・ストリーミング・セットトップボックス: volumeAdd / volumeSub / channelAdd / channelSub / SetChannel(param=番号)
//   スピーカー・DVD: volumeAdd / volumeSub / setMute / Play / Pause / Stop / Next / Previous / FastForward / Rewind
//   照明: brightnessUp / brightnessDown
//   扇風機: swing / timer / lowSpeed / middleSpeed / highSpeed
//   それ以外のボタン（入力切替・BASS など）は btn で学習ボタンとして送る。
//
// 書き間違い（名前が見つからない等）は起動時に赤字で知らせて、その部分だけ飛ばして動く。
#pragma once

static const char LAYOUT_JSON[] = R"json(
{
  "pages": [
    {"remote": "リビングのエアコン"},
    {"remote": "テレビ",
     "list": [{"btn": "入力切替"}, {"label": "NHK", "cmd": "SetChannel", "param": "1"}]},
    {"remote": "スピーカー", "color": "#ff6b81",
     "dial":   {"label": "音量", "up": {"cmd": "volumeAdd"}, "down": {"cmd": "volumeSub"}},
     "top":    {"label": "入力", "btn": "入力切替"},
     "center": {"cmd": "turnOn"},
     "bottom": {"label": "ミュート", "cmd": "setMute"},
     "list":   [{"label": "Bluetooth", "btn": "BT"}, {"label": "低音 ＋", "btn": "BASS+"},
                {"label": "低音 −", "btn": "BASS-"}]},
    {"title": "映画", "color": "#e056fd",
     "top":    {"label": "テレビ電源", "remote": "テレビ", "cmd": "turnOn"},
     "center": {"label": "映画モード", "scene": "映画モード"},
     "bottom": {"label": "スピーカー", "remote": "スピーカー", "cmd": "turnOn"},
     "dial":   {"label": "音量", "up": {"remote": "スピーカー", "cmd": "volumeAdd"},
                                 "down": {"remote": "スピーカー", "cmd": "volumeSub"}}},
    {"remote": "リビングの照明"},
    {"scenes": true}
  ]
}
)json";
