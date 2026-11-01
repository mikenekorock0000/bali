# 自前の ntfy サーバー（状態・指示用）

ESP32 の状態と、ダッシュボードからの指示・遠隔更新のファームウェアを中継する ntfy サーバー。
自宅の常時動く機械で Docker を使って動かし、Cloudflare Tunnel で **https://ntfy.takuya.win** として外に出す。

- ntfy.sh の無料の範囲（1 日 250 件）を気にせず、状態を 1 分ごと、指示を 15 秒ごとに読める。
- 利用者とトークンを登録した人しか読み書きできない（トピック名が漏れても読まれない）。
- **通知は今までどおり ntfy.sh に送る。** iPhone の ntfy アプリにすぐ届くのは ntfy.sh だけのため。
- ルーターのポートは開けない。Cloudflare Tunnel が内側から Cloudflare につなぐ。

## 1. 機械の準備

Docker が動く機械（Linux・Raspberry Pi・NAS・常時動いている Mac / Windows）に Docker を入れる。
このフォルダ（`esp32_engine_starter/server`）をその機械にコピーする（git で持ってきてもよい）。

## 2. Cloudflare Tunnel を作る

1. Cloudflare のダッシュボード → **Zero Trust** → **Networks** → **Tunnels** → **Create a tunnel**。
2. 種類は **Cloudflared**、名前は `hijet` など。
3. 「Install and run a connector」の画面で **Docker** を選ぶ。表示されたコマンドの `--token` の後ろの長い文字列をコピーする。
4. このフォルダで `.env.example` を `.env` にコピーし、`TUNNEL_TOKEN=` の後ろに貼る。
5. 次の画面「Public Hostname」で：

| 項目 | 値 |
|---|---|
| Subdomain | `ntfy` |
| Domain | `takuya.win` |
| Service の Type | `HTTP` |
| Service の URL | `ntfy:80` |

## 3. 起動する

```
docker compose up -d
docker compose logs -f        # 止めるときは Ctrl+C（サーバーは動き続ける）
```

ブラウザで `https://ntfy.takuya.win/v1/health` を開いて `{"healthy":true}` と出れば、外からつながっている。

## 4. 利用者とトークンを作る

```
docker compose exec ntfy ntfy user add hijet          # パスワードを 2 回聞かれる
docker compose exec ntfy ntfy access hijet '*' rw      # すべてのトピックを読み書きできる
docker compose exec ntfy ntfy token add hijet          # tk_ で始まるトークンが出る。控えておく
```

## 5. ESP32 とダッシュボードの設定を変える

**ESP32（設定モードの画面）**

| 項目 | 値 |
|---|---|
| サーバー（状態・指示） | `https://ntfy.takuya.win` |
| アクセストークン | 手順 4 の `tk_…` |
| 通知だけ送るサーバー | `https://ntfy.sh` |
| そのサーバーのアクセストークン | 空 |
| 3 つのトピック | 今のままでよい |

**ダッシュボード（右上の「設定」）**

| 項目 | 値 |
|---|---|
| ntfy のサーバー（状態・指示） | `https://ntfy.takuya.win` |
| アクセストークン | 手順 4 の `tk_…` |
| 通知のサーバー | `https://ntfy.sh` |

ESP32 は、サーバーが ntfy.sh でないとき、自動で短い間隔（状態は 1 分ごと、指示は 15 秒ごと、追跡中は 30 秒ごと）になる。

## 機械が止まったら

状態と指示が止まる（ダッシュボードは「応答なし」になり、ボタンも効かない）。**通知は ntfy.sh 経由なので届き続ける。**
機械を再起動すれば、`restart: unless-stopped` で自動的に動き出す。

## 更新

```
docker compose pull && docker compose up -d
```
