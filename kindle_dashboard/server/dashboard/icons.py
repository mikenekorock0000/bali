"""E-ink 向けの線画アイコン（天気・傘・電池）。座標はすべてピクセル単位。"""

from __future__ import annotations

import math

from PIL import ImageDraw

BLACK = 0
WHITE = 255


def _union(draw: ImageDraw.ImageDraw, shapes, w: float, fg: int, bg: int) -> None:
    """円と角丸長方形の和集合を、太さ w の輪郭線で描く（中は bg で塗る）。"""
    for grow, color in ((0, fg), (-w, bg)):
        for kind, *args in shapes:
            if kind == "circle":
                cx, cy, r = args
                r += grow
                draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
            else:
                x0, y0, x1, y1 = args
                r = (y1 - y0) / 2 + grow
                draw.rounded_rectangle((x0 - grow, y0 - grow, x1 + grow, y1 + grow),
                                       radius=max(r, 0), fill=color)


def cloud(draw, x: float, y: float, s: float, w: float, fg=BLACK, bg=WHITE) -> None:
    """(x, y) を左上とする一辺 s の枠に雲を描く。"""
    _union(draw, [
        ("rect", x + 0.12 * s, y + 0.48 * s, x + 0.88 * s, y + 0.76 * s),
        ("circle", x + 0.32 * s, y + 0.54 * s, 0.18 * s),
        ("circle", x + 0.53 * s, y + 0.42 * s, 0.24 * s),
        ("circle", x + 0.74 * s, y + 0.58 * s, 0.16 * s),
    ], w, fg, bg)


def sun(draw, cx: float, cy: float, r: float, w: float, fg=BLACK, bg=WHITE) -> None:
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fg)
    draw.ellipse((cx - r + w, cy - r + w, cx + r - w, cy + r - w), fill=bg)
    for i in range(8):
        a = math.pi / 4 * i
        r0, r1 = r * 1.45, r * 2.0
        draw.line((cx + r0 * math.cos(a), cy + r0 * math.sin(a),
                   cx + r1 * math.cos(a), cy + r1 * math.sin(a)), fill=fg, width=round(w))


def moon(draw, cx: float, cy: float, r: float, w: float, fg=BLACK, bg=WHITE) -> None:
    """三日月（塗りつぶし）。円を右上にずらした円でくり抜く。"""
    off = r * 0.5
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fg)
    draw.ellipse((cx - r + off, cy - r - off * 0.5, cx + r + off, cy + r - off * 0.5), fill=bg)


def weather(draw, kind: str, cx: float, cy: float, s: float, is_day: bool = True,
            fg=BLACK, bg=WHITE) -> None:
    """中心 (cx, cy)・大きさ s の天気アイコン。"""
    w = max(1.5, s * 0.045)
    x, y = cx - s / 2, cy - s / 2

    if kind == "clear":
        if is_day:
            sun(draw, cx, cy, s * 0.2, w, fg, bg)
        else:
            moon(draw, cx, cy, s * 0.3, w, fg, bg)
        return

    if kind == "partly":
        if is_day:
            sun(draw, x + s * 0.36, y + s * 0.34, s * 0.14, w, fg, bg)
        else:
            moon(draw, x + s * 0.36, y + s * 0.34, s * 0.2, w, fg, bg)
        cloud(draw, x + s * 0.14, y + s * 0.18, s * 0.86, w, fg, bg)
        return

    # 雲 + 降水などの組み合わせ（雲は上寄せ）
    lifted = kind in ("rain", "snow", "thunder", "fog")
    cloud(draw, x, y - (s * 0.16 if lifted else 0), s, w, fg, bg)
    if not lifted:
        return

    base = y + s * 0.66
    xs = [x + s * f for f in (0.33, 0.5, 0.67)]
    if kind == "rain":
        for px in xs:
            draw.line((px, base, px - s * 0.06, base + s * 0.18), fill=fg, width=round(w))
    elif kind == "snow":
        r = s * 0.035
        for i, px in enumerate(xs):
            py = base + s * (0.06 if i % 2 == 0 else 0.16)
            draw.ellipse((px - r, py - r, px + r, py + r), fill=fg)
    elif kind == "thunder":
        bx = x + s * 0.5
        draw.polygon([(bx + s * 0.04, base - s * 0.02), (bx - s * 0.1, base + s * 0.16),
                      (bx, base + s * 0.16), (bx - s * 0.06, base + s * 0.32),
                      (bx + s * 0.12, base + s * 0.1), (bx + s * 0.02, base + s * 0.1),
                      (bx + s * 0.1, base - s * 0.02)], fill=fg)
    elif kind == "fog":
        for i in range(2):
            py = base + s * (0.04 + 0.12 * i)
            draw.line((x + s * 0.2, py, x + s * 0.8, py), fill=fg, width=round(w))


def umbrella(draw, cx: float, cy: float, s: float, fg=BLACK) -> None:
    """降水確率の前に付ける小さな傘。"""
    w = max(1, round(s * 0.1))
    r = s * 0.5
    top = cy - s * 0.45
    draw.pieslice((cx - r, top, cx + r, top + 2 * r * 0.8), 180, 360, fill=fg)
    draw.line((cx, top + r * 0.4, cx, cy + s * 0.4), fill=fg, width=w)
    hook = s * 0.14
    draw.arc((cx - 2 * hook, cy + s * 0.4 - hook, cx, cy + s * 0.4 + hook), 0, 180,
             fill=fg, width=w)


def battery(draw, x: float, y: float, w: float, h: float, level: int | None,
            fg=BLACK, bg=WHITE) -> None:
    lw = max(1, round(h * 0.12))
    nub = w * 0.08
    draw.rectangle((x, y, x + w - nub, y + h), outline=fg, width=lw, fill=bg)
    draw.rectangle((x + w - nub, y + h * 0.3, x + w, y + h * 0.7), fill=fg)
    if level is not None:
        pad = lw + 1
        inner = (w - nub - 2 * pad) * max(0, min(level, 100)) / 100
        if inner > 0:
            draw.rectangle((x + pad, y + pad, x + pad + inner, y + h - pad), fill=fg)
