# NAS への設置手順（Kindle ダッシュボード）

配布ファイル（`kindle_dashboard/dist/`）:

| ファイル | 置き場所 |
|---|---|
| `kindle-dashboard-nas.zip` | NAS（Docker で動かすサーバー） |
| `kindle-dashboard-kindle.zip` | Kindle（脱獄後に USB でコピー） |

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

- ポート 8080 が使用中（起動時に `driver failed programming external connectivity` と出る）→ `docker-compose.yml` の `"8080:8080"` を `"8090:8080"` などに（Container Manager ならプロジェクトの「YAML 設定」で編集）。Kindle の `SERVER_URL` も同じ番号に。
- NAS のファイアウォールが有効 → そのポートを LAN 内に許可。
- **NAS の IP はルーターで固定**しておく（変わると Kindle が画像を取りに行けなくなる）。

## 4. Kindle 側

詳しくは `docs/kindle-dashboard/paperwhite3.md`（脱獄）と `kindle_dashboard/README.md`「2. Kindle に入れる」。

脱獄（WinterBreak2）が済んでいれば、Hotfix・KUAL は不要。

1. USB で Mac/PC に接続し、`kindle-dashboard-kindle.zip` を展開してできた 2 つのフォルダを Kindle のルートへコピー:
   - **`dashboard`** → Kindle のルート（`/mnt/us/dashboard` になる。本体とスクリプト）
   - **`documents`** の中の 3 つの `.sh` → Kindle の `documents` フォルダ（ライブラリに本として出る起動ボタン）
2. Kindle の `dashboard/config.sh` の `SERVER_URL` を `http://<NASのIP>:8080/dash.png` に書き換え
   （**改行コードは LF のまま保存**。Mac のテキストエディットは「標準テキスト」で。VS Code 推奨）。
3. 取り出して、機内モード OFF（Wi-Fi 接続）。ライブラリに **Dashboard テスト / 開始 / 停止** が出る。
4. **Dashboard テスト** を開く → 画像が出れば接続 OK（数秒で元の画面に戻ることがある）。
5. **Dashboard 開始** を開く → 約 5 秒後にダッシュボードに切り替わり、以後毎分更新。

**Mac の場合（おすすめ）**: Finder でコピーすると隠しファイル `._〜.sh` ができ、ライブラリに壊れた項目として出てしまう。
ターミナルで次を実行すると、それを避けてコピーと URL の書き換えまで済む（`192.168.x.x` は NAS の IP に置き換え）:

```bash
cd ~/Downloads && rm -rf kd && unzip -q kindle-dashboard-kindle.zip -d kd
COPYFILE_DISABLE=1 cp -R kd/dashboard /Volumes/Kindle/
COPYFILE_DISABLE=1 cp kd/documents/*.sh /Volumes/Kindle/documents/
sed -i '' 's|^SERVER_URL=.*|SERVER_URL="http://192.168.x.x:8080/dash.png"|' /Volumes/Kindle/dashboard/config.sh
find /Volumes/Kindle/dashboard /Volumes/Kindle/documents -name '._*' -delete
grep SERVER_URL /Volumes/Kindle/dashboard/config.sh   # 書き換わったか確認
```

終了は電源ボタン（またはライブラリの **Dashboard 停止**）。

## 5. 更新・変更

| やりたいこと | 方法 |
|---|---|
| 設定（`config.json` / `.env`）を変えた | プロジェクトを再起動（SSH: `docker compose up -d`） |
| プログラムを新しくした | ファイルを差し替えて作り直し（SSH: `docker compose up -d --build`、Container Manager は「ビルド」） |
| ログを見る | Container Manager のコンテナ →「ログ」／ `docker logs kindle-dashboard` |
| 時計のフォントを変える | `config.json` に `"clock": {"font": "ZenDots-Regular.ttf"}` など（README の表） |
