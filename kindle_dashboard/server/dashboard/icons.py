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
    w = max(2, s * 0.065)
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


# ---------------------------------------------------------------- 服装のイラスト

def _body(sleeve: str, neck_dip: float, hem: float = 0.92, flare: float = 0.0):
    """服の外形（左半分を作って左右反転）。座標は 0〜1 の正方形内。"""
    left = [(0.38, 0.1), (0.18, 0.17)]
    if sleeve == "short":
        left += [(0.02, 0.4), (0.14, 0.48), (0.25, 0.38)]
    else:  # long
        left += [(0.03, 0.84), (0.15, 0.87), (0.26, 0.4)]
    left += [(0.25 - flare, hem)]
    right = [(1 - x, y) for x, y in reversed(left)]
    return left + right + [(0.5, neck_dip)]


def _tank():
    return [(0.3, 0.06), (0.4, 0.06), (0.5, 0.28), (0.6, 0.06), (0.7, 0.06),
            (0.78, 0.4), (0.78, 0.92), (0.22, 0.92), (0.22, 0.4)]


GARMENTS = {90: "tank", 80: "tshirt", 70: "cardigan", 60: "shirt", 50: "sweater",
            40: "jacket", 30: "coat", 20: "down", 10: "down_scarf"}


def garment(draw, kind: str, x: float, y: float, s: float, fg=BLACK, bg=WHITE, shade=187) -> None:
    """(x, y) を左上とする一辺 s の枠に服のイラストを描く。"""
    w = max(2, round(s * 0.07))

    def P(pts):
        return [(x + px * s, y + py * s) for px, py in pts]

    def line(*pts):
        draw.line(P(pts), fill=fg, width=w, joint="curve")

    def dot(px, py, r=0.025):
        draw.ellipse((x + (px - r) * s, y + (py - r) * s, x + (px + r) * s, y + (py + r) * s), fill=fg)

    def outline(pts, fill=bg):
        draw.polygon(P(pts), fill=fill)
        draw.line(P(pts + pts[:1]), fill=fg, width=w, joint="curve")

    if kind == "tank":
        outline(_tank())
    elif kind == "tshirt":
        outline(_body("short", 0.18))
    elif kind == "cardigan":
        outline(_body("long", 0.55))
        draw.polygon(P([(0.38, 0.1), (0.62, 0.1), (0.5, 0.55)]), fill=shade)  # 中に着た T シャツ
        line((0.5, 0.55), (0.5, 0.92))
        for py in (0.62, 0.72, 0.82):
            dot(0.44, py)
    elif kind == "shirt":
        outline(_body("long", 0.18))
        outline([(0.38, 0.1), (0.5, 0.2), (0.4, 0.26)])  # 襟
        outline([(0.62, 0.1), (0.5, 0.2), (0.6, 0.26)])
        line((0.5, 0.2), (0.5, 0.92))
        for py in (0.36, 0.52, 0.68, 0.84):
            dot(0.55, py, 0.02)
    elif kind == "sweater":
        outline(_body("long", 0.17))
        line((0.25, 0.82), (0.75, 0.82))  # 裾のリブ
        line((0.07, 0.76), (0.18, 0.79))  # 袖口
        line((0.93, 0.76), (0.82, 0.79))
        line((0.3, 0.45), (0.38, 0.38), (0.46, 0.45), (0.54, 0.38), (0.62, 0.45), (0.7, 0.38))  # 柄
    elif kind in ("jacket", "coat"):
        coat = kind == "coat"
        hem = 1.0 if coat else 0.92
        outline(_body("long", 0.5, hem, 0.04 if coat else 0.0))
        draw.polygon(P([(0.38, 0.1), (0.62, 0.1), (0.5, 0.5)]), fill=shade)
        outline([(0.38, 0.1), (0.31, 0.3), (0.5, 0.5)])  # 襟（ラペル）
        outline([(0.62, 0.1), (0.69, 0.3), (0.5, 0.5)])
        line((0.5, 0.5), (0.5, hem))
        if coat:
            for px in (0.42, 0.58):
                for py in (0.58, 0.74):
                    dot(px, py)
            line((0.25, 0.66), (0.75, 0.66))  # ベルト
        else:
            dot(0.45, 0.6)
            dot(0.45, 0.75)
            line((0.29, 0.74), (0.4, 0.74))  # ポケット
            line((0.6, 0.74), (0.71, 0.74))
    elif kind in ("down", "down_scarf"):
        outline(_body("long", 0.12, 0.9))
        outline([(0.36, 0.02), (0.64, 0.02), (0.64, 0.14), (0.36, 0.14)])  # 高い襟
        for py in (0.34, 0.52, 0.7):  # キルティング
            line((0.27, py), (0.73, py))
            line((0.1, py + 0.12), (0.22, py + 0.08))
            line((0.9, py + 0.12), (0.78, py + 0.08))
        line((0.5, 0.14), (0.5, 0.9))  # ファスナー
        if kind == "down_scarf":
            draw.rounded_rectangle(P([(0.3, 0.08), (0.7, 0.22)]), radius=s * 0.05, fill=fg)
            draw.polygon(P([(0.54, 0.2), (0.66, 0.2), (0.7, 0.56), (0.58, 0.58)]), fill=fg)


def umbrella_badge(draw, x: float, y: float, s: float, fg=BLACK, bg=WHITE) -> None:
    """雨の日に服の隣へ出す大きな傘（黒地に白抜き）。(x, y) を左上とする一辺 s。"""
    def P(px, py):
        return x + px * s, y + py * s

    draw.rounded_rectangle((x, y, x + s, y + s), radius=s * 0.16, fill=fg)
    w = max(2, round(s * 0.06))
    # 傘の布: 半楕円を白で塗り、裾を 3 か所丸く切り欠く
    draw.pieslice((*P(0.1, 0.14), *P(0.9, 0.7)), 180, 360, fill=bg)
    for cx in (0.233, 0.5, 0.767):  # 裾の浅い波
        draw.ellipse((*P(cx - 0.133, 0.4), *P(cx + 0.133, 0.46)), fill=fg)
    for ex in (0.367, 0.633):  # 骨
        draw.line((*P(0.5, 0.15), *P(ex, 0.41)), fill=fg, width=max(1, w // 2))
    # 柄と持ち手
    draw.line((*P(0.5, 0.16), *P(0.5, 0.78)), fill=bg, width=w)
    draw.arc((*P(0.36, 0.7), *P(0.52, 0.88)), 0, 180, fill=bg, width=w)
    # 雨粒
    for px, py in ((0.2, 0.58), (0.8, 0.58), (0.27, 0.74), (0.73, 0.74)):
        draw.line((*P(px, py), *P(px - 0.04, py + 0.1)), fill=bg, width=w)
