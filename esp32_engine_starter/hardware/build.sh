#!/usr/bin/env bash
# 基板データ一式を作る：生成 → DRC → ガーバー/ドリル → zip → BOM → プレビュー画像
set -euo pipefail
cd "$(dirname "$0")"
python3 gen_pcb.py
python3 drc_check.py hijet_starter.kicad_pcb drc_report.txt
rm -rf gerber && mkdir gerber
kicad-cli pcb export gerbers -o gerber/ \
  -l F.Cu,B.Cu,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts \
  --subtract-soldermask hijet_starter.kicad_pcb
kicad-cli pcb export drill -o gerber/ --excellon-separate-th \
  hijet_starter.kicad_pcb
rm -f hijet_starter_gerber.zip
(cd gerber && zip -q ../hijet_starter_gerber.zip *)
python3 bom.py hijet_starter.kicad_pcb bom.csv
# 原寸印刷用（実物の DevKitC や部品を当てて穴位置を確認する）
kicad-cli pcb export pdf -l F.Cu,F.SilkS,Edge.Cuts --black-and-white \
  -o hijet_starter_1to1.pdf hijet_starter.kicad_pcb
./render.sh preview
ls gerber
