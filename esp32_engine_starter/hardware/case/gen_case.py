"""HIJET MONITOR 基板（v4、98×90mm）のケース。Bambu Lab A1 mini（造形 180×180×180mm）で印刷する。

    python3 gen_case.py      → case_base.stl（本体）と case_lid.stl（ふた）

座標：基板の左上が原点、x が右、y が下（gen_pcb.py と同じ）。z は本体の底面が 0。
本体は底を下に、ふたは上面を下にして置けば、サポートなしで印刷できる。
寸法は下の定数にまとめてある。部品の位置は gen_pcb.py の値を写したもの（基板を変えたら合わせる）。
"""
import manifold3d as m
import numpy as np
import trimesh

BOARD_W, BOARD_H = 98.0, 90.0
GAP = 0.5            # 基板と内壁のすき間
WALL = 2.0           # 壁の厚さ
FLOOR = 2.0          # 底の厚さ
BOSS_H = 8.0         # 基板を載せる柱の高さ（裏に出た足が底に当たらないように）
BOSS_D = 7.0
SCREW_PILOT = 2.6    # M3 のねじを直接ねじ込む下穴（PETG・PLA）
SCREW_CLEAR = 3.4    # M3 が通る穴
PCB_T = 1.6
CLEAR_ABOVE = 22.0   # 基板の上の空き（いちばん背の高いポリスイッチ 18mm＋余裕）
LID_T = 2.5
LIP_T, LIP_H, LIP_GAP = 1.5, 3.0, 0.3   # ふたの裏の位置決めの縁
EAR = 9.0            # 角のねじの耳（一辺）
SKIRT = 4.0          # ふたの外周の壁（本体の壁の上 4mm をふたの側に持たせ、耳と一体にして強くする）
CBORE_D, CBORE_H = 6.2, 3.5   # ふたの耳の座ぐり（ねじの頭を沈め、M3×10 で本体に 7mm 入るようにする）
HOLES = [(3.5, 3.5), (BOARD_W - 3.5, 3.5), (3.5, BOARD_H - 3.5), (BOARD_W - 3.5, BOARD_H - 3.5)]

PCB_BOTTOM = FLOOR + BOSS_H
PCB_TOP = PCB_BOTTOM + PCB_T
INNER_TOP = PCB_TOP + CLEAR_ABOVE      # ふたの裏
SPLIT = INNER_TOP - SKIRT               # 本体とふたの分かれ目
X0, Y0 = -GAP, -GAP                     # 内側の空間
X1, Y1 = BOARD_W + GAP, BOARD_H + GAP
OX0, OY0, OX1, OY1 = X0 - WALL, Y0 - WALL, X1 + WALL, Y1 + WALL

# 電線を通す切り欠き：(壁, 始め, 終わり)。端子台の電線の差し込み口の前を、基板の上面から上に開ける
WIRE_BOTTOM = PCB_TOP + 0.5      # 切り欠きの底（電線が載る高さ）
WIRE_TOP = PCB_TOP + 9.0         # ふたの舌がここまで下りて、すき間を電線の太さ程度にする
NOTCHES = [
    ("top", 38.8, 57.0, WIRE_BOTTOM),      # J1 電源（42.84〜53.0）
    ("bottom", 34.0, 52.2, WIRE_BOTTOM),   # J7 CAN（38.0〜48.16）
    ("left", 7.0, 48.6, WIRE_BOTTOM),      # J2 出力（10.5〜46.06）
    ("left", 51.0, 81.4, WIRE_BOTTOM),     # J3 入力（53.5〜78.9）
    ("right", 14.0, 42.0, PCB_TOP + 10.0), # J4 I2C・J8 GPS のケーブル（ピンの上で曲げて出す）
]
# DevKit の BOOT・EN ボタンを、ふたの上からつまようじで押す穴（位置は DevKit の外形からの推定。長穴で余裕を持たせる）
DEVKIT = (60.5, 7.3, 89.1, 59.56)        # x0, y0, x1, y1（check_mech.py と同じ）
BUTTONS = [(DEVKIT[0] + 4.5, DEVKIT[3] - 4.0), (DEVKIT[2] - 4.5, DEVKIT[3] - 4.0)]
BUTTON_SLOT = (9.0, 6.0)


def box(x0, y0, z0, x1, y1, z1):
    return m.Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])


def cyl(x, y, z0, h, d, seg=48):
    return m.Manifold.cylinder(h, d / 2, d / 2, seg).translate([x, y, z0])


def slot(x, y, z0, h, w, d):
    """角の丸い長穴（w×d）"""
    r = d / 2
    return m.Manifold.hull(cyl(x - w / 2 + r, y, z0, h, d) + cyl(x + w / 2 - r, y, z0, h, d))


def notch_box(side, a, b, z0, z1, extra=0.0):
    t = WALL + 2  # 壁を確実に貫く
    if side == "top":
        return box(a - extra, OY0 - 1, z0, b + extra, Y0 + 1, z1)
    if side == "bottom":
        return box(a - extra, Y1 - 1, z0, b + extra, OY1 + 1, z1)
    if side == "left":
        return box(OX0 - 1, a - extra, z0, X0 + 1, b + extra, z1)
    return box(X1 - 1, a - extra, z0, OX1 + 1, b + extra, z1)


def ear_centers():
    d = EAR / 2 - WALL  # 耳が内側の空間にはみ出さない位置
    return [(OX0 - d, OY0 - d), (OX1 + d, OY0 - d), (OX0 - d, OY1 + d), (OX1 + d, OY1 + d)]


def base():
    body = box(OX0, OY0, 0, OX1, OY1, SPLIT)
    body -= box(X0, Y0, FLOOR, X1, Y1, INNER_TOP + 1)
    # 角の耳（ふたのねじ）
    for cx, cy in ear_centers():
        body += box(cx - EAR / 2, cy - EAR / 2, 0, cx + EAR / 2, cy + EAR / 2, SPLIT)
        body -= cyl(cx, cy, 4.0, INNER_TOP, SCREW_PILOT)
    # 基板の柱
    for x, y in HOLES:
        body += cyl(x, y, FLOOR - 0.01, BOSS_H + 0.01, BOSS_D)
        body -= cyl(x, y, FLOOR + 1.0, BOSS_H, SCREW_PILOT)
    # 電線の切り欠き
    for side, a, b, z0 in NOTCHES:
        body -= notch_box(side, a, b, z0, INNER_TOP + 1)
    # 車への取り付け：左右の底に、ねじ・結束バンド用の長穴付きのつば
    for x0, x1 in ((OX0 - 14, OX0 + 0.01), (OX1 - 0.01, OX1 + 14)):
        body += box(x0, OY0 + 12, 0, x1, OY1 - 12, 3.0)
        cx = (x0 + x1) / 2
        for cy in (OY0 + 22, OY1 - 22):
            body -= box(cx - 2.25, cy - 4, -1, cx + 2.25, cy + 4, 5)  # 幅 4.5（M4 か結束バンド）
    return body


def lid():
    z = INNER_TOP
    top = box(OX0, OY0, z, OX1, OY1, z + LID_T)
    # 外周の壁（本体の壁の続き）。耳はこの壁と上の板の両方につながる
    top += box(OX0, OY0, SPLIT, OX1, OY1, z + 0.01) - box(X0, Y0, SPLIT - 1, X1, Y1, z + 1)
    for cx, cy in ear_centers():
        top += box(cx - EAR / 2, cy - EAR / 2, SPLIT, cx + EAR / 2, cy + EAR / 2, z + LID_T)
        top -= cyl(cx, cy, SPLIT - 1, z + LID_T - SPLIT + 2, SCREW_CLEAR)
        top -= cyl(cx, cy, z + LID_T - CBORE_H, CBORE_H + 1, CBORE_D)
    # 位置決めの縁（内壁の内側に入る）
    g = LIP_GAP
    lip = box(X0 + g, Y0 + g, z - LIP_H, X1 - g, Y1 - g, z + 0.01)
    lip -= box(X0 + g + LIP_T, Y0 + g + LIP_T, z - LIP_H - 1, X1 - g - LIP_T, Y1 - g - LIP_T, z + 1)
    top += lip
    # 切り欠きをふさぐ舌（電線の通るすき間だけ残す）
    for side, a, b, z0 in NOTCHES:
        tongue_bottom = WIRE_TOP if z0 == WIRE_BOTTOM else z0 + 7.0
        t = notch_box(side, a + g, b - g, tongue_bottom, z + 0.01)
        # 壁の厚みの中だけに残す
        wall_band = box(OX0, OY0, 0, OX1, OY1, z + 1) - box(X0, Y0, -1, X1, Y1, z + 2)
        top += t ^ wall_band
    # BOOT・EN ボタンの穴
    for bx, by in BUTTONS:
        top -= slot(bx, by, z - 1, LID_T + 2, *BUTTON_SLOT)
    return top


def save(man, path, flip=False):
    mesh = man.to_mesh()
    v = np.array(mesh.vert_properties)[:, :3]
    f = np.array(mesh.tri_verts)
    tm = trimesh.Trimesh(v, f, process=True)
    if flip:  # ふたは上面を下にして印刷する
        tm.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [1, 0, 0]))
    tm.apply_translation(-tm.bounds[0])
    tm.export(path)
    ext = tm.bounds[1] - tm.bounds[0]
    print(f"{path}: {ext[0]:.1f} × {ext[1]:.1f} × {ext[2]:.1f} mm, 水密={tm.is_watertight}, 体積 {tm.volume / 1000:.1f} cm³")
    return tm


if __name__ == "__main__":
    b, l = base(), lid()
    assert b.status() == m.Error.NoError and l.status() == m.Error.NoError
    assert (b ^ l).volume() < 1e-6, "本体とふたが重なっている"
    save(b, "case_base.stl")
    save(l, "case_lid.stl", flip=True)
    print(f"基板の上面 z={PCB_TOP:.1f}、ふたの裏 z={INNER_TOP:.1f}、全高 {INNER_TOP + LID_T:.1f} mm")
