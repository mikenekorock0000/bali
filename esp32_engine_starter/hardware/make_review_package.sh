#!/usr/bin/env bash
# 第三者検証用の一式（技術説明書・図面・ネットリスト・製造データ・スクリプト・ファームウェア）を ZIP にまとめる
#   ./make_review_package.sh [出力ファイル]
set -euo pipefail
cd "$(dirname "$0")"
OUT=$(realpath -m "${1:-../hijet_monitor_review.zip}")
PCB=hijet_starter.kicad_pcb
TMP=$(mktemp -d)
P="$TMP/hijet_monitor_review"
mkdir -p "$P"/{drawings,hardware/reports,fabrication,kicad,scripts/sim,firmware}

python3 export_netlist.py "$PCB" netlist.txt placement.csv
python3 export_jlc.py "$PCB" jlc_bom.csv jlc_cpl.csv
cp ../TECHNICAL.md "$P/"
cp preview/top.png preview/bottom.png hijet_starter_1to1.pdf "$P/drawings/"
kicad-cli pcb export pdf -l F.Cu,Edge.Cuts --black-and-white -o "$P/drawings/F_Cu.pdf" "$PCB" >/dev/null
kicad-cli pcb export pdf -l B.Cu,Edge.Cuts --black-and-white --mirror -o "$P/drawings/B_Cu.pdf" "$PCB" >/dev/null
kicad-cli pcb export pdf -l F.SilkS,F.Fab,Edge.Cuts --black-and-white -o "$P/drawings/assembly.pdf" "$PCB" >/dev/null
cp netlist.txt placement.csv bom.csv README.md VERIFICATION.md "$P/hardware/"
cp jlc_bom.csv jlc_cpl.csv "$P/fabrication/"
cp drc_report.txt pins_report.txt mech_report.txt sim_report.txt fab_report.txt "$P/hardware/reports/"
cp hijet_starter_gerber.zip "$P/fabrication/"
cp "$PCB" hijet_starter.kicad_pro "$P/kicad/"
cp -r footprints.pretty "$P/kicad/"
cp gen_pcb.py check_pins.py check_mech.py check_fab.py drc_check.py bom.py export_netlist.py export_jlc.py build.sh render.sh "$P/scripts/"
cp sim/*.cir sim/*.lib sim/*.py sim/*.sh "$P/scripts/sim/"
cp -r ../src ../lib ../test ../platformio.ini ../README.md "$P/firmware/"
rm -f "$P/firmware/src/secrets.h"  # 個人の Wi-Fi・ntfy の設定は含めない
rm -f "$OUT"
(cd "$TMP" && zip -qr "$OUT" hijet_monitor_review)
rm -rf "$TMP"
echo "wrote $OUT"
