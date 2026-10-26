# Kindle ダッシュボード（Kindle Paperwhite 第7世代向け）

古い Kindle を「時計・天気・室内環境・市況・ニュース」の E-ink ダッシュボードにする。
調査・脱獄手順は [docs/kindle-dashboard/](../docs/kindle-dashboard/)（PW3 専用手順: [paperwhite3.md](../docs/kindle-dashboard/paperwhite3.md)）。

**このあとやること・引き継ぎ**: [NEXT_STEPS.md](NEXT_STEPS.md)

**NAS に置くファイル**: [dist/kindle-dashboard-nas.zip](dist/kindle-dashboard-nas.zip)（サーバー）と
[dist/kindle-dashboard-kindle.zip](dist/kindle-dashboard-kindle.zip)（Kindle 側）。手順は [NAS_SETUP.md](NAS_SETUP.md)。
作り直しは `python kindle_dashboard/tool/package.py`。

![preview](../docs/kindle-dashboard/preview.png)

（ダミーデータで描画したプレビュー。実機では 90° 回転した 1072×1448 の画像が表示される）

## 仕組み

```
server/ (PC・Raspberry Pi)                         kindle/ (脱獄済み Kindle)
  Open-Meteo / Yahoo Finance / NHK RSS / SwitchBot      KUAL ▸ Dashboard ▸ Start
        │ 5〜15分ごとに取得（失敗時は前回値）              │ 毎分 0 秒すぎに
        ▼                                               ▼
  GET /dash.png ──── その時刻で描画した PNG ────────▶ wget → eips/fbink で表示
        ▲                                               │
        └──────── ?battery=96&charging=1 ◀───────────────┘ （電池残量を画面下に表示）
```

- 描画はすべてサーバー側（Python + Pillow）。Kindle は画像を貼るだけ。
- 時計はリクエストのたびにその時刻で描くので、Kindle が毎分取りに来れば分単位で正確。
- 15 回に 1 回は全面リフレッシュして残像を消す。

## 1. サーバーを動かす

### A. NAS の Docker で動かす（おすすめ）

NAS に Docker（Synology の Container Manager、QNAP の Container Station など）が入っていれば、
`server/` フォルダだけで動く。フォントはイメージ作成時に自動で取得する（NAS からインターネットへの接続が必要）。

1. **NAS にファイルを置く**: `kindle_dashboard/server` フォルダの中身を NAS の共有フォルダへコピー
   （例: Synology なら File Station で `/docker/kindle-dashboard/` を作ってそこへ。`git clone` してもよい）。
2. **設定ファイルを作る**: 同じ場所に `config` フォルダを作り、`config.example.json` を
   `config/config.json` という名前でコピーして、`location`（緯度・経度）を自宅に合わせる。
   （`config/config.json` が無くても東京の設定で起動する）
3. **起動する**
   - **Synology (DSM 7.2 以降)**: Container Manager → プロジェクト → 作成 →
     パスに手順 1 のフォルダを指定 →「既存の docker-compose.yml を使用」→ 次へ → 完了。
     イメージのビルドと起動が自動で行われる。
   - **QNAP / その他**: NAS に SSH でログインして
     ```bash
     cd /share/Container/kindle-dashboard   # 手順 1 のフォルダ
     docker compose up -d --build           # 古い環境では docker-compose up -d --build
     ```
4. **確認**: PC のブラウザで `http://<NASのIP>:8080/preview.png` を開く。
   `http://<NASのIP>:8080/health` で各データの取得状況（`ok: true/false`）が見られる。
5. Kindle の `config.sh` の `SERVER_URL` を `http://<NASのIP>:8080/dash.png` にする。
   **NAS の IP はルーターで固定**しておくと安心。

その他:
- 設定を変えたら Container Manager でプロジェクトを再起動（SSH なら `docker compose restart`）。
- プログラムを更新したら、ファイルを差し替えて再ビルド（SSH なら `docker compose up -d --build`）。
- ポート 8080 が使用中なら `docker-compose.yml` の `"8080:8080"` の左側を変える（例 `"8090:8080"`）。
- NAS のファイアウォールを有効にしている場合は、そのポートを LAN 内に許可する。
- SwitchBot を使うなら `.env.example` を `.env` にコピーしてトークンとシークレットを書く。
- ログ: Container Manager のコンテナ詳細 →「ログ」、または `docker logs kindle-dashboard`。

### B. PC / Raspberry Pi で直接動かす

Python 3.9 以上が必要。

```bash
cd kindle_dashboard/server
pip install -r requirements.txt
python fetch_fonts.py            # フォント（日本語 + 時計用）を取得
cp config.example.json config.json
# config.json の location（緯度・経度）を自宅に合わせる

python serve.py render --demo    # out/preview.png でデザインを確認（通信なし）
python serve.py render           # 実データで 1 枚描画（取得結果も表示）
python serve.py                  # 配信開始 → 表示された http://<IP>:8080/dash.png を控える
```

- ブラウザで `http://<IP>:8080/preview.png`（横向き確認用）と `/health`（各データの取得状況・Kindle の電池）を開ける。
- 常時起動は Raspberry Pi などで `kindle-dashboard.service`（systemd の設定例）を使う。
- Windows で「ファイアウォールの許可」が出たらプライベートネットワークを許可。
- フォントは `fetch_fonts.py` が使えない環境では、`config.json` の `font_path` に手元の日本語フォント（例: `C:/Windows/Fonts/meiryo.ttc`）を指定してもよい（太さの切り替えは可変フォントのみ）。

### config.json

| 項目 | 内容 |
|---|---|
| `location` | 地名・緯度・経度（Google マップで右クリックすると表示） |
| `clock` | 時計の数字のフォントと太さ（下記） |
| `display` | 画面サイズ（横置き）。PW3 は `1448 x 1072`（既定）、PW2/Voyage 以前の 6 インチ機は `1024 x 758`、無印 Kindle は `800 x 600` |
| `display.rotate` | Kindle 用画像の回転（時計回り 0/90/180/270）。表示が逆さなら 270 に |
| `refresh_minutes` | データ源ごとの取得間隔（分） |
| `news.url` | RSS の URL。NHK のカテゴリ別 RSS などに変更可 |
| `market.symbols` | マーケット欄に出す 3 銘柄（下記） |
| `indoor` | 室内センサー。SwitchBot を使うなら下記 |

### 時計のフォント

`config.json` に `"clock": {"font": "ZenDots-Regular.ttf"}` のように書く（既定は DM Serif Display）。
見本: [clock_candidates.png](../docs/kindle-dashboard/clock_candidates.png)、
横長の太字（左から DM Serif / Zen Dots / Unbounded Black）: [clock_wide_candidates.png](../docs/kindle-dashboard/clock_wide_candidates.png)

| 見本 | `font` | `weight` | 雰囲気 |
|---|---|---|---|
| A | `Outfit-VF.ttf` | `Light` / `Regular` | 細めで現代的・丸みあり |
| B | `Outfit-VF.ttf` | `Medium` | A を太くした版。遠くからも読みやすい |
| C | `Montserrat-VF.ttf` | `Light` | 幾何学的で上品 |
| D | `JosefinSans-VF.ttf` | `Light` | 細く背が低い・クラシック |
| E | `BebasNeue-Regular.ttf` | （なし） | 縦長で力強い |
| F | `Oswald-VF.ttf` | `Light` | 縦長・すっきり |
| H | `DMSerifDisplay-Regular.ttf` | （なし） | セリフ体・雑誌風（既定） |
| I | `SpaceGrotesk-VF.ttf` | `Light` | 個性的な「1」 |
| J | `Urbanist-VF.ttf` | `Thin` | とても細い（E-ink では薄く見えることあり） |
| K | `Lexend-VF.ttf` | `ExtraLight` | 細めで読みやすい |
| L | `ZenDots-Regular.ttf` | （なし） | 横長の太字・Horizon 風（0 に斜線） |
| M | `Unbounded-VF.ttf` | `Black` / `Bold` | 横長の太字・Horizon 風 |
| N | `KronaOne-Regular.ttf` | （なし） | 横長の太字 |
| O | `Orbitron-VF.ttf` | `Black` | 横長・SF 風 |
| P | `Archivo-VF.ttf` | `"axes": {"Weight": 900, "Width": 125}` | 横長の極太（幅も指定） |

- 太さだけでなく幅なども変えられるフォントは `weight` の代わりに `"axes": {"Weight": 900, "Width": 125}` のように数値で指定できる。
- 手持ちのフォント（例: Horizon）を使うときは、Docker なら `config` フォルダに置いて `"font": "/config/Horizon.otf"`
  のように絶対パスで指定する（Google Fonts にない有料・個人配布フォントは同梱していない。ライセンスは各自で確認）。
- 数字は日付の下の空間で上下中央に置くので、横長のフォントでも間延びしない。

可変フォント（`-VF`）の `weight` は `Thin` `ExtraLight` `Light` `Regular` `Medium` `SemiBold` `Bold` などから選べる。

### マーケット欄（ドル円・eMAXIS Slim 米国株式(S&P500)・iFreeNEXT FANG+）

既定では次の 3 つを表示する。投資信託は 1 日 1 回（営業日の夜）更新される基準価額で、ラベルの下に基準日を出す。

| 表示 | 中身 | 取得元 (`source`) |
|---|---|---|
| ドル円 | USD/JPY（ほぼリアルタイム） | `yahoo`: Yahoo Finance（非公式 API）`"symbol": "JPY=X"` |
| S&P500 | eMAXIS Slim 米国株式（S&P500）の基準価額 | `mufg`: 三菱UFJアセットマネジメント公式「投信情報 API」`"code": "03311187"`（協会コード） |
| FANG+ | iFreeNEXT FANG+インデックスの基準価額 | `toushin`: 投資信託協会「投信総合検索ライブラリー」の CSV `"isin": "JP90C000FZD4", "code": "04311181"` |

- 他の投資信託に替えるときは `toushin` を使えば運用会社を問わず取得できる。ISIN と協会コード（8 桁）は
  [投信総合検索ライブラリー](https://toushin-lib.fwg.ne.jp/FdsWeb/) や Yahoo!ファイナンスのファンドページで調べられる。
- 投資信託ではなく NYSE FANG+ 指数そのものを出したい場合は `{"label": "FANG+", "source": "yahoo", "symbol": "^NYFANG", "unit": "pt", "decimals": 0}` に替える。
- `refresh_minutes` を銘柄ごとに指定できる（投資信託は 60 分）。

### 服装指数（「今日の服装」の帯）

tenki.jp の服装指数を参考にした**独自の目安**（tenki.jp の値そのものではない）。Open-Meteo の 1 時間ごとの予報から計算する。

- 対象時間: 今日の「今〜21時」（6時より前なら 6時から）。**18時以降は明日の 6〜21時**で「明日の服装」を出す。
- 体感温度 = 0.6 × 最高体感 + 0.4 × 最低体感 で、次の表から指数と服装を決める。

| 体感温度 | 指数 | 表示 |
|---|---|---|
| 29℃〜 | 90 | ノースリーブでもOK |
| 25〜29℃ | 80 | 半袖で快適 |
| 21〜25℃ | 70 | 半袖＋薄い羽織りを |
| 17〜21℃ | 60 | 長袖シャツで快適 |
| 13〜17℃ | 50 | 薄手のセーターを |
| 9〜13℃ | 40 | ジャケットが必要 |
| 5〜9℃ | 30 | コートが必要 |
| 0〜5℃ | 20 | 厚手のコートを |
| 〜0℃ | 10 | ダウン・手袋で防寒 |

- イラスト: 左に今日の服（ダウン＋マフラー〜ノースリーブの 9 種類）。傘が必要な日（降水確率 50% 以上）は隣に黒地の大きな傘を出し、「傘を持って」を太字にする。
- 帯の右側は 1 日（0〜24時）の気温の折れ線グラフ。背景の灰色の棒は降水確率、点線は現在時刻、見出しの横に最低〜最高。服装と同じく 18時以降は明日の分を出す。
- 指数（10〜90）は服装とイラストの選択に使い、画面には数値を出さない。
- ひとこと（入りきらない分は後ろから省略）: 降水確率 50% 以上「傘を持って」、気温差 10℃ 以上「寒暖差に注意」、風速 8m/s 以上「風が強い」。
- しきい値や文言は `server/dashboard/clothing.py` の先頭で変えられる（寒がりなら各しきい値を 2〜3℃ 上げる、など）。

### Google カレンダー（3:00〜9:00 はニュース欄を今月のカレンダーに）

朝の時間帯だけ、右下のニュース欄が今月の月表示カレンダーに替わる。ログイン設定（OAuth）は不要で、
カレンダーの **iCal 形式の非公開 URL** を読む。繰り返し予定・終日予定・複数日の予定・複数カレンダーに対応し、
日本の祝日も表示する。

1. PC のブラウザで Google カレンダー → 右上の歯車 → 設定 → 左の「マイカレンダーの設定」で対象のカレンダー →
   「カレンダーの統合」→ **「iCal 形式の非公開 URL」** をコピー（`https://calendar.google.com/calendar/ical/.../private-.../basic.ics`）。
2. URL を設定する（どちらか）
   - Docker: `.env` に `CALENDAR_ICS_URLS=<URL>`（家族のカレンダーなど複数ならカンマ区切り）
   - `config.json`: `"calendar": {"ics_urls": ["<URL>", "<URL>"]}`
3. 再起動（`docker compose up -d`）。`/health` の `calendar` が `ok: true` になれば取得できている。

表示: 各日に予定のタイトル（祝日・終日予定は灰色の帯、時刻順）。入りきらない件数は日付の右に「+2」。
今日の日付は白黒反転、過ぎた日は灰色。カレンダーが取得できないときはニュースのまま。15 分ごとに取り直す。

時間帯と週の始まりは `config.json` で変えられる: `"calendar": {"window": ["03:00", "09:00"], "week_start": "sunday"}`
（月曜始まりは `"monday"`）。
表示の確認は `python serve.py render --demo --at 07:30`（時刻を指定して描画）。

> ⚠️ 非公開 URL を知っている人は誰でも予定を読める。`.env` や `config.json` を人に渡したり Git に入れたりしないこと
> （どちらも `.gitignore` 済み）。漏れたら Google カレンダーの同じ画面で「リセット」すると URL が変わる。

### 室内センサー（任意: SwitchBot）

1. SwitchBot アプリ → プロフィール → 設定 → 「アプリバージョン」を 10 回タップ → 開発者向けオプションでトークンとシークレットを取得。
2. 環境変数 `SWITCHBOT_TOKEN` と `SWITCHBOT_SECRET` を設定。
3. `config.json` を `"indoor": {"provider": "switchbot", "device_id": "<CO2センサーのデバイスID>"}` に。
   デバイス ID は `GET https://api.switch-bot.com/v1.1/devices` の一覧で確認できる。
4. CO2 は 1000ppm 未満「良好」、1500ppm 未満「やや高い」、それ以上「換気推奨」と表示。

## 2. Kindle に入れる

前提: 脱獄済み・KUAL 導入済み（[paperwhite3.md](../docs/kindle-dashboard/paperwhite3.md)）、Wi-Fi 設定済み・機内モード OFF。

1. USB で接続し、`kindle/extensions/dashboard` フォルダを Kindle の `extensions/` にコピー。
2. `extensions/dashboard/config.sh` の `SERVER_URL` を、サーバー起動時に表示された URL に書き換える。
   **改行コードは LF のまま保存**（Windows のメモ帳なら右下を「LF」に。VS Code 推奨）。
3. 取り外して KUAL → **Dashboard → Test (1回表示)** で画像が出るか確認。
4. 問題なければ **Dashboard → Start**。以後、毎分更新される。

終了方法: **電源ボタンを押す**（ダッシュボードを終了して通常の Kindle に戻る）／SSH で `sh /mnt/us/extensions/dashboard/bin/stop.sh`／再起動。

### config.sh

| 項目 | 内容 |
|---|---|
| `SERVER_URL` | 画像の URL（LAN 内は http） |
| `INTERVAL` | 更新間隔（秒）。60 なら毎分 0 秒すぎに合わせる |
| `FULL_REFRESH_EVERY` | 何回に 1 回全面リフレッシュするか |
| `STOP_MODE` | `pause`（UI を一時停止, 既定）／ `stop`（UI を停止）。表示が上書きされるなら `stop` に |
| `FRONTLIGHT` | フロントライトの明るさ（0 で消灯、空なら変更しない） |
| `EXIT_ON_POWER_BUTTON` | 1 なら電源ボタンで終了 |
| `LOG_FILE` | ログ。不調時は USB 接続して `extensions/dashboard/dashboard.log` を見る |

FBInk が入っていれば FBInk、なければ標準の `eips` で表示する。

## 3. 開発

```bash
cd kindle_dashboard/server
pip install -r requirements-dev.txt
python -m pytest -q
```

Kindle 側スクリプトは `lipc-*`・`eips` などをスタブにすれば PC 上でも動作確認できる（`sh` / BusyBox ash 互換で記述）。

## 検証状況

- ✅ サーバー: 単体テスト（API 応答の解析、描画、回転、16 階調化、HTTP 配信、電池残量の受け取り）とダミーデータでの描画。
- ✅ Docker: イメージのビルド、コンテナ起動、`/dash.png`・`/health` の応答、ヘルスチェック、非 root 実行、`/config` の設定読み込み。
- ✅ Kindle 側: コマンドをスタブにした PC 上のシミュレーションで、取得 → 全面/部分リフレッシュ → 停止で UI 復帰までを確認。
- ⚠️ 実 API（Open-Meteo / Yahoo Finance / 三菱UFJアセット / 投資信託協会 / NHK RSS / SwitchBot / Google カレンダー）は開発環境から接続できず未確認。応答形式は公開仕様・公開事例に合わせてある。NAS で起動後に `/health` で取得結果が確認できる。
- ⚠️ Kindle 実機（PW3, FW 5.15.1）では未検証。特に `STOP_MODE`、電源ボタンでの終了、FBInk のパスは実機で確認が必要。
