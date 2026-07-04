# マダミス GM アプリ

TOTEM型の対面マーダーミステリー自動進行アプリ（Flutter）

## 概要

Androidタブレットを親機（GM）として、プレイヤーはブラウザでQR参加する対面マダミスアプリ。

- **親機**: Flutter Androidアプリ（WiFiホットスポット + 内蔵Webサーバー）
- **参加者**: ブラウザのみ（アプリ不要）
- **進行**: 全自動（GM不要）
- **AI**: Gemini 2.0 Flash によるシナリオ自動生成
- **デモ**: 固定シナリオ + 保存シナリオ6本（2〜8人）

## 保存シナリオ

ホーム画面「保存シナリオ」からAI生成済みシナリオを選んでプレイできます。

| 人数 | タイトル | モード |
|------|---------|--------|
| 2人 | 白銀の密室 | 協力 |
| 3人 | 凍結の書斎 | 協力 |
| 4人 | 白銀の密室 | 対立 |
| 6/7/8人 | 白雪の密室 他 | 対立 |

## ドキュメント

- [詳細設計書](../docs/DESIGN.md)

## セットアップ

```bash
cd madamis_app
flutter pub get
flutter run
```

## AIシナリオ生成

1. 設定画面で [Google AI Studio](https://aistudio.google.com/apikey) の Gemini APIキーを保存
2. 「AIでシナリオ生成」→ ジャンル・難易度・時間・人数・テーマを設定
3. 生成完了後、ロビー画面へ自動遷移

生成パイプライン:
1. 世界観・事件設定
2. 登場人物・役割
3. 台本・手がかり
4. 整合性チェック（9項目）
5. 正解ルート検証（Gemini）
6. シナリオ完成（最大5回リトライ）

## 遊び方（MVP）

1. タブレットでアプリを起動
2. 「保存シナリオ」・「AIでシナリオを作る」・またはデモを選択
3. ロビー画面のQRコードをプレイヤーがスマホで読み取り
3. 各プレイヤーがニックネーム入力（配役は自動割り当て）
4. 全員参加後、タブレットで「ゲーム開始」
5. 自動進行: あらすじ → 個人台本 → 調査 → 議論 → 投票 → 真相

## 開発フェーズ

| Phase | 状態 | 内容 |
|-------|------|------|
| 1 MVP | ✅ | 通信基盤 + 固定シナリオ + TOTEM進行 |
| 2 | ✅ | Gemini連携・シナリオ自動生成 + 整合性検証 |
| 3 | ✅ | 2-3人協力推理モード + 検証強化 |
| 4 | ✅ | WiFiホットスポット + IP検出 |
| 5 | ✅ | BGM/SE、中断再開（SQLite） |
| + | ✅ | 保存シナリオ選択プレイ、UI改善、ジャンル別テーマ |

## テスト

```bash
flutter test
dart run tool/generate_test.dart          # 4人（要 GEMINI_API_KEY）
dart run tool/generate_test.dart --players=2
```

## 実機用 APK（ダウンロード）

**`dist/madamis-gm-v1.1.0+5.apk`** — main ブランチの最新 Android 向けビルド（v1.1.0+5）

`dist/madamis-gm-release.apk` は同じ内容の固定名です。

```bash
adb install -r dist/madamis-gm-v1.1.0+5.apk
```

設定画面でバージョン `1.1.0+5` と「プレイヤーシミュレーター」項目を確認してください。

## APKビルド（Android実機向け）

```bash
cd madamis_app
bash tool/build_release_apk.sh
```

`pubspec.yaml` の `version` に合わせて `dist/madamis-gm-v<version>.apk` を生成し、`dist/madamis-gm-release.apk` も更新します。**main にコミットして常に最新を置く。**

> release ビルドは現在 debug キーで署名されています（実機テスト用）。

## 音声アセット

```bash
bash tool/generate_audio.sh   # BGM/SEプレースホルダー再生成
```

## 技術スタック

- Flutter (Dart 3.x)
- shelf (HTTP/WebSocket サーバー)
- provider (状態管理)
- google_generative_ai (Gemini API)
- shared_preferences (APIキー保存)
