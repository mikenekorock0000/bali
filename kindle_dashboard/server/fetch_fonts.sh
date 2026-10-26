#!/bin/sh
# Noto Sans JP（可変ウェイト版, SIL OFL）を fonts/ にダウンロードする
set -e
cd "$(dirname "$0")"
mkdir -p fonts
curl -fL -o "fonts/NotoSansJP[wght].ttf" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
echo "fonts/NotoSansJP[wght].ttf を保存しました"
