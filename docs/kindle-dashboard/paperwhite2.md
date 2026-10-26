# 第6世代 Kindle（Kindle Paperwhite 2 / 2013年）でダッシュボードを作る具体手順

> 調査日: 2026-10-26。全体像・一般論は [README.md](README.md) を参照。ここでは **第6世代 = Kindle Paperwhite（2013, 通称 PW2）** に絞った手順をまとめる。
> ⚠️ 脱獄は自己責任（保証外・文鎮化リスクあり）。

## 0. 機種の確認

- Amazon の「第6世代」は **Kindle Paperwhite（2013年モデル, PW2）**。前面に「kindle」ロゴ、背面に「amazon」ロゴがあり、フロントライト付き。
  - 2012年の初代 Paperwhite（第5世代）と見た目がほぼ同じなので、**設定 → 端末オプション → 端末情報**で確認する。
- 画面: 6インチ **758 × 1024 px**（212ppi）、16階調グレー。横置きなら **1024 × 758** でデザインして 90° 回転して配信する。
- CPU 1GHz / RAM 256MB。描画は重いので **画像はすべてサーバーで作る**方式が必須。
- Wi-Fi は **2.4GHz のみ・WPA2 まで**（5GHz・WPA3 専用の SSID には繋がらない）。

## 1. ファームウェアを確認

設定 → 端末オプション → 端末情報。PW2 の**最終ファームウェアは 5.12.2.2**（以降の更新は出ていない）。

- 5.12.2.2 なら → **WinterBreak2** が使える（2026年6月に PW2 5.12.2.2 での成功記録あり）。
- それより古い版でも基本は同じ。迷ったら **[KindleModding の Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html)** に機種と版を入れて、表示されたルートに従う（一次情報が正）。

> 補足: Amazon は 2026/5/20 に「2012年以前発売の Kindle」の Kindle ストア対応を終了した（初代 Paperwhite などが対象）。**PW2（2013年）は対象外**。また WinterBreak2 はストアではなく**実験的ブラウザ**を使うので、ストアの有無は関係ない。

## 2. 脱獄（WinterBreak2）

1. **USB データ通信できるケーブル**で PC に接続（充電専用ケーブルだと認識されない）。
2. 念のため Kindle 内の見えるファイルを PC にバックアップ。
3. [WinterBreak2 のページ](https://kindlemodding.org/jailbreaking/WinterBreak2/) から最新リリースをダウンロードし、**中身を Kindle のルートに展開コピー**（記録例では `jb.sh`, `patchedUks.sqsh`, `winterbreak2/` が並ぶ）。
   - 空き容量が少ないと失敗するので、本などを消して余裕を作っておく。
4. Kindle を取り外す（画面の「切断」）。
5. Kindle で **Wi-Fi に接続** → **実験的ブラウザ（体験版ブラウザ）**を開く → WinterBreak2 のページ（手順書に記載の URL）を開き **Jailbreak ボタン**を押す。
6. 完了表示を待ったら **すぐ機内モード ON**（以後、作業中は基本 OFF にしない）。
7. 再度 PC に接続。`update.bin.tmp.partial` があれば削除。ルートの `winterbreak.log` に「jailbreak finished / hotfix is required next」とあれば成功。

## 3. 脱獄後の作業

1. **Hotfix**: [Update_hotfix_universal.bin](https://github.com/KindleModding/Hotfix/releases/latest/download/Update_hotfix_universal.bin) をルートへ → 取り外し → 設定 → メニュー → **Kindle をアップデート** → 再起動後ライブラリの **Run Hotfix** を開く。
2. **ランチャー**（どちらか）
   - 従来: MRPI + KUAL。MRPI の `extensions` / `mrpackages` をルートへ、`Update_KUALBooklet_HDRepack.bin` を `mrpackages` へ → 検索バーで **`;log mrpi`** → ライブラリに KUAL。空き容量が **約 220MB** 必要。
   - 新しい流れ: KindleModding は現在 **KPM（パッケージマネージャ）と Scriptlets** を推奨し、KUAL は「古い」扱い。[What's next](https://kindlemodding.org/jailbreaking/whats-next/) のページに従ってもよい。どちらでもダッシュボード用スクリプトは起動できる。
3. **OTA 停止**: PW2 は 5.12.2.2 以降の配信がないので実害は小さいが、WinterBreak 系は OTA ブロック済み。念のためルートの `.bin` は消しておく。
4. **SSH（強く推奨）**: KUAL の USBNetwork、または KOReader の SSH サーバーで `ssh root@<KindleのIP>` できるようにする。以降の調整がずっと楽になる。
5. **FBInk（推奨）**: PW2 は標準の `eips -g` でも PNG 表示できるが、FBInk のほうがリフレッシュ制御・回転が確実。
6. （任意）**KOReader**: `kindlepw2` パッケージが PW2 用（FW 5.16.2.1.1 以下）。TRMNL プラグインで手軽にやるならこれ。

## 4. サーバー側（PW2 向けの設定値）

[README.md §3](README.md#3-サーバー側-ダッシュボード画像を作る) の通り。PW2 用の値だけ抜き出す:

```bash
# 横置き（写真と同じ向き）でデザイン → 縦 758x1024 に回転して配信
npx playwright screenshot --viewport-size=1024,758 http://localhost:3000/dashboard shot.png
convert shot.png -rotate 90 -colorspace Gray -alpha off -depth 8 dash.png
file dash.png   # → PNG image data, 758 x 1024, 8-bit grayscale であること
```

- 回転方向（90 / 270）は Kindle をスタンドに置く向きに合わせて実機で確認。
- PW2 は 212ppi なので、写真の大時計クラスは 150px 前後、本文は 18〜22px 以上が読みやすい目安。
- 配信は LAN 内 **HTTP** 推奨（PW2 内蔵の wget は古く、最近の HTTPS サイトに繋がらないことが多い）。

## 5. Kindle 側（PW2）

[README.md §4-2](README.md#4-2-自作する場合の最小スクリプト考え方) のスクリプトをそのまま使える。PW2 での要点:

- 画面占有: `stop lab126_gui`（5.x 系の upstart）。戻すときは `start lab126_gui`。
- スリープ防止: `lipc-set-prop com.lab126.powerd preventScreenSaver 1`（終了時 0）。
- 表示: `eips -g /tmp/dash.png`（部分）/ `eips -f -g /tmp/dash.png`（全面）。FBInk があれば `fbink -g file=...` / `fbink -c -g file=...`。
- **フロントライトを 0 に**（常時表示で無駄に光らせない）: 設定画面で最小にするか `lipc-set-prop com.lab126.powerd flIntensity 0`。
- 電池残量: `lipc-get-prop com.lab126.powerd battLevel` → 画像取得時に `?battery=` で送り、写真の「Kindle 96%」欄に出す。
- 既製品を使うなら **[J105588/kindle_dashboard](https://github.com/J105588/kindle_dashboard)**（日本語・第7世代向け。PW2 は同世代の i.MX6SL 機でほぼ同じ作り。`device` 設定にない解像度 758×1024 を追加する必要あり）や **[pascalw/kindle-dash](https://github.com/pascalw/kindle-dash)**（RTC サスペンドのパスは機種依存なので、まずは給電＋常時起動で使う）。

## 6. 電源・設置

- PW2 の電池（約 1420mAh）は経年劣化していることが多い。**毎分更新なら USB 常時給電**が前提。
- 常時給電でも、終日起動ならフロントライト 0・全面リフレッシュは 10〜15 回に 1 回程度で十分。
- 横置きスタンド＋ L 字 USB ケーブルだと写真のような見た目になる。

## 7. つまずきポイント（PW2 で報告があったもの）

| 症状 | 対処 |
|---|---|
| PC に Kindle が出てこない | 充電専用ケーブル / USB ハブ / リモートデスクトップ越しを疑う。直挿しで試す |
| ブラウザ経由の脱獄が途中で止まる | 空き容量を増やす。機内モード→Wi-Fi の順を手順書通りに。Wizard で最新ルートを再確認 |
| LanguageBreak（古いルート）で言語選択ステップから進まない | PW2 5.12.2.2 で報告あり（GitHub issue）。WinterBreak2 を使う |
| MRPI が動かない | 空き容量 220MB 以上を確保 |
| HTTPS の画像が取れない | LAN 内 HTTP 配信にする |

## 参考

- [KindleModding Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html) / [WinterBreak2](https://kindlemodding.org/jailbreaking/WinterBreak2/) / [What's next（KPM・Scriptlets）](https://kindlemodding.org/jailbreaking/whats-next/)
- [PW2 5.12.2.2 の脱獄・KOReader 導入記録（lachlanchen/Kindle, 2026-06）](https://github.com/lachlanchen/Kindle/blob/main/docs/paperwhite2-5.12.2.2-koreader-jailbreak.md)
- [jailbreaking a kindle paperwhite 2 in 2025（Technically Competent）](https://technicallycompetent.com/blog/kindle-pw2-2025/)
- [LanguageBreak issue #60: PW 6th gen 5.12.2.2](https://github.com/notmarek/LanguageBreak/issues/60)
- [Kindle Jailbreak Compatibility Check（BookFere）](https://en.bookfere.com/post/jailbreak-compatibility-check.html)
- [Amazon の旧 Kindle サポート終了（対象機種一覧, TechRepublic）](https://www.techrepublic.com/article/news-amazon-ends-support-older-kindles-2026/)
