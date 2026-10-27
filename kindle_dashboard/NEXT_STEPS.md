# このあとやること（Kindle ダッシュボード）

最終更新: 2026-10-26 ／ ブランチ: `kindle-dashboard`（`main` には未マージ・PR 未作成）

## 現状

| 項目 | 状態 |
|---|---|
| 調査・脱獄手順 | ✅ `docs/kindle-dashboard/`（端末は **Kindle Paperwhite 第7世代・FW 5.16.2.1.1** → [paperwhite3.md](../docs/kindle-dashboard/paperwhite3.md)） |
| ファームウェア | ✅ **5.16.2.1.1** を確認済み（PW3 の最終版。2026-10-26 に自動アップデート）。WinterBreak・LanguageBreak とも対応範囲内 |
| サーバー（画像生成・配信） | ✅ 実装済み。単体テスト 105 件成功、Docker イメージのビルド・起動を確認 |
| Kindle 側スクリプト（Scriptlets で起動） | ✅ 実装済み。PC 上でコマンドを模擬して動作確認 |
| 配布ファイル | ✅ `dist/kindle-dashboard-nas.zip`・`dist/kindle-dashboard-kindle.zip`、手順は [NAS_SETUP.md](NAS_SETUP.md) |
| 実データの取得 | ⚠️ **未確認**（開発環境から外部 API に繋がらなかった） |
| 脱獄 | ✅ WinterBreak2 完了（2026-10-27）。`libkh/bin/fbink`・`JAILBROKEN.txt` あり。**Hotfix・KUAL は不要**（新しい脱獄では KPM/Scriptlets。Universal Hotfix は PW3 5.16.2.1.1 で不具合報告あり・入れない） |
| Kindle 実機での表示 | ⚠️ **未確認** |

## やること（順番に）

### ステップ 1. NAS でサーバーを動かす（30 分）

1. `dist/kindle-dashboard-nas.zip` を展開して NAS へ置く（[NAS_SETUP.md](NAS_SETUP.md) の 1）。
2. `config/config.json` の `location` に自宅の緯度・経度。
3. 必要なら `.env`（Google カレンダーの非公開 URL、SwitchBot）。
4. 起動（Container Manager のプロジェクト、または `docker compose up -d --build`）。
5. **確認**: PC のブラウザで
   - `http://<NASのIP>:8080/preview.png` … 画面が出るか
   - `http://<NASのIP>:8080/health` … 各項目が `"ok": true` か
6. NAS の IP をルーターで固定。

✅ 完了の目安: `/health` が全部 `true`、`preview.png` に実際の天気・市況・ニュースが出ている。

### ステップ 2. Kindle を脱獄する（1〜2 時間）— WinterBreak まで完了

手順: [paperwhite3.md](../docs/kindle-dashboard/paperwhite3.md)

1. **50% 以上まで充電**、**機内モード ON**（ファームウェアが上がらないように）。
2. [Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html) で機種・FW を入れて方法を確認。
3. WinterBreak2 で脱獄 ✅
4. ~~Hotfix → KUAL/MRPI~~ → **不要**（KindleModding 公式: 新しい脱獄では KUAL は廃止。Universal Hotfix は入れない）。
5. ルートに残った `.bin` ファイル・詰め物ファイルがあれば削除（自動アップデートは脱獄で止まっている）。

✅ 完了の目安: ライブラリに「JAILBROKEN」がある（済）。

### ステップ 3. Kindle にダッシュボードを入れる（15 分）

1. `dist/kindle-dashboard-kindle.zip` を展開し、`dashboard` を Kindle のルートへ、`documents` の 3 つの `.sh` を Kindle の `documents` へ。
2. Kindle の `dashboard/config.sh` の `SERVER_URL="http://<NASのIP>:8080/dash.png"`（LF 改行のまま保存）。
3. 機内モード OFF → ライブラリの **Dashboard テスト** を開く → 画像が出るか。
4. 出たら **Dashboard 開始**。電源ボタン（または Dashboard 停止）で終了できるか確認。

✅ 完了の目安: 毎分時計が進み、15 回に 1 回画面全体が書き換わる。

### ステップ 4. 実機で調整する

実機を見て気になるところを直す。よくありそうなもの:

| 症状 | 対処 |
|---|---|
| 上下逆さま | サーバーの `config.json` → `"display": {"rotate": 270}` |
| Kindle の画面（メニュー等）が上書きしてくる | Kindle の `config.sh` → `STOP_MODE=stop` |
| 電源ボタンで終了しない | 再起動（電源ボタン 40 秒長押し）で元に戻る。報告して直す |
| 開始してもライブラリの画面のまま／上書きされる | `config.sh` の `START_DELAY` を 10 に、それでもダメなら `STOP_MODE=stop` |
| 文字が細い・薄い（月カレンダーの予定、服の線など） | 文字サイズ・線の太さを上げる（`server/dashboard/render.py`） |
| 残像が気になる | `config.sh` の `FULL_REFRESH_EVERY` を小さく（例 5） |
| 「offline」と出る | Wi-Fi・`SERVER_URL`・NAS のポート/ファイアウォールを確認 |

### ステップ 5. 仕上げ（任意）

- `main` へのマージ（PR を作る）。
- Kindle の起動時に自動でダッシュボードを始める（今はライブラリの Dashboard 開始から手動）。
- 室内センサー（SwitchBot CO2 センサー）を買ったら `.env` と `config.json` の `indoor` を設定。

## 次のセッションに伝えること（報告テンプレート）

うまくいかないときは、これを貼れば続きから直せる:

```
・どのステップか: （例 ステップ1の確認）
・/health の結果: （ok:false の項目と error の文）
・Kindle の画面の写真 / Kindle の dashboard/dashboard.log の中身
・やったこと / 起きたこと:
```

## 確認できていないこと（要注意ポイント）

| 項目 | 心配な点 | 確認方法 |
|---|---|---|
| Open-Meteo（天気） | 応答の形は仕様どおりのはず | `/health` の `weather` |
| Yahoo Finance（ドル円） | **非公式 API**。User-Agent 制限などで弾かれる可能性 | `/health` の `market0` |
| 三菱UFJアセット API（eMAXIS Slim S&P500） | 応答形式は公開事例から推定 | `/health` の `market1` |
| 投資信託協会 CSV（FANG+） | URL 形式・CSV の列は公開事例から推定 | `/health` の `market2` |
| NHK RSS | URL（`cat0.xml`）が変わっている可能性 | `/health` の `news`。変わっていたら `config.json` の `news.url` |
| Google カレンダー | 非公開 URL の読み込み・繰り返し予定 | 3〜9 時に表示 or `/health` の `calendar` |
| Kindle 側 | `STOP_MODE=pause`（cvm 一時停止）で画面を確保できるか、電源ボタン検知、FBInk のパス | 実機で Test / Start |

## 開発メモ（コードを触る人向け）

```
kindle_dashboard/
  server/                  Python + Pillow。NAS の Docker で動く
    serve.py               起動（serve）／1 枚描画（render --demo --at 07:30）
    dashboard/
      app.py               設定の既定値・データ源の登録・HTTP（/dash.png /preview.png /health）
      sources.py           天気・市況（yahoo/mufg/toushin）・ニュース・SwitchBot
      clothing.py          服装指数（しきい値・文言はここ）
      gcal.py              Google カレンダー（iCal）・月グリッド・祝日
      render.py            レイアウト（論理 1024x758 → 画面サイズに拡大）
      icons.py             天気・服・傘などの線画
      store.py             取得間隔・失敗時は前回値
      demo.py              ダミーデータ
    tests/                 pytest
  kindle/dashboard/        Kindle 側の本体（/mnt/us/dashboard。BusyBox sh）
  kindle/documents/        Scriptlets（ライブラリに出る 開始・停止・テスト）
  tool/package.py          dist/ の zip を作る
```

よく使うコマンド（`kindle_dashboard/server` で）:

```bash
pip install -r requirements.txt pytest && python fetch_fonts.py   # 初回
python -m pytest -q tests                                        # テスト
python serve.py render --demo                 # out/preview.png でデザイン確認（通信なし）
python serve.py render --demo --at 07:30      # 時刻指定（3〜9 時は月カレンダー）
python serve.py render                        # 実データで 1 枚（取得結果を表示）
python serve.py                               # 配信 http://<IP>:8080/dash.png
python ../tool/package.py                     # 配布 zip を作り直す（リポジトリのルートからでも可）
```

決めたこと:

- 端末: Kindle Paperwhite 第7世代（1072×1448）。画像は横 1448×1072 で描き、時計回り 90° 回転して配信。
- 時計フォント: DM Serif Display（`config.json` の `clock` で変更可）。
- 市況: ドル円（Yahoo）／eMAXIS Slim 米国株式 S&P500（三菱UFJアセット API）／iFreeNEXT FANG+（投信協会 CSV）。
- 服装指数: tenki.jp を参考にした独自計算（体感温度ベース）。雨の日は大きな傘。
- 3:00〜9:00 はニュース欄を Google カレンダーの月表示に。
- 時計は Kindle が毎分取りに来るたびにサーバーがその時刻で描く（常時給電前提）。
