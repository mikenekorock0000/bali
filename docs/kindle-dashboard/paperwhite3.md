# Kindle Paperwhite 第7世代（PW3）でダッシュボードを作る具体手順

> 調査日: 2026-10-26。全体像・一般論は [README.md](README.md)。
> 対象: **Kindle Paperwhite（第7世代・2015年, 通称 PW3）／ファームウェア 5.15.1**（Wi-Fi + 3G モデル）。
> ⚠️ 脱獄は自己責任（保証外・文鎮化リスクあり）。

## 0. この端末の前提

| 項目 | 内容 |
|---|---|
| 機種 | Kindle Paperwhite 第7世代（設定 → 端末オプション → 端末情報 に「第7世代」と表示） |
| 画面 | 6インチ **1072 × 1448 px**（300ppi）、16 階調。横置きなら **1448 × 1072** で作って 90° 回転 |
| ファームウェア | **5.15.1**（2026-10-26 に自動アップデートが始まった。PW3 の最終版は **5.16.2.1.1**） |
| 通信 | Wi-Fi（2.4GHz・WPA2 まで）。3G は国内の 3G 停波で使えないが、ダッシュボードには関係ない |
| Amazon のサポート | 2026/5 のストア対応終了は「2012年以前の機種」が対象。PW3（2015年）は対象外 |

サーバー側（`kindle_dashboard/server`）は既定でこの解像度（`display.width: 1448, height: 1072`）で描く。

## 1. 脱獄の前に

- **充電しておく**（50% 以上推奨。作業中に電池切れで止まるのが一番危ない）。
- **機内モードを ON**。勝手にファームウェアが上がると、使える脱獄方法が変わる（下記の範囲から外れる）ことがある。
- 空き容量は 750MB 程度あれば十分（KUAL/MRPI の導入に約 220MB 必要）。
- まず **[KindleModding の Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html)** に機種とファームウェアを入れ、出てきた方法を確認する（一次情報が正）。

## 2. 使える脱獄方法（5.15.1 / 5.16.2.1.1 の場合）

> **自動アップデートについて**: Wi-Fi に繋いでいると Amazon から更新が自動で入る。PW3 の最終ファームウェアは
> **5.16.2.1.1**（2023年）で、これ以上新しい版は出ていないため、更新されても下の 2 つの方法の範囲内に収まる。
> **インストール中は電源を切らない**こと（充電しながら待つ）。終わったら版を確認し、すぐ機内モードを ON にする。

| 方法 | 対応範囲 | 位置づけ |
|---|---|---|
| **WinterBreak** | 5.18.1 より前（Paperwhite 2 以降の機種） | **第一候補**。Kindle ストア（Mesquito）経由 |
| **LanguageBreak** | 5.16.2.1.1 以下 | WinterBreak がうまくいかないときの代替。デモモードと言語選択を使う |

※ 5.15.1・5.16.2.1.1 とも両方の範囲内（5.16.2.1.1 は LanguageBreak の上限ちょうど）。WinterBreak は Kindle ストアを開く必要があるので、**端末が Amazon アカウントに登録済み**であること。

### WinterBreak の手順

1. [WinterBreak.tar.gz](https://github.com/KindleModding/WinterBreak/releases/latest/download/WinterBreak.tar.gz) を PC にダウンロードして展開。
2. Kindle を **機内モード ON** → 設定 → 端末オプション → **再起動**。
3. USB で PC に接続し、展開したファイルを**すべて Kindle のルートへコピー**（上書き可）。
   Mac/Linux は隠しフォルダ `.active_content_sandbox` もコピーされているか確認。
4. Kindle 画面で「切断」→ **Kindle ストア（カートのアイコン）**を開く。機内モード解除を促されたら解除。
5. ストアが読み込み直されたら **WinterBreak のアイコン**をタップ。
   - 出ないとき: KindleModding の FAQ の手順（`LocalStorage`・`ku`・`mfa` フォルダの削除、工場出荷リセット後サインイン前にコピー、など）。
6. 約 30 秒で「**Finished installing jailbreak**」→ **機内モード ON に戻す**。

うまくいかなければ [LanguageBreak](https://kindlemodding.org/jailbreaking/Legacy/LanguageBreak.html) の手順へ。

## 3. 脱獄後の作業

1. **Hotfix**: [Update_hotfix_universal.bin](https://github.com/KindleModding/Hotfix/releases/latest/download/Update_hotfix_universal.bin) をルートへ（他の `.bin` は削除）→ 取り外し → 設定 → メニュー → **Kindle をアップデート** → 再起動後ライブラリの **Run Hotfix** を開く。
2. **KUAL と MRPI**: [kual-mrinstaller-khf](https://fw.notmarek.com/khf/kual-mrinstaller-khf.tar.xz) の `extensions` と `mrpackages` をルートへ、
   KUAL（6 世代以降用の `Update_KUALBooklet_HDRepack.bin`）を `mrpackages` へ → 取り外して検索バーに **`;log mrpi`** → ライブラリに KUAL が出る。
   （KindleModding は現在 KPM・Scriptlets も案内している。どちらでもダッシュボードは起動できる）
3. **OTA（自動アップデート）**: WinterBreak で脱獄した場合はブロック済み。LanguageBreak の場合は `renameotabin` 拡張で無効化。
4. **SSH（推奨）**: USBNetwork を入れて `ssh root@<KindleのIP>` できるようにすると、設定変更や不具合調査が楽。
5. **FBInk（推奨）**: 標準の `eips` でも表示できるが、FBInk のほうがリフレッシュ制御が確実。

## 4. ダッシュボードを入れる

[kindle_dashboard/README.md](../../kindle_dashboard/README.md) の「2. Kindle に入れる」の通り。

1. `kindle_dashboard/kindle/extensions/dashboard` を Kindle の `extensions/` にコピー。
2. `config.sh` の `SERVER_URL` を `http://<NASのIP>:8080/dash.png` に（**LF 改行で保存**）。
3. Wi-Fi を ON（機内モード OFF）にして、KUAL → Dashboard → **Test** → 画像が出たら **Start**。

PW3 向けのポイント:

- 画面いっぱいに出ない・ずれる → サーバーの `config.json` の `display` が `1448 x 1072` になっているか確認。
- 上下逆さま → `display.rotate` を `270` に。
- 毎分更新なら **USB 給電しっぱなし**（電池が古いので）。フロントライトは `config.sh` の `FRONTLIGHT=0` で消灯。
- 表示が Kindle の画面に上書きされる → `config.sh` の `STOP_MODE=stop` を試す。

## 参考

- [KindleModding – Jailbreak Wizard](https://kindlemodding.org/jailbreak-wizard.html) / [WinterBreak](https://kindlemodding.org/jailbreaking/WinterBreak/) / [LanguageBreak](https://kindlemodding.org/jailbreaking/Legacy/LanguageBreak.html)
- [MobileRead: Introducing WinterBreak](https://www.mobileread.com/forums/showthread.php?p=4512798)（5.16.3 で不具合報告あり。5.15.1 は対応範囲内）
- [MobileRead: LanguageBreak](https://www.mobileread.com/forums/showthread.php?t=356872)
- [Android Police: WinterBreak（2013年以降の機種に対応）](https://www.androidpolice.com/new-kindle-jailbreak-2025-winterbreak/)
- [endoflife.date – Kindle（PW3 の最終版 5.16.2.1.1）](https://endoflife.date/kindle) / [LanguageBreak は 5.16.2.1.1 以下に対応（Liliputing）](https://liliputing.com/languagebreak-jailbreak-released-for-recent-kindle-devices-running-software-versions-5-16-2-1-1-or-lower/)
- [Amazon の旧 Kindle サポート終了（対象機種一覧, TechRepublic）](https://www.techrepublic.com/article/news-amazon-ends-support-older-kindles-2026/)
