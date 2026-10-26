# 古い Kindle で E-ink ダッシュボードを作る — 調査まとめ・手順書

> 調査日: 2026-10-26。脱獄ツールの対応ファームウェアは頻繁に変わるため、**作業前に必ず [Kindle Modding Wiki (kindlemodding.org)](https://kindlemodding.org/jailbreaking/) の最新情報を確認すること**。
>
> ⚠️ 脱獄は自己責任。メーカー保証の対象外になり、最悪の場合は文鎮化（起動不能）する。Amazon の利用規約にも反しうる。

目標イメージ（添付写真）: 日付・時刻 / 屋外の天気（現在・3時間ごと・3日間）/ 室内の温湿度・CO2 / 為替・株価 / NHK ニュース / Kindle 電池残量を 1 画面に表示する。

---

## 0. 全体像（みんなどうやっているか）

調べた事例はほぼすべて同じ構成になっている。

```
┌─────────── サーバー（PC / Raspberry Pi / NAS / GitHub Actions 等）──────────┐
│ 1. 各種 API からデータ取得（天気・株価・ニュース・室内センサー）           │
│ 2. HTML などでレイアウト → ヘッドレス Chrome でスクリーンショット         │
│ 3. Kindle の解像度に合わせた「グレースケール PNG」に変換して HTTP 配信      │
└──────────────────────────────┬───────────────────────────────────────────────┘
                               │ Wi-Fi で定期的に取得
┌──────────── 脱獄した Kindle ─┴───────────────────────────────────────────────┐
│ シェルスクリプトが「画像をダウンロード → eips / FBInk で画面に貼る」を繰り返す │
│ （スリープ・スクリーンセーバーを止める or RTC で起こす）                     │
└──────────────────────────────────────────────────────────────────────────────┘
```

**ポイント: Kindle 側では描画しない。** Kindle のブラウザは古く（2009年頃の WebKit 相当）、日本語フォント描画も弱いので、重い処理と見た目はすべてサーバーで作り、Kindle は「画像を表示するだけの端末」にする。これが一番安定し、電池も持つ。

やり方は大きく 4 通り。

| 方式 | 脱獄 | 難易度 | 向いている人 |
|---|---|---|---|
| **A. 自作スクリプト（kindle-dash 系）** ← 本命 | 必要 | 中 | 写真のような自由なレイアウトを作りたい |
| B. TRMNL (KOReader プラグイン / KUAL 拡張) | 必要 | 低〜中 | 既製のプラグイン群で手早く済ませたい |
| C. Home Assistant + Online Screensaver | 必要 | 中 | すでに Home Assistant を使っている |
| D. 実験的ブラウザで HTML を開きっぱなし | 不要 | 低 | 脱獄できない機種・FW。ただし不安定 |

写真のダッシュボードは **A 方式**（サーバーで PNG を作る＋Kindle は表示だけ）で作るのが妥当。

---

## 1. 準備するもの

- 古い Kindle（Paperwhite 3 以降が解像度的におすすめ）＋ USB ケーブル
- 常時給電用の USB 充電器（毎分時計を更新するなら**給電しっぱなし前提**）
- スタンド（写真のように横置きするなら画像を 90° 回転して配信する）
- サーバー役: 常時起動の PC / Raspberry Pi / 自宅 NAS / もしくは GitHub Actions + GitHub Pages
- 2.4GHz の Wi-Fi（古い Kindle は 5GHz・WPA3 非対応のことが多い）
- 室内センサーを出すなら: SwitchBot CO2 センサー等（API で値が取れるもの）

### 機種と画面解像度（PNG はこのサイズで作る）

| 機種 | 解像度（縦置き） |
|---|---|
| Kindle 4/5, Kindle Touch, Kindle 7/8/10 (無印) | 600 × 800 |
| Paperwhite 1/2 | 758 × 1024 |
| Paperwhite 3/4, Voyage, Oasis 1, Kindle 11 (2022) | 1072 × 1448 |
| Oasis 2/3 | 1264 × 1680 |
| Paperwhite 5 (11世代) | 1236 × 1648 |

※ 実機で `eips -i` や FBInk の情報表示で確認するのが確実。

---

## 2. 脱獄（Jailbreak）

### 2-1. まずファームウェアを確認

Kindle: 設定 → すべての設定 → 端末オプション → 端末情報 →「ファームウェアのバージョン」。
**末尾の枝番（例: `5.18.1.1.1`）まで控える。** どの脱獄が使えるかは機種 × バージョンで決まる。

> **ここから先、Wi-Fi に繋ぎっぱなしにしない。** 自動アップデートで脱獄できないバージョンに上がると詰む。作業中は基本 **機内モード ON**。

### 2-2. どの脱獄ツールを使うか（2026年10月時点の調査結果）

| ファームウェア | ツール | 条件・備考 |
|---|---|---|
| 〜 5.18.0.x | **WinterBreak**（Mesquito ベース） | 2025年1月公開。第12世代(2024)まで対応。5.18.1 で塞がれた |
| 5.18.1 〜 5.18.5.0.1 | **AdBreak** | **広告付き（キャンペーン情報つき）モデル**かつ登録済みのみ。Scribe / Colorsoft 非対応 |
| KT4 / PW4 の 5.18.1.1.1、KT5 / PW5(SE) の 5.19.2+ | **SpringBreak**（WinterBreak3） | 対応機種が限定的 |
| もっと古い FW (5.x 初期〜5.16 付近) | 旧来の脱獄（各機種別、kindlemodding の Legacy ページ参照） | 古い Kindle は大抵こちらで可能 |
| それ以外の最新 FW | **現状不可の可能性大** | → 方式 D（脱獄なし）を検討 |

※ 二次情報サイト同士で対応範囲が食い違っている（特に Nosebleed / SpringBreak）。**一次情報（kindlemodding.org と各 GitHub リポジトリ）を正とする。**

### 2-3. WinterBreak の手順（代表例）

1. [WinterBreak.tar.gz](https://github.com/KindleModding/WinterBreak/releases/latest/download/WinterBreak.tar.gz) をダウンロードして PC で展開。
2. Kindle を **機内モード ON** → 設定 → 端末オプション → **再起動**。
3. 再起動後 USB で PC に接続し、展開したファイルを**すべて Kindle のルートにコピー**（上書き可）。
   - Mac/Linux は隠しフォルダ **`.active_content_sandbox`** もコピーされているか確認（Finder では見えないのでターミナルで `store` フォルダをコピー）。
   - Mac で Kindle が見えない場合は Amazon の「ConnectMyKindle」アプリの USB File Manager を使う。
4. 取り外し（Kindle 画面で「切断」）→ **Kindle ストア（カートのアイコン）を開く**。機内モード解除を促されたら解除。
5. ストアが再読み込みされると **WinterBreak のアイコン**が出るのでタップ。
   - 出ない場合: 工場出荷リセット → **Amazon にサインインする前に** WinterBreak ファイルをコピー、`LocalStorage` フォルダ・`ku`・`mfa` フォルダがあれば削除、などを試す（kindlemodding の FAQ 参照）。
6. 約 30 秒待ち、「**Finished installing jailbreak**」が出たら完了 → **機内モードを ON に戻す**。

AdBreak / SpringBreak も「指定ファイルを USB でコピー → Kindle 上で所定の操作」という流れは似ているが、細部が違うので各ガイドに従う。

### 2-4. 脱獄後の必須作業

1. **Hotfix を入れる**（脱獄を OTA 後も維持するため）
   - [Update_hotfix_universal.bin](https://github.com/KindleModding/Hotfix/releases/latest/download/Update_hotfix_universal.bin) を Kindle ルートへコピー（他の `.bin` は削除。OTARenamer を入れていたらアンインストール）。
   - 設定 → 右上「︙」→ **Kindle をアップデート** → 確認。
   - 完了後、ライブラリに出る **「Run Hotfix」（または Run Bridge）** を開く → 再起動。
   - **OTA アップデートが入るたびに Run Hotfix をやり直す。**
2. **KUAL と MRPI を入れる**（拡張機能ランチャーとパッケージインストーラ）
   - [kual-mrinstaller-khf.tar.xz](https://fw.notmarek.com/khf/kual-mrinstaller-khf.tar.xz) を展開し、`extensions` と `mrpackages` フォルダを Kindle ルートへ。
   - KUAL 本体: 6世代以降は「KUAL Coplate (Update_KUALBooklet_HDRepack.bin)」、それ以前は KUAL Legacy。`.bin` を `mrpackages` に入れる。
   - 取り外して、ホームの検索バーに **`;log mrpi`** と入力して実行 → しばらくするとライブラリに **KUAL** が出る（途中「Application Error」が出ても正常）。
3. **OTA（自動アップデート）を止める**
   - WinterBreak / SpringBreak で脱獄した場合は OTA ブロック済み。
   - それ以外: 5.11 以降は `renameotabin` 拡張を `extensions` に入れ、KUAL → Rename OTA Binaries → Rename。5.10 以前は Kindle ルートに `update.bin.tmp.partial` という**空フォルダ**を作る。
4. **（推奨）USBNetwork / SSH を入れる**
   - KUAL から USBNetwork（または KOReader 経由の SSH）を有効にすると、PC から `ssh root@<KindleのIP>` でスクリプトを直接編集・デバッグできる。開発効率が段違い。
5. **（推奨）FBInk を入れる**
   - 標準の `eips` より新機種での PNG 表示・回転・リフレッシュ制御が確実。MRPI で入れられる。

---

## 3. サーバー側: ダッシュボード画像を作る

### 3-1. 画像の要件

- **グレースケール PNG、アルファチャンネル（透過）なし。** 不正な PNG はスリープ時にフリーズの原因になる報告あり。
- **解像度は機種の画面ピクセルぴったり**（拡大縮小させない）。
- 横置きにするなら **横長でデザインしてから 90° / 270° 回転**して縦長 PNG として配信（Kindle の向きに合わせて実機で確認）。
- E-ink は 16 階調。中間色は少なめに、文字は太め・大きめ、**黒 / 白 / 数段階のグレー**だけで設計するとくっきりする。
- 2 倍解像度で描いて縮小するとアンチエイリアスがきれい。

### 3-2. 作り方（どれでも可）

1. **HTML + ヘッドレス Chrome（Puppeteer / Playwright）でスクショ** ← 一番デザインしやすい。写真のレイアウトはこれで作るのが楽。
2. Python + Pillow で直接描画（J105588/kindle_dashboard の方式。依存が少ない）。
3. Home Assistant の画面をスクショ（sibbl/hass-lovelace-kindle-screensaver、Docker 一発）。

Playwright + ImageMagick 例:

```bash
# 1) HTML（データを埋め込んだダッシュボード）をスクショ
npx playwright screenshot --viewport-size=1448,1072 http://localhost:3000/dashboard shot.png
# 2) Kindle 用に変換（グレースケール・透過なし・縦向きに回転）
convert shot.png -rotate 90 -colorspace Gray -alpha off -depth 8 \
        -dither FloydSteinberg -remap eink16.png dash.png   # eink16.png = 16階調パレット(任意)
```

Python (Pillow) で変換するなら:

```python
from PIL import Image
img = Image.open("shot.png").convert("L")   # グレースケール・透過なし
img = img.rotate(90, expand=True)
img = img.quantize(colors=16).convert("L")   # 16階調に寄せる（任意）
img.save("dash.png", optimize=True)
```

### 3-3. 写真の各パネルのデータ取得元

| パネル | データ源 | 備考 |
|---|---|---|
| 日付・時刻 | サーバーの時計（または Kindle 側で描画、§4-3） | |
| 屋外: 現在・最高最低・降水・体感・湿度・風 | **[Open-Meteo](https://open-meteo.com/)**（無料・APIキー不要、JMA モデルあり） | 写真もこれ |
| 3時間ごとの予報 / この先の天気 | Open-Meteo の `hourly` / `daily` | 天気コード(WMO)→アイコンに変換 |
| 室内: 温度・湿度・CO2 | **SwitchBot API v1.1**（CO2センサー / 温湿度計）、Nature Remo、Netatmo、または Raspberry Pi + SCD40/SCD41 センサー | CO2 の「良好」等は 1000ppm 未満で良好などの閾値で判定 |
| マーケット（ドル円・日経平均・NYダウ） | Yahoo Finance の非公式 chart API（`JPY=X`, `^N225`, `^DJI`） | 写真もこれ。非公式なので壊れる可能性あり。代替: Stooq, Alpha Vantage |
| 主要ニュース | **NHK ニュース RSS**（`https://www.nhk.or.jp/rss/news/cat0.xml`） | 見出しだけ表示 |
| Kindle 電池残量 | Kindle が画像を取りに来るときにクエリで送る（§4-2） | 次回の画像に反映 |

Open-Meteo のリクエスト例（東京）:

```
https://api.open-meteo.com/v1/forecast?latitude=35.68&longitude=139.76
  &current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_direction_10m
  &hourly=temperature_2m,weather_code,precipitation_probability
  &daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max
  &timezone=Asia%2FTokyo&wind_speed_unit=ms&forecast_days=4
```

Yahoo Finance（非公式）例: `https://query1.finance.yahoo.com/v8/finance/chart/%5EN225?interval=1d&range=5d`
（`meta.regularMarketPrice` と `meta.chartPreviousClose` から前日比を計算）

SwitchBot: `GET https://api.switch-bot.com/v1.1/devices/{deviceId}/status`（ヘッダーに token / t / nonce / HMAC-SHA256 の sign が必要。アプリ「プロフィール → 設定 → アプリバージョンを10回タップ → 開発者向けオプション」でトークンとシークレット取得）。

### 3-4. 配信

- 自宅 LAN 内: `python -m http.server` や Node/Express、nginx で `dash.png` を配信するだけでよい。cron / systemd timer で 1〜10 分ごとに再生成。
- サーバーを置きたくない: **GitHub Actions で生成 → GitHub Pages で公開**（J105588/kindle_dashboard が実例。GitHub の schedule は遅延・欠落するので cron-job.org から `workflow_dispatch` を叩く運用）。
- 変化がないときは `ETag` / `Last-Modified` を変えないと、Kindle 側で無駄な書き換えを省ける。

---

## 4. Kindle 側: 画像を取ってきて表示する

### 4-1. 既製のクライアントを使う場合

| プロジェクト | 内容 |
|---|---|
| [pascalw/kindle-dash](https://github.com/pascalw/kindle-dash) | 一定間隔で PNG を取得 → 表示 → **RTC で RAM サスペンド**して省電力。cron 式でスケジュール、部分/全面リフレッシュ切替、電池低下通知。KUAL から起動可。HTTPS 対応の `xh` 同梱 |
| [J105588/kindle_dashboard](https://github.com/J105588/kindle_dashboard) | **日本語**。第7世代向け。背景は10分ごと、**時計の数字だけ毎分部分描画**（ちらつかない）。読書端末としても使える設計、スクリーンセーバー差し替え機能あり |
| Online Screensaver（MobileRead） | スクリーンセーバー画像を定期的にサーバー画像に差し替える。スリープ中も表示が残る |
| [usetrmnl/trmnl-koreader](https://github.com/usetrmnl/trmnl-koreader) | KOReader を入れて TRMNL（または自前 BYOS サーバー）の画像を表示。TRMNL 公式は 2026 年時点でこちらを推奨 |

kindle-dash の導入手順:

1. [Releases](https://github.com/pascalw/kindle-dash/releases) をダウンロードして展開。
2. `local/fetch-dashboard.sh` の URL を自分のサーバーの PNG に書き換え、`local/env.sh` で `TIMEZONE="Asia/Tokyo"`、`REFRESH_SCHEDULE`（cron 式）などを設定。
3. Kindle の `/mnt/us/dashboard` にコピー（例: `rsync -vr ./ kindle:/mnt/us/dashboard`。USB 接続なら `dashboard` フォルダをルートへ）。
4. KUAL 拡張 (`KUAL/kindle-dash` を `extensions` へ) から起動、または SSH で `/mnt/us/dashboard/start.sh`。10〜15 秒後にサスペンドに入る。
5. Kindle 4 NT で検証されたもの。**新しい機種では RTC のパスや framework 停止コマンドを機種に合わせて修正が必要**なことがある。

### 4-2. 自作する場合の最小スクリプト（考え方）

`/mnt/us/extensions/mydash/` に置き、KUAL から起動する想定。

```sh
#!/bin/sh
URL="http://192.168.1.10:8080/dash.png"
IMG=/tmp/dash.png
INTERVAL=60   # 秒

# スクリーンセーバー（自動スリープ）を止める
lipc-set-prop com.lab126.powerd preventScreenSaver 1
# 標準 UI を止めて画面を占有（機種により `stop lab126_gui` / `/etc/init.d/framework stop`）
stop lab126_gui 2>/dev/null || /etc/init.d/framework stop

n=0
while true; do
  BATT=$(lipc-get-prop com.lab126.powerd battLevel)       # 電池残量(%)
  if wget -q -O "$IMG" "$URL?battery=$BATT"; then
    if [ $((n % 10)) -eq 0 ]; then
      fbink -c -g file="$IMG"     # 10回に1回は全面リフレッシュ（残像除去）
    else
      fbink -g file="$IMG"        # 通常は部分更新（チラつかない）
    fi
    # FBInk がなければ: eips -f -g "$IMG"（全面） / eips -g "$IMG"（部分）
  fi
  n=$((n + 1))
  sleep $INTERVAL
done
```

ポイント:
- **`preventScreenSaver 1`** でスリープを防ぐ（終了時に 0 に戻す）。
- 標準 UI（framework / lab126_gui）を止めないと、ステータスバー等が上書きしてくる。
- 部分更新を続けると残像（ゴースト）が出るので **N 回に 1 回は全面リフレッシュ (`-f` / `-c`)**。
- 内蔵の `wget`/`curl` は OpenSSL が古く **HTTPS で失敗しやすい** → LAN 内は HTTP にするか、`xh`/`ht` などの静的バイナリを同梱する（kindle-dash 方式）。
- Wi-Fi 接続待ち: `lipc-get-prop com.lab126.wifid cmState` が `CONNECTED` になるまで待つ。
- 停止方法を必ず用意（KUAL メニューに Stop、または電源ボタン監視）。再起動すれば通常の Kindle に戻る作りにしておくと安全。

### 4-3. 毎分の時計表示について（写真の「14:19」）

選択肢は 2 つ。

1. **常時給電して 1 分ごとに画像ごと更新**（シンプル。写真の Kindle は 96% なので給電運用と思われる）。
2. **背景は 5〜10 分ごと、時計の数字だけ Kindle 側で部分描画**（J105588 方式。0〜9 の数字画像を先に配っておき、変わった桁だけ `eips`/`fbink` で貼る。通信が減りチラつかない）。

### 4-4. 電池運用したい場合

- RTC ウェイクアップで更新の間だけ起きて RAM サスペンド（kindle-dash 方式）。
- 30 分間隔更新で 2〜4 週間持ったという報告あり。毎分更新は給電必須。
- フロントライトは 0 に。Wi-Fi は取得時だけ ON（KOReader なら設定で可能）。

---

## 5. 脱獄できない場合（方式 D）

- Kindle の「実験的ブラウザ（Beta ブラウザ）」で、自分のダッシュボード HTML（`<meta http-equiv="refresh" content="60">` 付き）を開きっぱなしにする。
  - ブラウザは古い WebKit（ES5 程度）。モダン JS・Web フォントは不可。**サーバー側で PNG を作り、それを `<img>` で全面表示して定期リロード**するのが現実的。
  - 自動スリープが邪魔: 旧ファームでは検索バーに **`~ds`** と入力するとスクリーンセーバーが無効化できた（Paperwhite 1/3 で報告あり。新しい FW では効かない）。
- 不安定・電池も持たないので、本格運用なら脱獄可能な中古 Kindle を入手するか、専用 E-ink（TRMNL、Raspberry Pi + Waveshare 7.5" など）も検討。

---

## 6. トラブルシューティング

| 症状 | 対処 |
|---|---|
| WinterBreak のアイコンがストアに出ない | 機内モードの切り替え順を見直す / 工場出荷リセット後サインイン前にコピー / `LocalStorage`・`ku`・`mfa` を削除 |
| Hotfix がインストールできない | 以前の OTA 無効化が残っている → KUAL で Rename OTA Binaries → Restore → Hotfix 再導入 → 再度無効化 |
| 勝手にアップデートされた | ライブラリの **Run Hotfix** を実行。脱獄が消えていたら FW に合うツールで再脱獄 |
| 画像が表示されない / フリーズ | PNG がグレースケール・透過なし・画面ぴったりサイズか確認。`file dash.png` で確認 |
| 残像が出る | 全面リフレッシュの頻度を上げる |
| HTTPS で取得できない | HTTP にする or `xh` 等の静的バイナリを使う |
| `Fetching JSON... error`（TRMNL） | 機内モードのままになっている |
| 改行コードでスクリプトが動かない | Windows で編集した `.sh` は **LF** で保存 |

---

## 7. おすすめの進め方（このプロジェクトでの TODO）

1. [ ] 手持ち Kindle の**機種とファームウェア（枝番まで）**を確認 → 使える脱獄ツールを決定
2. [ ] 機内モードで脱獄 → Hotfix → KUAL/MRPI → OTA 無効化 → USBNetwork(SSH) → FBInk
3. [ ] サーバー側: 写真のレイアウトを HTML で作成し、Open-Meteo / Yahoo Finance / NHK RSS / SwitchBot からデータ取得
4. [ ] Playwright でスクショ → グレースケール PNG（機種解像度・回転）に変換 → HTTP 配信（Raspberry Pi 常駐 or GitHub Actions + Pages）
5. [ ] Kindle 側: kindle-dash を流用するか §4-2 の自作スクリプトで 1 分ごと表示。電池残量をクエリで送信
6. [ ] 常時給電・スタンド設置、残像対策の全面リフレッシュ頻度を調整

---

## 参考リンク

### 脱獄（一次情報）
- [Kindle Modding Wiki – Jailbreaking](https://kindlemodding.org/jailbreaking/)
- [KindleModding/WinterBreak](https://github.com/KindleModding/WinterBreak) / [AdBreak](https://github.com/KindleModding/AdBreak) / [SpringBreak](https://github.com/KindleModding/SpringBreak) / [Hotfix](https://github.com/KindleModding/Hotfix)
- [Disabling OTA Updates (kindlemodding)](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/disable-ota.html)
- [Setting Up A Hotfix (kindlemodding)](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/setting-up-a-hotfix/)
- [KUAL / MRPI (NiLuJe / notmarek)](https://fw.notmarek.com/khf/)

### 脱獄（解説記事）
- [GIGAZINE: WinterBreak リリース](https://www.gigazine.net/news/20250218-winterbreak-kindle-jailbreak/)
- [Zenn: 【自己責任】Kindleを脱獄してみた【WinterBreak】](https://zenn.dev/headwaters/articles/0f77165087f246)
- [The eBook Reader: New Kindle Jailbreak (AdBreak)](https://blog.the-ebook-reader.com/2025/09/26/new-kindle-jailbreak-released/)
- [BookFere: SpringBreak Tutorial](https://en.bookfere.com/post/springbreak-jailbreak-tutorial-for-kindle-firmware-5-19-2-5-18-1-1-1.html)
- [Kindle Jailbreak Guide 2026 (itechguides)](https://www.itechguides.com/this-is-the-kindle-jailbreak-guide-amazon-doesnt-want-you-to-read-but-it-isnt-universal/)（二次情報。対応表は一次情報で要確認）

### ダッシュボード実装例
- [pascalw/kindle-dash](https://github.com/pascalw/kindle-dash)（Kindle 側クライアント、省電力）
- [J105588/kindle_dashboard](https://github.com/J105588/kindle_dashboard)（日本語、Open-Meteo、時計の部分更新、GitHub Actions 運用）
- [sibbl/hass-lovelace-kindle-screensaver](https://github.com/sibbl/hass-lovelace-kindle-screensaver)（Home Assistant 画面を Kindle 用 PNG に）
- [hermannsblum/kindle_infoscreen](https://github.com/hermannsblum/kindle_infoscreen)（脱獄なし・ブラウザ方式、`~ds`）
- [usetrmnl/trmnl-kindle](https://github.com/usetrmnl/trmnl-kindle) / [usetrmnl/trmnl-koreader](https://github.com/usetrmnl/trmnl-koreader)
- [terminalbytes: Kindle dashboard e-ink display (2026)](https://terminalbytes.com/kindle-dashboard-eink-display-2026)
- [Hackaday: Modern E-Ink Dashboards, Kindle And Otherwise (2026/07)](https://hackaday.com/2026/07/03/modern-e-ink-dashboards-kindle-and-otherwise/)

### データ源
- [Open-Meteo](https://open-meteo.com/en/docs)
- [NHK ニュース RSS](https://www.nhk.or.jp/toppage/rss/index.html)
- [SwitchBot API](https://github.com/OpenWonderLabs/SwitchBotAPI)
