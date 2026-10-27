#!/usr/bin/env python3
"""stl/*.stl の見た目を確認する画像（preview_*.png）を作る（正射影・陰影付き）。"""

from pathlib import Path

import numpy as np
import trimesh
from PIL import Image

HERE = Path(__file__).resolve().parent
PX = 5  # 1mm あたりのピクセル数


def view_matrix(elev, azim):
    """elev/azim（度）から、画面座標（右, 上, 奥）への回転行列。"""
    e, a = np.radians(elev), np.radians(azim)
    rz = np.array([[np.cos(a), -np.sin(a), 0], [np.sin(a), np.cos(a), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, np.cos(e), -np.sin(e)], [0, np.sin(e), np.cos(e)]])
    return rx @ rz


def render(mesh, rot, light, color=(225, 225, 230)):
    v = mesh.vertices @ rot.T
    v[:, :2] -= v[:, :2].min(0)
    w, h = (np.ceil(v[:, :2].max(0) * PX) + 20).astype(int)
    v[:, :2] = v[:, :2] * PX + 10
    zbuf = np.full((h, w), -np.inf)
    img = np.full((h, w), 255.0)
    normals = mesh.face_normals @ rot.T
    lum = np.clip(0.25 + 0.75 * np.abs(normals @ light), 0, 1)
    for f, l in zip(mesh.faces, lum):
        p = v[f]
        x0, y0 = np.floor(p[:, :2].min(0)).astype(int)
        x1, y1 = np.ceil(p[:, :2].max(0)).astype(int)
        if x1 <= x0 or y1 <= y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        w1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        w2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        w3 = 1 - w1 - w2
        inside = (w1 >= -1e-6) & (w2 >= -1e-6) & (w3 >= -1e-6)
        z = w1 * az + w2 * bz + w3 * cz
        yy, xx = ys[inside], xs[inside]
        ok = (yy >= 0) & (yy < h) & (xx >= 0) & (xx < w)
        yy, xx, zz = yy[ok], xx[ok], z[inside][ok]
        nearer = zz > zbuf[yy, xx]
        zbuf[yy[nearer], xx[nearer]] = zz[nearer]
        img[yy[nearer], xx[nearer]] = 255 * l
    # 奥にある面ほど暗くして、段差が分かるようにする
    zmin, zmax = zbuf[~np.isinf(zbuf)].min(), zbuf[~np.isinf(zbuf)].max()
    depth = np.where(np.isinf(zbuf), 1, (zbuf - zmin) / max(zmax - zmin, 1e-6))
    img = img * (0.45 + 0.55 * depth)
    rgb = np.where(np.isinf(zbuf)[..., None], 255, img[..., None] * np.array(color) / 255)
    return Image.fromarray(np.flipud(rgb).astype(np.uint8))


def main():
    frame = trimesh.load(HERE / "stl" / "frame.stl")
    back = trimesh.load(HERE / "stl" / "back.stl")
    light = np.array([-0.35, 0.45, 0.82]); light /= np.linalg.norm(light)
    # 画面座標: x 右, y 上, z 手前（大きいほど手前）
    views = {
        "frame_front": (frame, np.diag([1.0, 1.0, -1.0])),    # 前面（z=0 側）から見る＝壁に掛けた姿
        "frame_back": (frame, np.diag([-1.0, 1.0, 1.0])),    # 裏から（Kindle を入れる側。左右が逆になる）
        "frame_corner": (frame, view_matrix(-50, -30)),      # 斜め裏から
        "back_inside": (back, np.diag([-1.0, 1.0, 1.0])),    # 裏ぶたの内側（Kindle に当たる面）
    }
    for name, (mesh, rot) in views.items():
        render(mesh, rot, light).save(HERE / f"preview_{name}.png")
        print("wrote", f"preview_{name}.png")


if __name__ == "__main__":
    main()
