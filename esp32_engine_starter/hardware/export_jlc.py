#!/usr/bin/env python3
"""JLCPCB の組立サービス形式の BOM と CPL（部品配置リスト）を書き出す。
この基板は手はんだ前提（部品は秋月電子）なので、LCSC の部品番号は空欄。組立を頼むときは埋めること。
座標は基板の左下を原点、上向きを +Y とする（JLCPCB の形式）。回転角は JLCPCB の画面で向きを確認すること。
  python3 export_jlc.py hijet_starter.kicad_pcb jlc_bom.csv jlc_cpl.csv
"""
import csv
import re
import sys
from collections import OrderedDict

import pcbnew

SKIP = {"J5", "J6"}  # ESP32 DevKit のピン（DevKit は自分で付ける）


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


board = pcbnew.LoadBoard(sys.argv[1])
bb = board.GetBoardEdgesBoundingBox()
x0, y1 = bb.GetX(), bb.GetY() + bb.GetHeight()
fps = sorted((f for f in board.GetFootprints()
              if not f.GetReference().startswith("H") and f.GetReference() not in SKIP),
             key=lambda f: natural(f.GetReference()))
groups = OrderedDict()
for f in fps:
    key = (f.GetValue(), f.GetFPID().GetLibItemName().wx_str())
    groups.setdefault(key, []).append(f.GetReference())
with open(sys.argv[2], "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
    for (val, fpn), refs in groups.items():
        w.writerow([val, ",".join(refs), fpn, ""])
with open(sys.argv[3], "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    for f in fps:
        p = f.GetPosition()
        w.writerow([f.GetReference(), f"{pcbnew.ToMM(p.x - x0):.3f}mm", f"{pcbnew.ToMM(y1 - p.y):.3f}mm",
                    "Top", f"{f.GetOrientationDegrees() % 360:.0f}"])
print("wrote", sys.argv[2], sys.argv[3])
