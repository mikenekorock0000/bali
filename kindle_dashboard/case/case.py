#!/usr/bin/env python3
"""Kindle Paperwhite 第7世代用の壁掛け額縁ケース（Bambu Lab A1 mini で印刷できる大きさ）。

  pip install manifold3d trimesh numpy
  python case.py            # stl/frame.stl, stl/back.stl を書き出す

部品:
  frame.stl  額の本体。前面（画面側）を下にして印刷する。サポート不要。
  back.stl   裏ぶた。そのまま平らに印刷する。
  fit_test.stl  お試し用（額の前面＋壁の根元 1mm だけ。窓の位置と Kindle の外形の合い具合を 20 分ほどで確認）

設置の向き: 横置き、Kindle のロゴ（=充電端子・電源ボタンのある辺）が右。
ケーブル: 右辺中央の micro-USB 端子に薄型 FPC（フラット）延長ケーブルの 90° プラグを挿し、
          右側の細い溝を下へ通して、右下角のポケットにメス側の基板を収める。

座標: X = 右, Y = 上, Z = 前面（0）から裏側へ。単位は mm。
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import trimesh
from manifold3d import CrossSection, JoinType, Manifold, OpType

# ---------------------------------------------------------------- 寸法（必要ならここを変える）

# Kindle Paperwhite 第7世代（2015）
K_W, K_H, K_T = 169.0, 117.0, 9.1
FIT = 0.3                     # Kindle の周りのすき間（片側）
# 画面（表示部）の位置: 横置き・ロゴが右のとき、Kindle の外形からの距離（写真から計測した推定値）
SCREEN_W, SCREEN_H = 122.6, 90.8
SCREEN_LEFT, SCREEN_BOTTOM = 19.0, 13.1
WINDOW_MARGIN = 0.8           # 窓を表示部より片側これだけ大きく
WINDOW_CHAMFER = 1.6          # 窓の前面側の面取り

# 額
W = 178.0                     # 横幅（A1 mini の 180mm に収める）
WALL_L, WALL_R = 1.2, 1.6     # 左右の壁
BORDER_BOTTOM, BORDER_TOP = 16.0, 18.0   # Kindle の上下の額の幅
FRONT_T = 2.0                 # 前面（画面の周りの縁）の厚さ
POCKET_D = K_T + 0.5          # Kindle の入る深さ
BACK_T = 2.4                  # 裏ぶたの厚さ（はめ込み）
CORNER_R = 4.0                # 外形の角の丸み

# ケーブル
GUTTER = W - WALL_L - WALL_R - 2 * FIT - K_W          # 右側の溝の幅（≒5.6）
PORT_FROM_BOTTOM = K_H / 2                            # 端子は右辺の中央
JACK_POCKET_W, JACK_POCKET_H = 16.0, 11.0             # 右下角のメス基板ポケット（X, Y）
JACK_OPENING_W = 12.0                                 # 下面の差し口の幅
BUTTON_SLOT = (6.0, 32.0)                             # 電源ボタン用スリット: 端子の中心から上へ何 mm〜何 mm
BUTTON_SLOT_W = 2.6

# 取り付け
SCREW_PILOT = 2.5            # M3 タッピングねじの下穴
SCREW_CLEAR, SCREW_HEAD = 3.4, 6.4
KEYHOLE_HEAD, KEYHOLE_SHANK, KEYHOLE_SLIDE = 8.5, 4.5, 5.0
KEYHOLE_DEPTH = 4.0          # 額の上の縁に掘るねじ頭の逃げ
KEYHOLE_SPACING = 90.0

# ---------------------------------------------------------------- 計算した位置

H = BORDER_BOTTOM + 2 * FIT + K_H + BORDER_TOP
D = FRONT_T + POCKET_D + BACK_T
KX0 = WALL_L + FIT                       # Kindle の左端
KY0 = BORDER_BOTTOM + FIT                # Kindle の下端
KX1, KY1 = KX0 + K_W, KY0 + K_H
GX0, GX1 = KX1 + FIT, W - WALL_R         # 右側の溝
PORT_Y = KY0 + PORT_FROM_BOTTOM

SCREWS = [(22.0, H - 9.0), (W - 22.0, H - 9.0), (22.0, 8.0), (W - 34.0, 8.0)]
KEYHOLES = [(W / 2 - KEYHOLE_SPACING / 2, KY1 + FIT + 5.6), (W / 2 + KEYHOLE_SPACING / 2, KY1 + FIT + 5.6)]


def rrect(x0, y0, x1, y1, r=0.0) -> CrossSection:
    """角を丸めた長方形（r=0 なら角ばったまま）。"""
    w, h = x1 - x0, y1 - y0
    if r <= 0:
        return CrossSection.square([w, h]).translate([x0, y0])
    return CrossSection.square([w - 2 * r, h - 2 * r]).translate([x0 + r, y0 + r]).offset(
        r, JoinType.Round, circular_segments=48)


def slab(cs: CrossSection, z0: float, z1: float) -> Manifold:
    return cs.extrude(z1 - z0).translate([0, 0, z0])


def box(x0, y0, z0, x1, y1, z1) -> Manifold:
    return Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])


def cyl_z(x, y, z0, z1, d) -> Manifold:
    return Manifold.cylinder(z1 - z0, d / 2, d / 2, 48).translate([x, y, z0])


def keyhole(x, y, head_w, z0, z1) -> Manifold:
    """丸い入口（頭が通る）と上へのスライド溝。"""
    circle = cyl_z(x, y, z0, z1, KEYHOLE_HEAD)
    slot = box(x - head_w / 2, y, z0, x + head_w / 2, y + KEYHOLE_SLIDE, z1)
    top = cyl_z(x, y + KEYHOLE_SLIDE, z0, z1, head_w)
    return circle + slot + top


# ---------------------------------------------------------------- 額の本体

def frame() -> Manifold:
    body = slab(rrect(0, 0, W, H, CORNER_R), 0, D)

    cuts = []
    # Kindle の入るくぼみ（裏から）
    cuts.append(slab(rrect(KX0 - FIT, KY0 - FIT, KX1 + FIT, KY1 + FIT, 3.0), FRONT_T, D))
    # 裏ぶたのはめ込み段（周りの壁だけ残す）
    cuts.append(slab(rrect(WALL_L, WALL_R, W - WALL_R, H - WALL_R, max(CORNER_R - WALL_R, 0.5)), D - BACK_T, D))

    # 画面の窓（前面ほど広い面取り）
    wx0 = KX0 + SCREEN_LEFT - WINDOW_MARGIN
    wy0 = KY0 + SCREEN_BOTTOM - WINDOW_MARGIN
    ww, wh = SCREEN_W + 2 * WINDOW_MARGIN, SCREEN_H + 2 * WINDOW_MARGIN
    c = WINDOW_CHAMFER
    # scale_top は原点基準なので、中心で作ってから移動する
    window = (CrossSection.square([ww + 2 * c, wh + 2 * c], center=True)
              .extrude(FRONT_T + 0.01, scale_top=(ww / (ww + 2 * c), wh / (wh + 2 * c)))
              .translate([wx0 + ww / 2, wy0 + wh / 2, -0.005]))
    cuts.append(window)

    # 右側の溝: 端子の高さから下の縁のポケットまで（裏から開いている）
    cuts.append(box(GX0, BORDER_BOTTOM - JACK_POCKET_H + 0.5, FRONT_T, GX1, KY1, D))
    # 右下角: FPC のメス基板ポケットと、下面の差し口
    px1 = GX1
    px0 = px1 - JACK_POCKET_W
    py0 = WALL_R
    cuts.append(box(px0, py0, FRONT_T + 1.0, px1, py0 + JACK_POCKET_H, D))
    ox = (px0 + px1) / 2
    cuts.append(box(ox - JACK_OPENING_W / 2, -1, FRONT_T + 1.0, ox + JACK_OPENING_W / 2, py0 + 0.01, D))

    # 電源ボタン用の縦スリット（右の壁、厚みの中央。つまようじ等で押す）
    zc = FRONT_T + POCKET_D / 2
    cuts.append(box(GX1 - 0.01, PORT_Y + BUTTON_SLOT[0], zc - BUTTON_SLOT_W / 2,
                    W + 1, PORT_Y + BUTTON_SLOT[1], zc + BUTTON_SLOT_W / 2))

    # ねじの下穴（裏ぶたの段の底から）
    for x, y in SCREWS:
        cuts.append(cyl_z(x, y, D - BACK_T - 10.0, D, SCREW_PILOT))
    # 壁掛け: 額の上の縁にねじ頭の逃げ（裏ぶたの鍵穴の奥）
    for x, y in KEYHOLES:
        cuts.append(keyhole(x, y, KEYHOLE_HEAD, D - BACK_T - KEYHOLE_DEPTH, D))

    return body - Manifold.batch_boolean(cuts, OpType.Add)


# ---------------------------------------------------------------- 裏ぶた

def back() -> Manifold:
    gap = 0.2
    plate = slab(rrect(WALL_L + gap, WALL_R + gap, W - WALL_R - gap, H - WALL_R - gap,
                       max(CORNER_R - WALL_R - gap, 0.5)), 0, BACK_T)
    cuts = []
    for x, y in SCREWS:  # 皿ねじ用の穴（外側=z 上面が広い）
        cuts.append(cyl_z(x, y, -1, BACK_T + 1, SCREW_CLEAR))
        cuts.append(Manifold.cylinder(1.6, SCREW_CLEAR / 2, SCREW_HEAD / 2, 48).translate([x, y, BACK_T - 1.6 + 0.001]))
    for x, y in KEYHOLES:  # 鍵穴（頭が通る丸＋ねじの軸が通る細い溝）
        cuts.append(keyhole(x, y, KEYHOLE_SHANK, -1, BACK_T + 1))
    plate = plate - Manifold.batch_boolean(cuts, OpType.Add)

    # Kindle を前へ軽く押さえる 2 本の帯（内側=z 下面に）
    ribs = [box(KX0 + 20, KY0 + 25, -0.5, KX1 - 30, KY0 + 30, 0.01),
            box(KX0 + 20, KY1 - 30, -0.5, KX1 - 30, KY1 - 25, 0.01)]
    plate = plate + Manifold.batch_boolean(ribs, OpType.Add)
    # 印刷しやすいよう、外側の面を下にして置く（上下反転して z=0 から）
    plate = plate.mirror([0, 0, 1])
    return plate.translate([0, 0, -plate.bounding_box()[2]])


def to_trimesh(m: Manifold) -> trimesh.Trimesh:
    mesh = m.to_mesh()
    return trimesh.Trimesh(np.asarray(mesh.vert_properties)[:, :3], np.asarray(mesh.tri_verts), process=True)


def fit_test() -> Manifold:
    """前面とその上 1mm だけを切り出した確認用。"""
    return frame() ^ box(-1, -1, -1, W + 1, H + 1, FRONT_T + 1.0)


def main() -> None:
    out = Path(__file__).resolve().parent / "stl"
    out.mkdir(exist_ok=True)
    for name, part in (("frame", frame()), ("back", back()), ("fit_test", fit_test())):
        mesh = to_trimesh(part)
        assert mesh.is_watertight, name
        mesh.export(out / f"{name}.stl")
        ext = mesh.bounds[1] - mesh.bounds[0]
        print(f"{name}.stl  {ext[0]:.1f} x {ext[1]:.1f} x {ext[2]:.1f} mm  体積 {mesh.volume / 1000:.0f} cm3")
    print(f"右側の溝の幅 {GUTTER:.1f} mm / 全体 {W:.0f} x {H:.1f} x {D:.1f} mm")


if __name__ == "__main__":
    main()
