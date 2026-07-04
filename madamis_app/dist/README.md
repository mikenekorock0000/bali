# 実機用 APK

| ファイル | 説明 |
|---------|------|
| **`madamis-gm-v1.1.0+4.apk`** | **最新** — WebView 全ボタン修正・自動テスト同梱（v1.1.0+4） |
| `madamis-gm-release.apk` | 上記と同一内容（互換用の固定名） |

## バージョン確認

インストール後、アプリ **設定** 画面の先頭に `1.1.0+4` と表示され、
**「プレイヤーシミュレーター / 全自動テスト」** 項目があれば最新版です。

## インストール

```bash
adb install -r madamis-gm-v1.1.0+4.apk
```

または APK をタブレットにコピーしてタップ（「提供元不明のアプリ」を許可）。
古い版は上書きインストール（`-r`）を推奨。

## 再ビルド

```bash
cd madamis_app
bash tool/build_release_apk.sh
```

`pubspec.yaml` の `version:` に合わせて `dist/madamis-gm-v<version>.apk` が生成されます。
