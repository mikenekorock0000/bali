#!/usr/bin/env python3
"""ハイゼット スターター連携基板（ESP32-DevKitC キャリア）を生成する。

KiCad 7 の pcbnew API で部品を配置し、簡易迷路ルーターで配線、GND ベタを敷いて
hijet_starter.kicad_pcb を書き出す。ガーバー出力と DRC は build.sh で行う。

  python3 gen_pcb.py
"""
import heapq
import math
import os
import sys

import numpy as np
import pcbnew

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "hijet_starter.kicad_pcb")
FPLIB = "/usr/share/kicad/footprints"

# ---------------------------------------------------------------- 基板寸法
BOARD_W, BOARD_H = 92.0, 70.0
GRID = 0.25            # ルーティング格子 [mm]
CLEAR = 0.30           # 銅箔間クリアランス [mm]
EDGE_CLEAR = 0.60      # 基板端からの距離 [mm]
SIG_W, PWR_W = 0.40, 1.00
VIA_D, VIA_DRILL = 0.80, 0.40

POWER_NETS = {"BATT", "12V_F", "12V_P", "+5V", "GND"}

# ESP32 DevKit V1 互換（30 ピン、HW-394）：列間 25.4mm、15 ピン×2。
# 1 番ピンをアンテナ側（基板の上）にした並び。
ESP_X, ESP_Y = 59.0, 14.0
ESP_ROW = 25.4
ESP_L = {2: "G36", 4: "VSENSE", 5: "G35", 6: "G32", 7: "G33", 8: "G25", 9: "G26", 10: "G27",
         13: "G13", 14: "GND", 15: "+5V"}  # EN VP VN D34 D35 D32 D33 D25 D26 D27 D14 D12 D13 GND VIN
ESP_R = {2: "SCL", 5: "SDA", 6: "G19", 7: "G18", 9: "G17", 10: "G16", 11: "STBY",
         14: "GND", 15: "+3V3"}  # D23 D22 TX0 RX0 D21 D19 D18 D5 D17 D16 D4 D2 D15 GND 3V3

# アンテナ下（ピン列の間、上端側）は銅箔禁止
ANTENNA_KEEPOUT = (ESP_X + 1.6, 0.0, ESP_X + ESP_ROW - 1.6, ESP_Y + 4.0)

# ---------------------------------------------------------------- 部品表
# (ref, lib, footprint, x, y, 角度, {pad: net}, 値)
PARTS = []


def part(ref, lib, fp, x, y, rot, nets, value):
    PARTS.append((ref, lib, fp, x, y, rot, nets, value))


# 足の間隔 5.08mm で立てて実装する抵抗・ダイオード（はんだ付けしやすく、場所を取らない）
RV = ("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P5.08mm_Vertical")
D35V = ("Diode_THT", "D_DO-35_SOD27_P5.08mm_Vertical_KathodeUp")
CDISC = ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P2.50mm")
DIP4 = ("Package_DIP", "DIP-4_W7.62mm")

# ---- 中央列：電源（端子 → ポリスイッチ → 逆接保護 → TVS/コンデンサ → DC-DC）と電圧測定・ブザー
part("J1", "TerminalBlock_Phoenix", "TerminalBlock_Phoenix_MKDS-1,5-3-5.08_1x03_P5.08mm_Horizontal",
     53.0, 5.8, 180, {"1": "BATT", "2": "GND", "3": "12V_F"}, "12V IN")
part("F1", "Capacitor_THT", "C_Disc_D7.5mm_W5.0mm_P5.00mm", 41.0, 17.0, 0,
     {"1": "BATT", "2": "12V_F"}, "PTC 0.5A")
part("D1", "Diode_THT", "D_DO-41_SOD81_P5.08mm_Vertical_KathodeUp", 49.5, 15.5, 0,
     {"1": "12V_P", "2": "12V_F"}, "1N5819")
part("D2", "Diode_THT", "D_DO-15_P5.08mm_Vertical_KathodeUp", 49.5, 21.5, 0,
     {"1": "12V_P", "2": "GND"}, "P6KE22A")
part("C1", "Capacitor_THT", "CP_Radial_D8.0mm_P3.50mm", 40.5, 25.5, 0,
     {"1": "12V_P", "2": "GND"}, "100uF 50V")
part("C2", "Capacitor_THT", "CP_Radial_D6.3mm_P2.50mm", 51.0, 27.0, 0,
     {"1": "+5V", "2": "GND"}, "100uF 16V")
part("U1", "Converter_DCDC", "Converter_DCDC_Murata_OKI-78SR_Vertical", 40.5, 37.0, 0,
     {"1": "12V_P", "2": "GND", "3": "+5V"}, "OKI-78SR-5/1.5-W36-C")
part("R1", *RV, 50.5, 34.0, 0, {"1": "12V_F", "2": "VSENSE"}, "100k")
part("R2", *RV, 50.5, 38.0, 0, {"1": "GND", "2": "VSENSE"}, "22k")
part("C4", *CDISC, 51.0, 42.0, 0, {"1": "VSENSE", "2": "GND"}, "0.1uF")
part("D3", *D35V, 50.5, 46.0, 0, {"1": "+3V3", "2": "VSENSE"}, "BAT85")
part("C3", *CDISC, 55.5, 55.0, 90, {"1": "+5V", "2": "GND"}, "0.1uF")

# ブザー（5V 自励式）：GPIO13 → 1k → 2SC1815（E-C-B）。10k で起動時に OFF、1N4148 で逆起電力吸収
part("BZ1", "Buzzer_Beeper", "Buzzer_12x9.5RM7.6", 40.5, 54.0, 0, {"1": "+5V", "2": "BZN"}, "Buzzer 5V 12mm")
part("D7", *D35V, 40.0, 63.0, 0, {"1": "+5V", "2": "BZN"}, "1N4148")
part("Q1", "Package_TO_SOT_THT", "TO-92_Inline_Wide", 40.0, 67.5, 0,
     {"1": "GND", "2": "BZN", "3": "QB"}, "2SC1815")
part("R13", *RV, 48.0, 63.0, 0, {"1": "QB", "2": "G13"}, "1k")
part("R14", *RV, 48.0, 67.5, 0, {"1": "QB", "2": "GND"}, "10k")

# ---- ESP32 DevKit V1（30 ピン）用ソケット。下の空間に背の低い部品を置く
part("J5", "Connector_PinSocket_2.54mm", "PinSocket_1x15_P2.54mm_Vertical", ESP_X, ESP_Y, 0,
     {str(k): v for k, v in ESP_L.items()}, "ESP32 VIN row")
part("J6", "Connector_PinSocket_2.54mm", "PinSocket_1x15_P2.54mm_Vertical", ESP_X + ESP_ROW, ESP_Y, 0,
     {str(k): v for k, v in ESP_R.items()}, "ESP32 3V3 row")

# OBD-II（CAN）：MCP2562（VDD=5V、VIO=3.3V）。STBY は 10k で待機側に固定し、GPIO4 で LOW にしたときだけ動作
part("U9", "Package_DIP", "DIP-8_W7.62mm", 65.0, 33.0, 0,
     {"1": "G18", "2": "GND", "3": "+5V", "4": "G19", "5": "+3V3", "6": "CANL", "7": "CANH",
      "8": "STBY"}, "MCP2562-E/P")
part("C5", *CDISC, 65.0, 45.5, 0, {"1": "+5V", "2": "GND"}, "0.1uF")
part("C6", *CDISC, 76.0, 45.0, 90, {"1": "+3V3", "2": "GND"}, "0.1uF")
part("R15", *RV, 76.0, 30.0, 0, {"1": "STBY", "2": "+3V3"}, "10k")
part("J7", "TerminalBlock_Phoenix", "TerminalBlock_Phoenix_PT-1,5-3-3.5-H_1x03_P3.50mm_Horizontal",
     72.0, 64.0, 0, {"1": "CANH", "2": "CANL", "3": "GND"}, "OBD-II CAN")

# ---- 右端：I2C と GPS（UART2）のピンヘッダー。1 番（四角）が GND
part("J4", "Connector_PinHeader_2.54mm", "PinHeader_1x04_P2.54mm_Vertical", 89.5, 18.0, 0,
     {"1": "GND", "2": "+3V3", "3": "SCL", "4": "SDA"}, "I2C")
part("J8", "Connector_PinHeader_2.54mm", "PinHeader_1x04_P2.54mm_Vertical", 89.5, 31.0, 0,
     {"1": "GND", "2": "+3V3", "3": "G17", "4": "G16"}, "GPS")

# ---- 左列：絶縁出力 4ch（1ch は車両の施錠信号用）
OUT_GPIO = ["G25", "G26", "G27", "G32"]
OUT_NAME = ["LOCK", "OUT2", "OUT3", "OUT4"]
j2nets = {}
for k in range(4):
    ye = 10.5 + 7 * k
    part(f"U{2 + k}", *DIP4, 22.12, ye + 2.54, 180,
         {"1": f"LED{k + 1}", "2": "GND", "3": f"O{k + 1}E", "4": f"O{k + 1}C"}, "PC817C")
    part(f"R{3 + k}", *RV, 25.5, ye + 2.54, 0, {"1": f"LED{k + 1}", "2": OUT_GPIO[k]}, "470")
    j2nets[str(2 * k + 1)] = f"O{k + 1}E"
    j2nets[str(2 * k + 2)] = f"O{k + 1}C"
part("J2", "TerminalBlock_Phoenix", "TerminalBlock_Phoenix_PT-1,5-8-3.5-H_1x08_P3.50mm_Horizontal",
     5.5, 10.0, 270, j2nets, "OUT")

# ---- 左列：絶縁入力 3ch（IN+ → 2.2k → PC817 LED → IN-、1N4148 で逆電圧保護）。3ch 目は ACC 検知
IN_GPIO = ["G33", "G35", "G36"]
for k in range(3):
    y = 39.0 + 7 * k
    part(f"R{7 + k}", *RV, 12.0, y, 0, {"1": f"IN{k + 1}P", "2": f"IN{k + 1}A"}, "2.2k")
    part(f"D{4 + k}", *D35V, 17.08, y + 3.5, 180, {"1": f"IN{k + 1}A", "2": f"IN{k + 1}N"}, "1N4148")
    part(f"U{6 + k}", *DIP4, 20.5, y, 0,
         {"1": f"IN{k + 1}A", "2": f"IN{k + 1}N", "3": "GND", "4": IN_GPIO[k]}, "PC817C")
    part(f"R{10 + k}", *RV, 31.0, y, 0, {"1": IN_GPIO[k], "2": "+3V3"}, "10k")
part("J3", "TerminalBlock_Phoenix", "TerminalBlock_Phoenix_PT-1,5-6-3.5-H_1x06_P3.50mm_Horizontal",
     5.5, 39.0, 270, {"1": "IN1P", "2": "IN1N", "3": "IN2P", "4": "IN2N", "5": "IN3P", "6": "IN3N"},
     "IN")

for i, (x, y) in enumerate([(3.5, 3.5), (88.5, 3.5), (3.5, 66.5), (88.5, 66.5)]):
    part(f"H{i + 1}", "MountingHole", "MountingHole_3.2mm_M3", x, y, 0, {}, "M3")

L, R, C = "L", "R", "C"
SILK = [
    # (文字, x, y, 角度, 大きさ, 揃え)
    ("+12V", 53.0, 12.6, 0, 0.8, C), ("GND", 47.92, 12.6, 0, 0.8, C), ("OUT", 42.84, 12.6, 0, 0.8, C),
    ("CAN", 68.5, 64.0, 0, 0.8, R),
    ("H", 72.0, 59.3, 0, 0.8, C), ("L", 75.5, 59.3, 0, 0.8, C), ("G", 79.0, 59.3, 0, 0.8, C),
    ("I2C", 89.5, 15.5, 0, 0.8, C), ("GPS", 89.5, 28.5, 0, 0.8, C),
    ("HIJET MONITOR v3", 71.7, 52.5, 0, 1.0, C),
    ("USB side", 71.7, 56.5, 0, 0.8, C),
]
for k in range(4):
    SILK.append((f"+ {OUT_NAME[k]} -", 11.2, 11.75 + 7 * k, 90, 0.8, C))
for k, name in enumerate(["IN1", "IN2", "ACC"]):
    SILK.append((f"- {name} +", 9.9, 40.75 + 7 * k, 90, 0.8, C))

# 部品番号の位置の上書き：立てる部品は既定で本体の上（-2mm）。("rel", dx, dy) はパッド中点から、
# ("abs", x, y) は絶対位置
REF_POS = {"D1": ("rel", 0, 2.6), "Q1": ("abs", 37.0, 67.5), "D3": ("rel", 0, 2.0), "C2": ("abs", 56.6, 27.0)}

# ---------------------------------------------------------------- ボード生成


def mm(v):
    return pcbnew.FromMM(float(v))


def build_board():
    board = pcbnew.BOARD()
    ds = board.GetDesignSettings()
    ds.SetCopperLayerCount(2)
    ds.m_TrackMinWidth = mm(0.2)
    ds.m_MinClearance = mm(0.2)
    ds.m_ViasMinSize = mm(0.6)
    ds.m_MinThroughDrill = mm(0.3)
    ds.m_CopperEdgeClearance = mm(0.5)
    ds.m_HoleClearance = mm(0.25)
    nc = ds.m_NetSettings.m_DefaultNetClass
    nc.SetClearance(mm(CLEAR))
    nc.SetTrackWidth(mm(SIG_W))
    nc.SetViaDiameter(mm(VIA_D))
    nc.SetViaDrill(mm(VIA_DRILL))

    # 外形
    pts = [(0, 0), (BOARD_W, 0), (BOARD_W, BOARD_H), (0, BOARD_H)]
    for i in range(4):
        s = pcbnew.PCB_SHAPE(board)
        s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(pcbnew.VECTOR2I(mm(pts[i][0]), mm(pts[i][1])))
        s.SetEnd(pcbnew.VECTOR2I(mm(pts[(i + 1) % 4][0]), mm(pts[(i + 1) % 4][1])))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(mm(0.1))
        board.Add(s)

    nets = {}

    def net(name):
        if name not in nets:
            n = pcbnew.NETINFO_ITEM(board, name)
            board.Add(n)
            nets[name] = n
        return nets[name]

    for ref, lib, fpn, x, y, rot, padnets, value in PARTS:
        fp = pcbnew.FootprintLoad(os.path.join(FPLIB, lib + ".pretty"), fpn)
        if fp is None:
            sys.exit(f"footprint not found: {lib}:{fpn}")
        fp.SetReference(ref)
        fp.SetValue(value)
        fp.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        fp.SetOrientationDegrees(rot)
        board.Add(fp)
        for p in fp.Pads():
            n = padnets.get(p.GetNumber())
            if n:
                p.SetNet(net(n))
        # 値は F.Fab（組立図）に、シルクは部品番号だけにする
        fp.Value().SetLayer(pcbnew.F_Fab)
        ref = fp.Reference()
        ref.SetTextSize(pcbnew.VECTOR2I(mm(0.8), mm(0.8)))
        ref.SetTextThickness(mm(0.12))
        if ref.GetText().startswith("H") or ref.GetText() in ("J1", "J2", "J3", "J4", "J7", "J8"):
            ref.SetVisible(False)  # 取付穴と端子台はシルクの文字で用途を示す
        name = ref.GetText()
        if name in REF_POS or "Vertical" in fpn and name[0] in "RD":
            xs = [p.GetPosition().x for p in fp.Pads()]
            ys = [p.GetPosition().y for p in fp.Pads()]
            kind, dx, dy = REF_POS.get(name, ("rel", 0, -2.0))
            if kind == "abs":
                ref.SetPosition(pcbnew.VECTOR2I(mm(dx), mm(dy)))
            else:
                ref.SetPosition(pcbnew.VECTOR2I((min(xs) + max(xs)) // 2 + mm(dx),
                                                (min(ys) + max(ys)) // 2 + mm(dy)))
            ref.SetTextAngleDegrees(0)
        elif (name[0] in "RDU" and name != "U1") or name in ("BZ1", "F1"):
            # 抵抗・ダイオード・フォトカプラは本体の中央に番号を置く
            xs = [p.GetPosition().x for p in fp.Pads()]
            ys = [p.GetPosition().y for p in fp.Pads()]
            ref.SetPosition(pcbnew.VECTOR2I((min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2))
            ref.SetTextAngleDegrees(90 if rot in (90, 270) and ref.GetText()[0] != "U" else 0)
        for p in fp.Pads():
            # ESP32 ソケットの GND はベタに直結（細いピンなので熱逃がし不要）
            if padnets.get(p.GetNumber()) == "GND" and (
                    ref.GetText() in ("J5", "J6", "C2", "C3", "C5", "C6", "U9", "J4", "J8")):
                p.SetZoneConnection(pcbnew.ZONE_CONNECTION_FULL)

    for text, x, y, rot, size, just in SILK:
        t = pcbnew.PCB_TEXT(board)
        t.SetText(text)
        t.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        t.SetLayer(pcbnew.F_SilkS)
        t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        t.SetTextThickness(mm(size * 0.15))
        t.SetTextAngleDegrees(rot)
        t.SetHorizJustify({"L": pcbnew.GR_TEXT_H_ALIGN_LEFT, "R": pcbnew.GR_TEXT_H_ALIGN_RIGHT,
                           "C": pcbnew.GR_TEXT_H_ALIGN_CENTER}[just])
        board.Add(t)
    return board, nets


# ---------------------------------------------------------------- ルーター


class Router:
    """2 層の格子迷路ルーター（A*、8 方向、ビア付き）。"""

    def __init__(self, board):
        self.board = board
        self.nx = int(BOARD_W / GRID) + 1
        self.ny = int(BOARD_H / GRID) + 1
        self.xs = np.arange(self.nx) * GRID
        self.ys = np.arange(self.ny) * GRID
        # classes: 0=signal, 1=power/via
        self.half = {0: SIG_W / 2, 1: max(PWR_W, VIA_D) / 2}
        self.cov = {(l, c): np.zeros((self.ny, self.nx), np.int16) for l in (0, 1) for c in (0, 1)}
        self.own = {}  # (net, layer, class) -> list of index arrays
        self.fixed = {(l, c): np.zeros((self.ny, self.nx), bool) for l in (0, 1) for c in (0, 1)}
        self.pads = {}  # net -> list of pad
        self._init_static()

    # 格子に図形を塗る
    def _mark(self, net, layers, mask_fn, bbox, inflate_extra):
        for c in (0, 1):
            infl = self.half[c] + CLEAR + inflate_extra
            x0, y0, x1, y1 = bbox
            i0 = max(0, int((x0 - infl) / GRID))
            i1 = min(self.nx - 1, int((x1 + infl) / GRID) + 1)
            j0 = max(0, int((y0 - infl) / GRID))
            j1 = min(self.ny - 1, int((y1 + infl) / GRID) + 1)
            X, Y = np.meshgrid(self.xs[i0:i1 + 1], self.ys[j0:j1 + 1])
            m = mask_fn(X, Y, infl)
            jj, ii = np.nonzero(m)
            jj = jj + j0
            ii = ii + i0
            for l in layers:
                if net is None:
                    self.fixed[(l, c)][jj, ii] = True
                else:
                    self.cov[(l, c)][jj, ii] += 1
                    self.own.setdefault((net, l, c), []).append((jj, ii))

    def mark_segment(self, net, layer, a, b, width):
        (ax, ay), (bx, by) = a, b
        w = width / 2

        def fn(X, Y, infl):
            dx, dy = bx - ax, by - ay
            L2 = dx * dx + dy * dy
            if L2 == 0:
                d = np.hypot(X - ax, Y - ay)
            else:
                t = np.clip(((X - ax) * dx + (Y - ay) * dy) / L2, 0, 1)
                d = np.hypot(X - (ax + t * dx), Y - (ay + t * dy))
            return d <= w + infl

        self._mark(net, [layer], fn, (min(ax, bx), min(ay, by), max(ax, bx), max(ay, by)), w)

    def mark_circle(self, net, layers, c, r):
        cx, cy = c

        def fn(X, Y, infl):
            return np.hypot(X - cx, Y - cy) <= r + infl

        self._mark(net, layers, fn, (cx, cy, cx, cy), r)

    def _init_static(self):
        # 基板端
        for c in (0, 1):
            e = EDGE_CLEAR + self.half[c]
            for l in (0, 1):
                f = self.fixed[(l, c)]
                f[:, : int(e / GRID) + 1] = True
                f[:, -(int(e / GRID) + 1):] = True
                f[: int(e / GRID) + 1, :] = True
                f[-(int(e / GRID) + 1):, :] = True
                x0, y0, x1, y1 = ANTENNA_KEEPOUT
                f[int(y0 / GRID): int(y1 / GRID) + 1, int(x0 / GRID): int(x1 / GRID) + 1] = True
        for fp in self.board.GetFootprints():
            for p in fp.Pads():
                name = p.GetNetname() or None
                pos = p.GetPosition()
                cx, cy = pcbnew.ToMM(pos.x), pcbnew.ToMM(pos.y)
                if name:
                    self.pads.setdefault(name, []).append(p)
                bb = p.GetBoundingBox()
                x0, y0 = pcbnew.ToMM(bb.GetX()), pcbnew.ToMM(bb.GetY())
                x1, y1 = x0 + pcbnew.ToMM(bb.GetWidth()), y0 + pcbnew.ToMM(bb.GetHeight())
                if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH:
                    # 取付穴：ネジ頭とワッシャー分を空ける
                    self.mark_circle(None, [0, 1], (cx, cy), 3.2)
                    continue
                if name is None:
                    name = f"__nc_{fp.GetReference()}_{p.GetNumber()}"
                pad = p

                def fn(X, Y, infl, pad=pad):
                    out = np.zeros(X.shape, bool)
                    acc = mm(infl)
                    for j in range(X.shape[0]):
                        for i in range(X.shape[1]):
                            out[j, i] = pad.HitTest(pcbnew.VECTOR2I(mm(X[j, i]), mm(Y[j, i])), acc)
                    return out

                self._mark(name, [0, 1], fn, (x0, y0, x1, y1), 0)

    def blocked(self, net, layer, cls):
        own = np.zeros_like(self.cov[(layer, cls)])
        for jj, ii in self.own.get((net, layer, cls), []):
            np.add.at(own, (jj, ii), 1)
        b = self.fixed[(layer, cls)] | ((self.cov[(layer, cls)] - own) > 0)
        return b

    def cell(self, x, y):
        return int(round(y / GRID)), int(round(x / GRID))

    def route_pads(self, name, pads):
        saved = self.pads.get(name)
        self.pads[name] = pads
        try:
            return self.route_net(name)
        finally:
            self.pads[name] = saved

    def route_net(self, name):
        pads = self.pads.get(name, [])
        if len(pads) < 2:
            return True, []
        cls = 1 if name in POWER_NETS else 0
        width = PWR_W if cls else SIG_W
        blk = [self.blocked(name, l, cls) for l in (0, 1)]
        vblk = blk if cls == 1 else [self.blocked(name, l, 1) for l in (0, 1)]
        via_ok = ~(vblk[0] | vblk[1])

        def padcells(p):
            pos = p.GetPosition()
            return self.cell(pcbnew.ToMM(pos.x), pcbnew.ToMM(pos.y))

        # 自ネットのパッド領域は通行可にする
        for p in pads:
            j, i = padcells(p)
            r = 2
            for l in (0, 1):
                blk[l][max(0, j - r): j + r + 1, max(0, i - r): i + r + 1] &= False

        connected = {(l,) + padcells(pads[0]) for l in (0, 1)}
        remaining = list(pads[1:])
        segments = []
        # 近い順に繋ぐ
        while remaining:
            src = connected

            def dist(p):
                j, i = padcells(p)
                return min(abs(j - s[1]) + abs(i - s[2]) for s in src)

            remaining.sort(key=dist)
            tgt = remaining.pop(0)
            tj, ti = padcells(tgt)
            path = self.astar(src, (tj, ti), blk, via_ok)
            if path is None:
                return False, segments
            segments.append(path)
            for s in path:
                connected.add(s)
            connected.add((0, tj, ti))
            connected.add((1, tj, ti))
        return True, segments

    def astar(self, sources, target, blk, via_ok):
        tj, ti = target
        VIA_COST = 30
        moves = [(0, 1, 1.0), (1, 0, 1.0), (0, -1, 1.0), (-1, 0, 1.0),
                 (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)]
        openh = []
        g = {}
        parent = {}
        for s in sources:
            g[s] = 0.0
            parent[s] = None
            h = max(abs(s[1] - tj), abs(s[2] - ti))
            heapq.heappush(openh, (h, 0.0, s))
        ny, nx = self.ny, self.nx
        while openh:
            f, gc, s = heapq.heappop(openh)
            if gc > g.get(s, 1e18):
                continue
            l, j, i = s
            if j == tj and i == ti:
                path = []
                while s is not None:
                    path.append(s)
                    s = parent[s]
                return path[::-1]
            nbrs = []
            for dj, di, c in moves:
                nj, ni = j + dj, i + di
                if 0 <= nj < ny and 0 <= ni < nx and not blk[l][nj, ni]:
                    # 斜めは両隣が空いているときだけ（角の削り込み防止）
                    if dj and di and (blk[l][j, ni] or blk[l][nj, i]):
                        continue
                    nbrs.append(((l, nj, ni), c + (0.2 if l == 1 else 0.0)))
            if via_ok[j, i]:
                nbrs.append(((1 - l, j, i), VIA_COST))
            for ns, c in nbrs:
                ng = gc + c
                if ng < g.get(ns, 1e18):
                    g[ns] = ng
                    parent[ns] = s
                    h = max(abs(ns[1] - tj), abs(ns[2] - ti))
                    heapq.heappush(openh, (ng + h, ng, ns))
        return None

    def commit(self, name, paths):
        """経路を基板に追加し、占有格子を更新する。"""
        cls = 1 if name in POWER_NETS else 0
        width = PWR_W if cls else SIG_W
        netinfo = self.board.FindNet(name)
        for path in paths:
            # 同じ方向・同じ層の連続をまとめる
            pts = [path[0]]
            for k in range(1, len(path)):
                pts.append(path[k])
            runs = []
            cur = [pts[0]]
            for p in pts[1:]:
                if p[0] != cur[-1][0]:
                    runs.append(cur)
                    # ビア
                    x, y = cur[-1][2] * GRID, cur[-1][1] * GRID
                    v = pcbnew.PCB_VIA(self.board)
                    v.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
                    v.SetWidth(mm(VIA_D))
                    v.SetDrill(mm(VIA_DRILL))
                    v.SetNet(netinfo)
                    self.board.Add(v)
                    self.mark_circle(name, [0, 1], (x, y), VIA_D / 2)
                    cur = [p]
                else:
                    cur.append(p)
            runs.append(cur)
            for run in runs:
                if len(run) < 2:
                    continue
                layer = run[0][0]
                # 折れ点だけ残す
                verts = [run[0]]
                for k in range(1, len(run) - 1):
                    d1 = (run[k][1] - run[k - 1][1], run[k][2] - run[k - 1][2])
                    d2 = (run[k + 1][1] - run[k][1], run[k + 1][2] - run[k][2])
                    if d1 != d2:
                        verts.append(run[k])
                verts.append(run[-1])
                for a, b in zip(verts, verts[1:]):
                    ax, ay = a[2] * GRID, a[1] * GRID
                    bx, by = b[2] * GRID, b[1] * GRID
                    t = pcbnew.PCB_TRACK(self.board)
                    t.SetStart(pcbnew.VECTOR2I(mm(ax), mm(ay)))
                    t.SetEnd(pcbnew.VECTOR2I(mm(bx), mm(by)))
                    t.SetWidth(mm(width))
                    t.SetLayer(pcbnew.F_Cu if layer == 0 else pcbnew.B_Cu)
                    t.SetNet(netinfo)
                    self.board.Add(t)
                    self.mark_segment(name, layer, (ax, ay), (bx, by), width)


GND_LINKS = []


def find_pad(board, ref, num):
    return [p for p in board.FindFootprintByReference(ref).Pads() if p.GetNumber() == num][0]


def add_zones(board, nets):
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNet(nets["GND"])
        z.SetLocalClearance(mm(0.4))
        z.SetMinThickness(mm(0.3))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetThermalReliefGap(mm(0.4))
        z.SetThermalReliefSpokeWidth(mm(0.6))
        z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
        ol = z.Outline()
        ol.NewOutline()
        for x, y in [(0.3, 0.3), (BOARD_W - 0.3, 0.3), (BOARD_W - 0.3, BOARD_H - 0.3), (0.3, BOARD_H - 0.3)]:
            ol.Append(mm(x), mm(y))
        board.Add(z)
    # アンテナ下の銅箔禁止エリア
    ka = pcbnew.ZONE(board)
    ka.SetIsRuleArea(True)
    ka.SetDoNotAllowCopperPour(True)
    ka.SetDoNotAllowTracks(True)
    ka.SetDoNotAllowVias(True)
    ka.SetDoNotAllowPads(False)
    ka.SetDoNotAllowFootprints(False)
    ls = pcbnew.LSET()
    ls.AddLayer(pcbnew.F_Cu)
    ls.AddLayer(pcbnew.B_Cu)
    ka.SetLayerSet(ls)
    ol = ka.Outline()
    ol.NewOutline()
    x0, y0, x1, y1 = ANTENNA_KEEPOUT
    for x, y in [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]:
        ol.Append(mm(x), mm(y))
    board.Add(ka)


def main():
    board, nets = build_board()
    router = Router(board)
    order = ["12V_F", "BATT", "12V_P", "+5V", "VSENSE", "+3V3", "SCL", "SDA",
             "G25", "G26", "G27", "G32", "G33", "G35"]
    order += sorted(n for n in router.pads if n not in order and n != "GND")
    failed = []
    for name in order:
        ok, paths = router.route_net(name)
        router.commit(name, paths)
        if not ok:
            failed.append(name)
        print(f"route {name:8s} {'ok' if ok else 'FAILED'}")
    # ベタだけでは届かない GND パッドを、近くの GND パッドへ直接配線する
    for a, b in GND_LINKS:
        ok, paths = router.route_pads("GND", [find_pad(board, *a), find_pad(board, *b)])
        router.commit("GND", paths)
        print(f"route GND {a}-{b} {'ok' if ok else 'FAILED'}")
        if not ok:
            failed.append(f"GND {a}-{b}")
    add_zones(board, nets)
    board.Save(OUT)
    # 新規 BOARD のままだと ZONE_FILLER が落ちるため、読み直してから塗りつぶす
    filled = pcbnew.LoadBoard(OUT)
    pcbnew.ZONE_FILLER(filled).Fill(filled.Zones())
    filled.Save(OUT)
    print("saved", OUT)
    if failed:
        print("UNROUTED:", failed)
        sys.exit(1)


if __name__ == "__main__":
    main()
