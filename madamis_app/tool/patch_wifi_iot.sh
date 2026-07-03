#!/usr/bin/env bash
# wifi_iot 0.3.19+2 の古い Gradle 設定を修正（jcenter / buildscript 除去）
set -euo pipefail

CACHE_ROOT="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev"
TARGET=$(find "$CACHE_ROOT" -maxdepth 1 -type d -name 'wifi_iot-*' | head -n 1)

if [ -z "$TARGET" ]; then
  echo "wifi_iot not found in pub cache. Run 'flutter pub get' first."
  exit 1
fi

cat > "$TARGET/android/build.gradle" <<'EOF'
group 'com.alternadom.wifiiot'
version '1.0-SNAPSHOT'

apply plugin: 'com.android.library'

android {
    namespace 'com.alternadom.wifiiot'

    compileSdkVersion 35

    defaultConfig {
        minSdkVersion 21
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }
    lintOptions {
        disable 'InvalidPackage'
    }
}
EOF

echo "Patched $TARGET/android/build.gradle"
