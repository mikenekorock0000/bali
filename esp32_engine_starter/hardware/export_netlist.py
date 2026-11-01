#!/usr/bin/env python3
"""基板からネットリスト（ネット → 部品のピン）と部品配置表を書き出す。回路図の代わりに検証用に使う。
  python3 export_netlist.py hijet_starter.kicad_pcb netlist.txt placement.csv
"""
import csv
import re
import sys
from collections import defaultdict

import pcbnew


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s)]


board = pcbnew.LoadBoard(sys.argv[1])
nets = defaultdict(list)
rows = []
for fp in board.GetFootprints():
    ref = fp.GetReference()
    pos = fp.GetPosition()
    rows.append([ref, fp.GetValue(), fp.GetFPID().GetLibItemName().wx_str(),
                 f"{pcbnew.ToMM(pos.x):.2f}", f"{pcbnew.ToMM(pos.y):.2f}", f"{fp.GetOrientationDegrees():.0f}",
                 "表面実装" if any(p.GetAttribute() == pcbnew.PAD_ATTRIB_SMD for p in fp.Pads()) else "リード"])
    for p in fp.Pads():
        if p.GetNetname():
            nets[p.GetNetname()].append(f"{ref}.{p.GetNumber()}({fp.GetValue()})")
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write("# HIJET MONITOR ネットリスト（基板データから自動生成）\n")
    f.write("# 形式: ネット名: 部品番号.ピン番号(値) ...\n")
    f.write("# J5 = ESP32 DevKit V1 の VIN 列（1 番がアンテナ側の EN、15 番が VIN）、J6 = 3V3 列（1 番が D23、15 番が 3V3）\n\n")
    for name in sorted(nets, key=natural):
        f.write(f"{name}: {' '.join(sorted(nets[name], key=natural))}\n")
with open(sys.argv[3], "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["部品番号", "値", "フットプリント", "X(mm)", "Y(mm)", "角度", "実装"])
    for r in sorted(rows, key=lambda r: natural(r[0])):
        w.writerow(r)
print("wrote", sys.argv[2], sys.argv[3])
