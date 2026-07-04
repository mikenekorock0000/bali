#!/usr/bin/env bash
# バージョン付きファイル名で release APK を dist/ に配置する。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
OUT_NAME="madamis-gm-v${VERSION}.apk"

echo "==> Building release APK (version ${VERSION})..."
bash tool/patch_wifi_iot.sh
flutter build apk --release

mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk "dist/${OUT_NAME}"
cp "dist/${OUT_NAME}" dist/madamis-gm-release.apk

echo ""
echo "Built:"
ls -lh "dist/${OUT_NAME}"
echo "Also copied to dist/madamis-gm-release.apk"
