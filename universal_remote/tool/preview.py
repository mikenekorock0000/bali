#!/usr/bin/env python3
"""画面のイメージ図を描く（docs/preview.png）。実機の描画（firmware/src/main.cpp）と同じ配置を Pillow でなぞったもの。

  python3 universal_remote/tool/preview.py [フォントのフォルダ]

フォント（NotoSansJP-VF.ttf と Orbitron-VF.ttf）は Kindle ダッシュボードの
`kindle_dashboard/server/fetch_fonts.py` で取得したもの（kindle-dashboard ブランチ）を使う。
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "kindle_dashboard" / "server" / "fonts"
S = 2  # 2 倍で描いて見やすく
W = 240 * S

BG, TEXT, SUB, TRACK, OFF = "#000000", "#ffffff", "#8a8f98", "#22262c", "#4a4f57"
COOL, TV, LIGHT, OK = "#3aa0ff", "#e056fd", "#ffc93c", "#2e7d4f"


def jp(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONTS / "NotoSansJP-VF.ttf"), size * S)
    try:
        f.set_variation_by_axes([600])
    except Exception:  # noqa: BLE001
        pass
    return f


def seg(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / "Orbitron-VF.ttf"), size * S)


class Screen:
    def __init__(self) -> None:
        self.im = Image.new("RGB", (W, W), BG)
        self.d = ImageDraw.Draw(self.im)

    def text(self, s: str, y: int, size: int, color: str, x: int = 120, font=None) -> None:
        self.d.text((x * S, y * S), s, font=font or jp(size), fill=color, anchor="mm")

    def arc(self, r0: int, r1: int, a0: float, a1: float, color: str) -> None:
        box = [(120 - r1) * S, (120 - r1) * S, (120 + r1) * S, (120 + r1) * S]
        self.d.arc(box, a0, a1, fill=color, width=(r1 - r0) * S)

    def circle(self, x: int, y: int, r: int, color: str) -> None:
        self.d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=color)

    def power(self, x: int, y: int, r: int, color: str) -> None:
        box = [(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S]
        self.d.arc(box, 300, 600, fill=color, width=5 * S)
        self.d.line([x * S, (y - r - 4) * S, x * S, (y - 2) * S], fill=color, width=6 * S)

    def toast(self, s: str, color: str) -> None:
        w = 120
        self.d.rounded_rectangle([(120 - w // 2) * S, 192 * S, (120 + w // 2) * S, 220 * S],
                                 radius=14 * S, fill=color)
        self.text(s, 206, 16, TEXT)

    def done(self) -> Image.Image:
        # 丸い画面の外を落とし、本体の枠を描く
        mask = Image.new("L", (W, W), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, W - 1, W - 1], fill=255)
        pad = 26 * S
        out = Image.new("RGB", (W + pad * 2, W + pad * 2), "#f2f2f2")
        dd = ImageDraw.Draw(out)
        dd.ellipse([4 * S, 4 * S, W + pad * 2 - 4 * S, W + pad * 2 - 4 * S], fill="#d24a3a")
        dd.ellipse([pad - 6 * S, pad - 6 * S, W + pad + 6 * S, W + pad + 6 * S], fill="#2a2a2a")
        out.paste(self.im, (pad, pad), mask)
        return out


def home() -> Image.Image:
    s = Screen()
    s.text("21:47", 34, 20, SUB)
    s.circle(120, 102, 40, COOL)
    s.text("エアコン", 102, 16, BG)
    s.text("リビングのエアコン", 165, 22, TEXT)
    s.text("室温 24.5℃  48%", 194, 16, SUB)
    n, cur, span = 6, 0, 50
    for i in range(n):
        a = math.radians(90 + span / 2 - span * i / (n - 1))
        x, y = 120 + math.cos(a) * 108, 120 + math.sin(a) * 108
        s.circle(round(x), round(y), 4 if i == cur else 2, COOL if i == cur else OFF)
    return s.done()


def aircon() -> Image.Image:
    s = Screen()
    s.arc(108, 118, 135, 405, TRACK)
    s.arc(108, 118, 135, 135 + 270 * (26 - 16) / 14, COOL)
    s.text("リビングのエアコン", 36, 13, SUB)
    s.text("冷房", 58, 24, COOL)
    s.text("26", 106, 0, TEXT, x=112, font=seg(58))
    s.text("℃", 92, 20, TEXT, x=160)
    s.text("● 運転中", 146, 16, COOL)
    s.text("風量 自動", 178, 20, TEXT)
    s.text("室温 24.5℃  48%", 206, 16, SUB)
    return s.done()


def tv() -> Image.Image:
    s = Screen()
    s.arc(112, 118, 0, 360, TRACK)
    s.text("テレビ", 32, 16, SUB)
    s.text("チャンネル ＋", 62, 20, TEXT)
    s.circle(120, 120, 32, "#15181c")
    s.power(120, 122, 16, TV)
    s.text("チャンネル −", 176, 20, TEXT)
    s.toast("音量 ＋", OK)
    return s.done()


def scenes() -> Image.Image:
    s = Screen()
    s.text("シーン", 32, 16, SUB)
    items = ["おやすみ", "外出", "映画モード"]
    for d, label in zip(range(-1, 2), items):
        y = 124 + d * 46
        if d == 0:
            s.d.rounded_rectangle([22 * S, (y - 22) * S, 218 * S, (y + 22) * S], radius=22 * S, fill="#ff8a3d")
            s.text(label, y, 24, BG)
        else:
            s.text(label, y, 20, SUB)
    s.text("2 / 5", 222, 12, SUB)
    return s.done()


def main() -> None:
    if not (FONTS / "NotoSansJP-VF.ttf").exists():
        sys.exit(f"フォントがありません: {FONTS}（kindle_dashboard/server/fetch_fonts.py で取得するか、フォルダを引数で指定）")
    shots = [("ホーム（ダイヤルで機器を選ぶ）", home()), ("エアコン", aircon()),
             ("テレビ（音量を送った直後）", tv()), ("シーン・学習ボタン", scenes())]
    w, h = shots[0][1].size
    gap = 24 * S
    sheet = Image.new("RGB", (len(shots) * w + (len(shots) + 1) * gap, h + 60 * S), "#f2f2f2")
    d = ImageDraw.Draw(sheet)
    for i, (cap, im) in enumerate(shots):
        x = gap + i * (w + gap)
        sheet.paste(im, (x, gap // 2))
        d.text((x + w // 2, h + 34 * S), cap, font=jp(14), fill="#333333", anchor="mm")
    out = ROOT / "docs" / "preview.png"
    out.parent.mkdir(exist_ok=True)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
