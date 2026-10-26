#!/usr/bin/env python3
"""製造データの照合：ドリルファイルの穴数・穴径が基板と一致するか、外形が閉じているか。
  python3 check_fab.py hijet_starter.kicad_pcb gerber/
"""
import collections
import os
import re
import sys

import pcbnew

board = pcbnew.LoadBoard(sys.argv[1])
gdir = sys.argv[2]
errors = []

want = collections.Counter()
want_npth = collections.Counter()
for fp in board.GetFootprints():
    for p in fp.Pads():
        d = round(pcbnew.ToMM(p.GetDrillSize().x), 2)
        if d <= 0:
            continue
        (want_npth if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH else want)[d] += 1
for t in board.GetTracks():
    if t.GetClass() == "PCB_VIA":
        want[round(pcbnew.ToMM(t.GetDrillValue()), 2)] += 1


def read_drl(path):
    tools, cur, hits = {}, None, collections.Counter()
    for line in open(path):
        line = line.strip()
        m = re.match(r"^T(\d+)C([\d.]+)$", line)
        if m:
            tools[m.group(1)] = round(float(m.group(2)), 2)
            continue
        m = re.match(r"^T(\d+)$", line)
        if m:
            cur = m.group(1)
            continue
        if line.startswith("X") and cur:
            hits[tools[cur]] += 1
    return hits


got = read_drl(os.path.join(gdir, "hijet_starter-PTH.drl"))
got_npth = read_drl(os.path.join(gdir, "hijet_starter-NPTH.drl"))
for name, w, g in (("めっき穴", want, got), ("めっきなし穴", want_npth, got_npth)):
    print(f"{name}: " + ", ".join(f"φ{d}×{n}" for d, n in sorted(g.items())))
    if w != g:
        errors.append(f"{name}の数が基板と違う: 基板 {dict(w)} / ドリル {dict(g)}")
    for d in g:
        if d < 0.3:
            errors.append(f"{name} φ{d} は JLCPCB の最小穴径 0.3mm 未満")

edge = open(os.path.join(gdir, "hijet_starter-Edge_Cuts.gm1")).read()
pts = re.findall(r"X(-?\d+)Y(-?\d+)D0([12])\*", edge)
if not pts:
    errors.append("外形のガーバーに線がない")
names = [f for f in os.listdir(gdir)]
for need in ("F_Cu.gtl", "B_Cu.gbl", "F_Mask.gts", "B_Mask.gbs", "F_Silkscreen.gto", "Edge_Cuts.gm1", "PTH.drl"):
    if not any(n.endswith(need) for n in names):
        errors.append(f"{need} がない")
if any("drl_map" in n for n in names):
    errors.append("ドリルマップが入っている（発注サイトが層として読み込んでしまう）")
for e in errors:
    print("  NG  ", e)
print(f"製造データ: {len(errors)} 件の問題")
sys.exit(1 if errors else 0)
