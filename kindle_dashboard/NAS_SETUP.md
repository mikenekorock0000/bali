# NAS への設置手順（Kindle ダッシュボード）

配布ファイル（`kindle_dashboard/dist/`）:

| ファイル | 置き場所 |
|---|---|
| `kindle-dashboard-nas.zip` | NAS（Docker で動かすサーバー） |
| `kindle-dashboard-kindle.zip` | Kindle（脱獄・KUAL 導入後に USB でコピー） |

zip が古いときは、リポジトリのルートで `python kindle_dashboard/tool/package.py` を実行すると作り直せる。

## 1. NAS に置く

1. `kindle-dashboard-nas.zip` を展開し、できた `kindle-dashboard` フォルダを NAS の共有フォルダへコピー
   （例: Synology は File Station で `/docker/kindle-dashboard/`）。中身はこうなる:

   ```
   kindle-dashboard/
     docker-compose.yml   Dockerfile   requirements.txt   serve.py   fetch_fonts.py
     dashboard/           （プログラム）
     config/config.json   ← 設定（下で編集）
     .env.example         ← 必要なら .env にコピーして使う
     NAS_SETUP.md         （この手順）
   ```

2. **`config/config.json` を編集**（最低限ここだけ）

   ```json
   "location": {"name": "自宅", "latitude": 35.6812, "longitude": 139.7671},
   ```

   緯度・経度は Google マップで自宅を右クリックすると出る。他の項目はそのままでよい
   （画面サイズは Kindle Paperwhite 第7世代 `1448 x 1072` が既定）。

3. **（任意）`.env` を作る**: `.env.example` を `.env` という名前でコピーし、使うものだけ書く。
   - `CALENDAR_ICS_URLS=` … Google カレンダーの「iCal 形式の非公開 URL」（3:00〜9:00 に月表示）
   - `SWITCHBOT_TOKEN=` / `SWITCHBOT_SECRET=` … 室内の温湿度・CO2（`config.json` の `indoor` も設定）

   ※ File Station などでは `.` で始まるファイルが見えないことがある。その場合は SSH で作るか、
   `docker-compose.yml` の `environment:` に直接書いてもよい（人に見せない）。

## 2. 起動する

- **Synology（DSM 7.2 以降）**: Container Manager → プロジェクト → 作成 →
  プロジェクト名 `kindle-dashboard`、パスに上のフォルダ →「既存の docker-compose.yml を使用」→ 次へ → 完了。
  初回はイメージ作成（Python・フォントのダウンロード）に数分かかる。
- **QNAP / その他（SSH）**:

  ```bash
  cd /share/Container/kindle-dashboard   # 置いた場所
  docker compose up -d --build           # 古い環境では docker-compose up -d --build
  ```

## 3. 確認する（PC のブラウザで）

| URL | 見えるもの |
|---|---|
| `http://<NASのIP>:8080/preview.png` | 横向きのダッシュボード |
| `http://<NASのIP>:8080/health` | 各データの取得状況。`"ok": true` ならOK |
| `http://<NASのIP>:8080/dash.png` | Kindle が取りに来る画像（縦向き 1072×1448） |

`/health` で `"ok": false` の項目があれば、その `error` の文をメモしておく（直すときに使う）。

- ポート 8080 が使用中 → `docker-compose.yml` の `"8080:8080"` を `"8090:8080"` などに。
- NAS のファイアウォールが有効 → そのポートを LAN 内に許可。
- **NAS の IP はルーターで固定**しておく（変わると Kindle が画像を取りに行けなくなる）。

## 4. Kindle 側

詳しくは `docs/kindle-dashboard/paperwhite3.md`（脱獄）と `kindle_dashboard/README.md`「2. Kindle に入れる」。

1. 充電（50% 以上）→ 機内モード ON → WinterBreak で脱獄 → Hotfix → KUAL/MRPI。
2. `kindle-dashboard-kindle.zip` を展開し、中の `extensions/dashboard` を Kindle の `extensions/` にコピー。
3. Kindle の `extensions/dashboard/config.sh` の 1 行を書き換え（**LF 改行のまま保存**。VS Code 推奨）:

   ```sh
   SERVER_URL="http://<NASのIP>:8080/dash.png"
   ```

4. 機内モード OFF（Wi-Fi 接続）→ KUAL → Dashboard → **Test** で画像が出れば → **Start**。
   終了は電源ボタン。

## 5. 更新・変更

| やりたいこと | 方法 |
|---|---|
| 設定（`config.json` / `.env`）を変えた | プロジェクトを再起動（SSH: `docker compose up -d`） |
| プログラムを新しくした | ファイルを差し替えて作り直し（SSH: `docker compose up -d --build`、Container Manager は「ビルド」） |
| ログを見る | Container Manager のコンテナ →「ログ」／ `docker logs kindle-dashboard` |
| 時計のフォントを変える | `config.json` に `"clock": {"font": "ZenDots-Regular.ttf"}` など（README の表） |
