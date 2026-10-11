#!/usr/bin/env python3
"""基板の部品から BOM（部品表 CSV）を作る。"""
import csv
import sys
from collections import OrderedDict

import pcbnew

# 値 → 購入時の説明
DESC = {
    "12V IN": "端子台 5.08mm 3P（Phoenix MKDS 1,5/3-5,08 互換）",
    "OUT": "端子台 3.5mm 8P（Phoenix PT 1,5/8-3,5-H 互換。2P×4 連結でも可）ピッチ 3.5mm（3.81/5.0mm 品は不可）",
    "AUX IN": "端子台 3.5mm 4P（Phoenix PT 1,5/4-3,5-H 互換）",
    "PTC 0.75A": "ポリスイッチ（リセッタブルヒューズ）保持電流 0.75A・耐圧 30V 以上・ラジアル 足の間隔 5.0〜5.1mm・本体幅 7.5mm 以下（例：Littelfuse RXEF075）",
    "1N5819": "ショットキーダイオード 40V 1A（DO-41、立てて実装）逆接保護。SB140 なども可",
    "P6KE22A": "TVS ダイオード 600W 22V 単方向 P6KE22A（DO-15、立てて実装）。末尾 A の単方向品",
    "100uF 50V": "電解コンデンサ 100µF 50V φ8mm 足の間隔 3.5mm（105℃品）",
    "100uF 16V": "電解コンデンサ 100µF 16〜25V φ6.3mm 足の間隔 2.5mm（105℃品）",
    "OKI-78SR-5/1.5-W36-C": "DC-DC 5V 1.5A Murata OKI-78SR-5/1.5-W36-C",
    "0.1uF": "積層セラミック 0.1µF(100nF/104) 50V X7R 足の間隔 2.5mm（5.0mm 品は不可）",
    "100k": "抵抗 100kΩ 1/4W（立てて実装）",
    "18k": "抵抗 18kΩ 1/4W（立てて実装）",
    "330": "抵抗 330Ω 1/4W（立てて実装）",
    "2.2k": "抵抗 2.2kΩ 1/4W（立てて実装）",
    "10k": "抵抗 10kΩ 1/4W（R15 だけ横置き、ほかは立てて実装）",
    "BAT85": "小信号ショットキー BAT85 または BAT43（DO-35）電圧測定入力のクランプ",
    "1N4148": "小信号ダイオード 1N4148（DO-35）入力の逆電圧保護・ブザーの逆起電力吸収",
    "PC817C": "フォトカプラ PC817C または PC817D（DIP-4）。ランク A・B は電流伝達率が低いので不可",
    "ESP32 VIN row": "ピンソケット 1×15 2.54mm 高さ 8.5mm（1×40 分割タイプから切り出し可）",
    "ESP32 3V3 row": "ピンソケット 1×15 2.54mm 高さ 8.5mm（1×40 分割タイプから切り出し可）",
    "I2C": "ピンヘッダー 1×4 2.54mm",
    "GPS": "ピンヘッダー 1×4 2.54mm（UART の GPS モジュール用）",
    "IN": "端子台 3.5mm 6P（Phoenix PT 1,5/6-3,5-H 互換。2P×3 連結でも可）ピッチ 3.5mm",
    "OBD-II CAN": "端子台 3.5mm 3P（Phoenix PT 1,5/3-3,5-H 互換）ピッチ 3.5mm",
    "MCP2562-E/P": "CAN トランシーバー MCP2562-E/P または MCP2562FD-E/P（DIP-8）。MCP2561 は 5 番ピンが違うので不可",
    "Buzzer 5V 12mm": "電子ブザー（自励式・発振回路内蔵）5V φ12mm 足の間隔 7.6mm（6.5mm 品は不可）＋側が長い足",
    "2SC1815": "NPN トランジスタ 2SC1815-GR または KSC1815（TO-92、足の並び E-C-B。並びが違う品は不可）",
    "1k": "抵抗 1kΩ 1/4W（立てて実装）",
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
