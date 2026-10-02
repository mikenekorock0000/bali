#!/usr/bin/env python3
"""DRC を実行し、ライブラリ設定の警告以外が 1 件でもあれば失敗にする。"""
import re
import sys

import pcbnew

pcb, report = sys.argv[1], sys.argv[2]
board = pcbnew.LoadBoard(pcb)
pcbnew.WriteDRCReport(board, report, pcbnew.EDA_UNITS_MILLIMETRES, True)
text = open(report, encoding="utf-8").read()
issues = [l for l in text.splitlines() if l.startswith("[") and not l.startswith("[lib_footprint")]
unconnected = int(re.search(r"Found (\d+) unconnected", text).group(1))
print(f"DRC: {len(issues)} violations, {unconnected} unconnected")
for l in issues:
    print("  ", l)
sys.exit(1 if issues or unconnected else 0)
