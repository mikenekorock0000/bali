#!/usr/bin/env python3
"""基板の部品から BOM（部品表 CSV）を作る。購入先は原則として秋月電子通商（URL は商品ページ）。"""
import csv
import re
import sys
from collections import OrderedDict

import pcbnew

AKI = "https://akizukidenshi.com/catalog/g/g{}/"

# 値 → (購入時の説明, 買う単位（部品番号 1 つあたり）, 購入先, URL)
# 買う単位：数値なら 部品数 × その数。文字列ならそのまま（抵抗は 100 本入り 1 袋など）
DESC = {
    "12V IN": ("端子台 3P 5.08mm TB112-2-3-E-1（ねじが上、電線は横から入るタイプ）", 1, "秋月", AKI.format("101310")),
    "OUT": ("端子台 2P 5.08mm TB112-2-2-E-1 を 4 個連結して 8P にする（電線は横から入るタイプ）", 4, "秋月", AKI.format("101308")),
    "IN": ("端子台 2P 5.08mm TB112-2-2-E-1 を 3 個連結して 6P にする", 3, "秋月", AKI.format("101308")),
    "OBD-II CAN": ("端子台 3P 5.08mm TB112-2-3-E-1", 1, "秋月", AKI.format("101310")),
    "PTC 1.1A": ("リセッタブルヒューズ Bourns MF-RX110/72（保持 1.1A・トリップ 2.2A・72V、幅 10.8mm・足 0.81mm・間隔 5.1mm）。"
                 "Littelfuse RXEF110（秋月 101356）でも可。RUEF 系（30V）は不可", 1, "秋月", AKI.format("113585")),
    "SB340LS": ("ショットキーダイオード SB340LS 40V 3A（DO-15、立てて実装）逆接保護", 1, "秋月", AKI.format("107788")),
    "P6KE20A": ("TVS ダイオード P6KE20A 600W 単方向（DO-15、立てて実装）。秋月に 20V 前後の TVS がないため DigiKey などで買う。"
                "P6KE22A も可（クランプ 30.6V で DC-DC の上限 32V 以内）", 1, "DigiKey",
                "https://www.digikey.com/en/products/detail/littelfuse-inc/P6KE20A/285930"),
    "100uF 50V": ("電解コンデンサ 100µF 50V φ8mm 足の間隔 3.5mm（105℃、Rubycon PX）", 1, "秋月", AKI.format("117905")),
    "100uF 16V": ("電解コンデンサ 100µF 16V φ6.3mm 高さ 5mm 足の間隔 2.5mm（105℃）", 1, "秋月", AKI.format("105002")),
    "M78AR05-1": ("DC-DC 5V 1A MINMAX M78AR05-1（三端子レギュレーター互換、入力 6.5〜32V）", 1, "秋月", AKI.format("113536")),
    "0.1uF": ("積層セラミック 0.1µF 50V X7R 足の間隔 2.5mm（村田製作所）", 1, "秋月", AKI.format("113582")),
    "100k": ("抵抗 100kΩ 1/4W（立てて実装）", "1 袋（100 本）", "秋月", AKI.format("125104")),
    "18k": ("抵抗 18kΩ 1/4W（立てて実装）", "1 袋（100 本）", "秋月", AKI.format("125183")),
    "330": ("抵抗 330Ω 1/4W（立てて実装）", "1 袋（100 本）", "秋月", AKI.format("125331")),
    "3.3k": ("抵抗 3.3kΩ 1/4W（立てて実装）", "1 袋（100 本）", "秋月", AKI.format("125332")),
    "10k": ("抵抗 10kΩ 1/4W（立てて実装）", "1 袋（100 本）", "秋月", AKI.format("125103")),
    "1k": ("抵抗 1kΩ 1/4W（立てて実装）", "1 袋（100 本）", "秋月", AKI.format("125102")),
    "BAT43": ("小信号ショットキー BAT43（DO-35）電圧測定入力のクランプ", 1, "秋月", AKI.format("113907")),
    "1N4148": ("小信号ダイオード 1N4148（DO-35）入力の逆電圧保護・ブザーの逆起電力吸収", 1, "秋月", AKI.format("100941")),
    "SMBJ45CA": ("TVS ダイオード SMBJ45CA 双方向 600W（表面実装 SMB）出力端子のサージ保護。向きはない", 1, "秋月", AKI.format("107410")),
    "PC817": ("フォトカプラ PC817X3NSZ1B（DIP-4、VCEO 80V、CTR 200〜400%）", 1, "秋月", AKI.format("113765")),
    "ESP32 VIN row": ("ESP32 DevKit V1 30 ピン（購入済み）を直接はんだ付けする。ピンが付いていないボードはピンヘッダー 1×15 を 2 本付ける", 0, "購入済み", ""),
    "ESP32 3V3 row": ("（同上）", 0, "", ""),
    "I2C": ("ピンヘッダー 1×4 2.54mm（1×40 を切って使う。GPS 用と合わせて 1 本）", "1 本（1×40）", "秋月", AKI.format("100167")),
    "GPS": ("ピンヘッダー 1×4 2.54mm（上の 1×40 から切り出す）", 0, "", ""),
    "MCP2562-E/P": ("CAN トランシーバー MCP2562FD-E/P（DIP-8）。MCP2561 は 5 番ピンが違うので不可", 1, "秋月", AKI.format("114383")),
    "Buzzer 5V 12mm": ("電子ブザー（発振回路内蔵）5V φ12mm UGCM1205XP。足の間隔 7.6mm を原寸 PDF で確認", 1, "秋月", AKI.format("109800")),
    "2SC1815": ("NPN トランジスタ 2SC1815（TO-92、足の並び E-C-B）", 1, "秋月", AKI.format("117089")),
}
# 基板に載らないが一緒に買うもの
EXTRA = [
    ("取付", "スペーサー M3 10mm（オス・メス）TP-10", "4", "秋月", AKI.format("107566")),
    ("取付", "なべ小ねじ M3×10（スペーサーの固定用）", "1 袋", "秋月", AKI.format("110253")),
]

board = pcbnew.LoadBoard(sys.argv[1])
groups = OrderedDict()
def natural(ref):
    m = re.match(r"([A-Z]+)(\d+)", ref)
    return (m.group(1), int(m.group(2)))


for fp in sorted(board.GetFootprints(), key=lambda f: natural(f.GetReference())):
    if fp.GetReference().startswith("H"):
        continue
    groups.setdefault(fp.GetValue(), []).append(fp.GetReference())
missing = [v for v in groups if v not in DESC]
if missing:
    sys.exit(f"bom.py の DESC にない部品: {missing}")
with open(sys.argv[2], "w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f)
    w.writerow(["部品数", "部品番号", "値", "内容", "買う数", "購入先", "URL"])
    for value, refs in groups.items():
        desc, unit, shop, url = DESC[value]
        buy = unit if isinstance(unit, str) else ("" if unit == 0 else str(len(refs) * unit))
        w.writerow([len(refs), " ".join(refs), value, desc, buy, shop, url])
    for ref, desc, buy, shop, url in EXTRA:
        w.writerow(["", ref, "", desc, buy, shop, url])
print("wrote", sys.argv[2])
