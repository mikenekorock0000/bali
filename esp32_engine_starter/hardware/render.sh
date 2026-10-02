#!/usr/bin/env bash
# 基板のプレビュー画像を出力する（KiCad の SVG を Chromium で PNG 化）
#   ./render.sh <出力ディレクトリ>
set -euo pipefail
cd "$(dirname "$0")"
OUTDIR=${1:-preview}
mkdir -p "$OUTDIR"
CHROME=${CHROME:-$(ls -d /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)}
PCB=hijet_starter.kicad_pcb
# レイヤーごとに SVG を出し、色を付けて重ねる
declare -A COLOR=( [B.Cu]="#3d6fb6" [F.Cu]="#c8492f" [F.SilkS]="#f2f2f2" [Edge.Cuts]="#e6c229" [F.Fab]="#9ad0ff" )
render() {  # name, layers...
  local name=$1; shift
  local html="$OUTDIR/$name.html"
  echo '<html><body style="margin:0;background:#15391f"><div style="position:relative;width:2000px;height:1700px">' > "$html"
  for l in "$@"; do
    local f="$OUTDIR/${name}_${l//./_}.svg"
    kicad-cli pcb export svg -l "$l,Edge.Cuts" --page-size-mode 2 --exclude-drawing-sheet --black-and-white -o "$f" "$PCB" >/dev/null
    sed -i "s/#000000/${COLOR[$l]}/g; s/fill-opacity:1.0000/fill-opacity:0.85/g" "$f"
    echo "<img src=\"$(basename "$f")\" style=\"position:absolute;left:0;top:0;width:2000px\">" >> "$html"
  done
  echo '</div></body></html>' >> "$html"
  "$CHROME" --headless --no-sandbox --disable-gpu --hide-scrollbars --window-size=2000,1700 \
    --screenshot="$OUTDIR/$name.png" "file://$(realpath "$html")" >/dev/null 2>&1
  rm -f "$html" "$OUTDIR/${name}_"*.svg
}
render top B.Cu F.Cu F.SilkS
render bottom B.Cu

echo "wrote $OUTDIR/top.png"
