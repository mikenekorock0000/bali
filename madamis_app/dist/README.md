# 実機用 APK

| ファイル | 説明 |
|---------|------|
| `madamis-gm-release.apk` | Android タブレット向けリリースビルド（マダミス GM） |

## インストール

```bash
adb install madamis-gm-release.apk
```

または APK をタブレットにコピーしてタップ（「提供元不明のアプリ」を許可）。

## 再ビルド

```bash
cd madamis_app
flutter pub get
bash tool/patch_wifi_iot.sh
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk dist/madamis-gm-release.apk
```
