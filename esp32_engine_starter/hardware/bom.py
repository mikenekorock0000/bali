#!/usr/bin/env python3
"""基板の部品から BOM（部品表 CSV）を作る。"""
import csv
import sys
from collections import OrderedDict

import pcbnew

# 値 → 購入時の説明
DESC = {
    "12V IN": "端子台 5.08mm 3P（Phoenix MKDS 1,5/3-5,08 互換）",
    "REMOTE OUT": "端子台 3.5mm 8P（Phoenix PT 1,5/8-3,5-H 互換）",
    "AUX IN": "端子台 3.5mm 4P（Phoenix PT 1,5/4-3,5-H 互換）",
    "Mini blade 1A": "ミニ平型ヒューズホルダー Keystone 3568 ＋ ミニ平型ヒューズ 1A",
    "1N5819": "ショットキーダイオード 40V 1A（DO-41）逆接保護",
    "P6KE22A": "TVS ダイオード 600W 22V 単方向（DO-15）",
    "100uF 50V": "電解コンデンサ 100µF 50V φ8 ピッチ3.5mm（105℃品）",
    "100uF 16V": "電解コンデンサ 100µF 16V以上 φ6.3 ピッチ2.5mm（105℃品）",
    "OKI-78SR-5/1.5-W36-C": "DC-DC 5V 1.5A Murata OKI-78SR-5/1.5-W36-C",
    "0.1uF": "積層セラミック 0.1µF(100nF/104) 50V X7R ピッチ2.5mm",
    "100k": "抵抗 100kΩ 1/4W",
    "22k": "抵抗 22kΩ 1/4W",
    "470": "抵抗 470Ω 1/4W",
    "2.2k": "抵抗 2.2kΩ 1/4W",
    "10k": "抵抗 10kΩ 1/4W",
    "BAT85": "小信号ショットキー BAT85（DO-35）電圧測定入力のクランプ",
    "1N4148": "小信号ダイオード 1N4148（DO-35）入力の逆電圧保護",
    "PC817C": "フォトカプラ PC817C（DIP-4）",
    "ESP32 J1": "ピンソケット 1×19 2.54mm（ESP32-DevKitC 用）",
    "ESP32 J3": "ピンソケット 1×19 2.54mm（ESP32-DevKitC 用）",
    "I2C": "ピンヘッダー 1×4 2.54mm",
}

board = pcbnew.LoadBoard(sys.argv[1])
groups = OrderedDict()
for fp in sorted(board.GetFootprints(), key=lambda f: f.GetReference()):
    if fp.GetReference().startswith("H"):
        continue
    groups.setdefault(fp.GetValue(), []).append(fp.GetReference())
with open(sys.argv[2], "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["数量", "部品番号", "値", "内容"])
    for value, refs in groups.items():
        # ESP32 用ソケットは 1 行にまとめる
        w.writerow([len(refs), " ".join(refs), value, DESC.get(value, "")])
print("wrote", sys.argv[2])
