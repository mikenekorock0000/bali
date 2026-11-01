#!/usr/bin/env python3
"""DRC では分からない「実物の部品が収まるか」を確認する。

- 部品の足の太さと穴径（足 + 0.15mm 以上の穴か）
- ESP32 ボード（直接はんだ付け、下の隙間 2.5mm）の下に部品がないか
- ESP32 の USB コネクタにケーブルを挿す空間
- 端子台の電線の差し込み口が基板の外側を向いているか
- 部品が基板からはみ出していないか

数値は各部品の一般的なデータシート値（最大値寄り）。違う部品を買う場合はこの表も見直すこと。
  python3 check_mech.py hijet_starter.kicad_pcb
"""
import sys

import pcbnew

# 値 → (足の最大径 mm, 実装時の高さ mm, 根拠)。角ピンは対角の長さ。表面実装は足 0
PARTS = {
    "PC817": (0.55, 5.0, "DIP-4 足 0.5mm、高さ 3.5mm＋浮き"),
    "MCP2562-E/P": (0.56, 5.3, "PDIP-8 足 0.46mm、本体 3.3mm＋足の肩"),
    "330": (0.6, 10.0, "1/4W 抵抗（立てる）"),
    "100k": (0.6, 10.0, "1/4W 抵抗（立てる）"),
    "3.3k": (0.6, 10.0, "1/4W 抵抗（立てる）"),
    "1k": (0.6, 10.0, "1/4W 抵抗（立てる）"),
    "10k": (0.6, 10.0, "1/4W 抵抗（立てる）"),
    "1N4148": (0.55, 7.0, "DO-35 足 0.5mm（立てる）"),
    "BAT43": (0.55, 7.0, "DO-35 足 0.5mm（立てる）"),
    "SB340LS": (0.9, 11.0, "DO-15 足 0.86mm（立てる）"),
    "P4KE15A": (0.9, 9.0, "DO-41 足 0.86mm（立てる）"),
    "P4KE6.8CA": (0.9, 9.0, "DO-41 足 0.86mm（立てる）"),
    "SMBJ45CA": (0, 2.6, "表面実装 SMB（DO-214AA）高さ 2.6mm"),
    "0.1uF": (0.55, 6.0, "積層セラミック ラジアル 足 0.5mm"),
    "100uF 50V": (0.6, 12.5, "φ8×11.5mm 電解"),
    "100uF 16V": (0.55, 6.0, "φ6.3×5.4mm 電解（MH5 など背の低いもの）"),
    "PTC 1.1A": (0.81, 18.0, "ポリスイッチ RXEF110（幅 12.8×厚さ 3.0×高さ 17.5mm）／MF-RX110/72（10.8×3.1×16.8mm）足 0.81mm"),
    "M78AR05-1": (0.64 * 1.414, 10.7, "SIP-3 本体 11.5×7.55×10.2mm。足は 0.64mm 角以下と想定（対角 0.9mm）"),
    "Buzzer 5V 12mm": (0.65, 9.5, "φ12×9.5mm 電子ブザー"),
    "2SC1815": (0.5, 8.0, "TO-92 足 0.45mm"),
    "12V IN": (1.15, 10.0, "5.08mm 端子台 TB112（推奨穴 1.3mm）"),
    "OUT": (1.15, 10.0, "5.08mm 端子台 TB112（推奨穴 1.3mm）"),
    "IN": (1.15, 10.0, "5.08mm 端子台 TB112（推奨穴 1.3mm）"),
    "OBD-II CAN": (1.15, 10.0, "5.08mm 端子台 TB112（推奨穴 1.3mm）"),
    "ESP32 VIN row": (0.64 * 1.414, 2.5, "DevKit のピン 0.64mm 角（対角 0.9mm）を直接はんだ付け"),
    "ESP32 3V3 row": (0.64 * 1.414, 2.5, "同上"),
    "I2C": (0.64 * 1.414, 8.5, "ピンヘッダー 0.64mm 角"),
    "GPS": (0.64 * 1.414, 8.5, "ピンヘッダー 0.64mm 角"),
    "M3": (0, 0, "取付穴"),
}

# ESP32 DevKit V1（HW-394）の実測：EN ピンからアンテナ側の端まで 6.7mm、VIN から USB 側の端まで 10mm、幅 28.4mm。
# 直接はんだ付けなので、ESP32 の基板の下面はピンヘッダーの樹脂（2.5mm）の高さ。下には部品を一切置かない。
ESP_X, ESP_Y, ESP_ROW, ESP_PINS = 62.0, 14.0, 25.4, 15
DEVKIT = (ESP_X + ESP_ROW / 2 - 14.2, ESP_Y - 6.7, ESP_X + ESP_ROW / 2 + 14.2, ESP_Y + (ESP_PINS - 1) * 2.54 + 10.0)
UNDER_DEVKIT_MAX_H = 0.0
# USB プラグ（micro-B のモールド部 幅 12mm・厚さ 8mm まで）を挿す空間。コネクタの中心は基板から約 5.4mm
# （樹脂 2.5 ＋ DevKit の基板 1.6 ＋ 1.3）なので、プラグの下面は約 1.4mm。リード部品は置けない
USB_CX = ESP_X + ESP_ROW / 2
USB_ZONE = (USB_CX - 6.5, DEVKIT[3], USB_CX + 6.5, DEVKIT[3] + 25)
USB_MAX_H = 1.0
DRILL_MARGIN = 0.15        # 丸い足：足径 + 0.15mm 以上の穴
SQUARE_PIN_MARGIN = 0.05   # 角ピン（0.64mm 角）：対角 + 0.05mm 以上（ヘッダーの推奨穴径 1.0mm を満たす）
SQUARE_PIN_PARTS = {"ESP32 VIN row", "ESP32 3V3 row", "I2C", "GPS", "M78AR05-1"}


def mm(v):
    return pcbnew.ToMM(v)


def rect_overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def main():
    board = pcbnew.LoadBoard(sys.argv[1])
    bb = board.GetBoardEdgesBoundingBox()
    W, H = mm(bb.GetWidth()), mm(bb.GetHeight())
    errors, notes = [], []

    for fp in board.GetFootprints():
        ref, val = fp.GetReference(), fp.GetValue()
        if val not in PARTS:
            errors.append(f"{ref} {val}: 部品の寸法表にない（check_mech.py に追加すること）")
            continue
        lead, height, why = PARTS[val]
        cy = fp.GetCourtyard(pcbnew.F_CrtYd).BBox() if fp.GetCourtyard(pcbnew.F_CrtYd).OutlineCount() else fp.GetBoundingBox(False, False)
        box = (mm(cy.GetX()), mm(cy.GetY()), mm(cy.GetX() + cy.GetWidth()), mm(cy.GetY() + cy.GetHeight()))

        # 穴径
        for p in fp.Pads():
            if p.GetAttribute() in (pcbnew.PAD_ATTRIB_NPTH, pcbnew.PAD_ATTRIB_SMD):
                continue
            d = mm(p.GetDrillSize().x)
            margin = SQUARE_PIN_MARGIN if val in SQUARE_PIN_PARTS else DRILL_MARGIN
            if d < lead + margin:
                errors.append(f"{ref} {val} pad {p.GetNumber()}: 穴 {d:.2f}mm < 足 {lead:.2f}mm + {margin}")

        # ESP32 の下
        if ref not in ("J5", "J6") and rect_overlap(box, DEVKIT):
            if height > UNDER_DEVKIT_MAX_H:
                errors.append(f"{ref} {val}: ESP32 の下に入るが高さ {height}mm > {UNDER_DEVKIT_MAX_H}mm")
            else:
                notes.append(f"ESP32 の下: {ref} {val}（高さ {height}mm）")

        # USB プラグ
        if rect_overlap(box, USB_ZONE) and height > USB_MAX_H:
            errors.append(f"{ref} {val}: USB プラグの差し込み空間にあり高さ {height}mm > {USB_MAX_H}mm")

        # 基板からのはみ出し（端子台の差し込み口側は 0.5mm まで許す）
        if box[0] < -0.5 or box[1] < -0.5 or box[2] > W + 0.5 or box[3] > H + 0.5:
            errors.append(f"{ref} {val}: 基板からはみ出している {tuple(round(v, 1) for v in box)}")

        # 端子台の向き：フットプリントの +y 側が差し込み口。基板の端に向いているか
        if fp.GetFPID().GetLibItemName().wx_str().startswith("TerminalBlock"):
            o = fp.GetOrientationDegrees() % 360
            dirs = {0: (0, 1), 90: (1, 0), 180: (0, -1), 270: (-1, 0)}
            dx, dy = dirs[round(o) % 360]
            edge = {(-1, 0): box[0], (1, 0): W - box[2], (0, -1): box[1], (0, 1): H - box[3]}[(dx, dy)]
            side = {(-1, 0): "左", (1, 0): "右", (0, -1): "上", (0, 1): "下"}[(dx, dy)]
            if edge > 1.5:
                errors.append(f"{ref} {val}: 差し込み口（{side}向き）が基板の端から {edge:.1f}mm 内側")
            else:
                notes.append(f"{ref} {val}: 差し込み口は基板の{side}端に向いている")

    print(f"基板 {W:.1f} x {H:.1f} mm")
    print(f"ESP32 の外形（想定）: x {DEVKIT[0]:.1f}〜{DEVKIT[2]:.1f}, y {DEVKIT[1]:.1f}〜{DEVKIT[3]:.1f}")
    for n in sorted(notes):
        print("  ok  ", n)
    for e in errors:
        print("  NG  ", e)
    print(f"機構チェック: {len(errors)} 件の問題")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
