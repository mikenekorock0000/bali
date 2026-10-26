"""ダッシュボード画像の描画。

横 1024 x 縦 758（Kindle Paperwhite 2 の横置き）で 2 倍解像度に描いてから縮小し、
16 階調のグレースケールに落として、Kindle の向きに合わせて回転する。
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from . import icons
from .sources import Indoor, Quote, Weather, co2_level, icon_kind, weather_label, wind_direction_ja

BLACK, DARK, GRAY, LIGHT, WHITE = 0, 68, 119, 187, 255
WEEKDAYS = "月火水木金土日"

FONT_CANDIDATES = [
    "fonts/NotoSansJP[wght].ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf",
    "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf",
    "C:/Windows/Fonts/meiryo.ttc",
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
]


@dataclass
class DashboardData:
    now: datetime
    weather: Weather | None = None
    quotes: list[Quote] = field(default_factory=list)
    news: list[str] = field(default_factory=list)
    indoor: Indoor | None = None
    battery: int | None = None
    charging: bool = False
    failing: list[str] = field(default_factory=list)
    news_label: str = "NHKニュース"
    credits: str = "天気: Open-Meteo ／ 市況: Yahoo Finance"


class Fonts:
    """サイズ・太さごとのフォントをキャッシュする。可変フォントなら太さを切り替える。"""

    def __init__(self, path: str | None = None, base_dir: Path | None = None):
        candidates = ([path] if path else []) + FONT_CANDIDATES
        base = base_dir or Path.cwd()
        for c in candidates:
            p = Path(c) if Path(c).is_absolute() else base / c
            if p.exists():
                self.path = str(p)
                break
        else:
            raise FileNotFoundError(
                "日本語フォントが見つかりません。server/fetch_fonts.sh を実行するか config の font_path を設定してください")
        self._cache: dict[tuple[int, str], ImageFont.FreeTypeFont] = {}

    def get(self, size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
        key = (size, weight)
        if key not in self._cache:
            font = ImageFont.truetype(self.path, size)
            try:
                font.set_variation_by_name(weight)
            except (OSError, ValueError):
                pass  # 可変フォントでなければ太さは変えられない
            self._cache[key] = font
        return self._cache[key]


class Canvas:
    """論理座標（1024x758）で描き、内部では scale 倍の解像度で描画する。"""

    def __init__(self, width: int, height: int, fonts: Fonts, scale: int = 2):
        self.w, self.h, self.s = width, height, scale
        self.fonts = fonts
        self.img = Image.new("L", (width * scale, height * scale), WHITE)
        self.d = ImageDraw.Draw(self.img)

    def font(self, size: float, weight: str):
        return self.fonts.get(round(size * self.s), weight)

    def text(self, x, y, txt, size, weight="Regular", fill=BLACK, anchor="la") -> float:
        """描いた文字列の幅（論理座標）を返す。"""
        f = self.font(size, weight)
        self.d.text((x * self.s, y * self.s), txt, font=f, fill=fill, anchor=anchor)
        return self.text_width(txt, size, weight)

    def text_width(self, txt, size, weight="Regular") -> float:
        return self.font(size, weight).getlength(txt) / self.s

    def fit(self, txt, size, weight, max_width) -> str:
        if self.text_width(txt, size, weight) <= max_width:
            return txt
        while txt and self.text_width(txt + "…", size, weight) > max_width:
            txt = txt[:-1]
        return txt + "…"

    def fit_size(self, txt, size, weight, max_width) -> float:
        while size > 8 and self.text_width(txt, size, weight) > max_width:
            size -= 2
        return size

    def line(self, x0, y0, x1, y1, width=1, fill=BLACK):
        self.d.line((x0 * self.s, y0 * self.s, x1 * self.s, y1 * self.s),
                    fill=fill, width=max(1, round(width * self.s)))

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1):
        self.d.rectangle((x0 * self.s, y0 * self.s, x1 * self.s, y1 * self.s),
                         fill=fill, outline=outline, width=round(width * self.s))

    def weather_icon(self, code, cx, cy, size, is_day=True):
        icons.weather(self.d, icon_kind(code), cx * self.s, cy * self.s, size * self.s, is_day)

    def umbrella(self, cx, cy, size):
        icons.umbrella(self.d, cx * self.s, cy * self.s, size * self.s)

    def battery(self, x, y, w, h, level):
        icons.battery(self.d, x * self.s, y * self.s, w * self.s, h * self.s, level)

    def label_box(self, x, y, txt):
        w = self.text_width(txt, 17, "Bold") + 16
        self.rect(x, y, x + w, y + 27, fill=DARK)
        self.text(x + w / 2, y + 14, txt, 17, "Bold", fill=WHITE, anchor="mm")

    def finish(self) -> Image.Image:
        return self.img.resize((self.w, self.h), Image.LANCZOS)


def _deg(v: float | None) -> str:
    return "—" if v is None else f"{round(v)}°"


def _pct(v: float | None) -> str:
    return "—" if v is None else f"{round(v)}%"


def _num(v: float, decimals: int) -> str:
    return f"{v:,.{decimals}f}"


# ---------------------------------------------------------------- 各パネル

M = 22  # 左右の余白


def draw_clock(c: Canvas, now: datetime):
    c.text(M, 26, f"{now.year}年{now.month}月{now.day}日（{WEEKDAYS[now.weekday()]}）", 28, "SemiBold")
    hm = now.strftime("%H:%M")
    size = c.fit_size(hm, 176, "Bold", 436)
    c.text(M - 4, 222, hm, size, "Bold", anchor="ls")


def draw_outdoor(c: Canvas, w: Weather | None):
    x = 494
    c.label_box(x, 26, "屋外")
    if w is None:
        c.text(x, 90, "天気を取得できません", 20, "Medium", fill=GRAY)
        return
    cur = w.current
    c.weather_icon(cur.code, x + 44, 110, 86, cur.is_day)
    tw = c.text(x + 104, 130, f"{cur.temperature:.1f}", 62, "Bold", anchor="ls")
    c.text(x + 106 + tw, 130, "℃", 22, "Medium", anchor="ls")
    c.text(x + 106, 140, weather_label(cur.code), 26, "SemiBold")

    cells = [
        ("最高", _deg(w.today_max)), ("最低", _deg(w.today_min)), ("降水", _pct(w.precip_prob)),
        ("体感", _deg(cur.apparent)), ("湿度", _pct(cur.humidity)),
        ("風", f"{wind_direction_ja(cur.wind_direction)} {round(cur.wind_speed)}m/s"),
    ]
    for i, (label, value) in enumerate(cells):
        cx = x + 2 + (i % 3) * 90
        cy = 196 + (i // 3) * 30
        lw = c.text(cx, cy, label, 14, "Medium", fill=GRAY, anchor="ls")
        c.text(cx + lw + 6, cy, value, 18, "Medium", anchor="ls")


def draw_indoor(c: Canvas, ind: Indoor | None):
    x = 822
    c.label_box(x, 26, "室内")
    if ind is None:
        c.text(x, 90, "未設定", 20, "Medium", fill=GRAY)
        return
    temp = "—" if ind.temperature is None else f"{ind.temperature:.1f}"
    tw = c.text(x, 118, temp, 56, "Bold", anchor="ls")
    c.text(x + tw + 2, 118, "℃", 22, "Medium", anchor="ls")

    rows = [("湿度", "—" if ind.humidity is None else f"{round(ind.humidity)}", "%", 156),
            ("CO2", "—" if ind.co2 is None else str(ind.co2), "ppm", 192)]
    for label, value, unit, y in rows:
        c.text(x + 2, y, label, 14, "Medium", fill=GRAY, anchor="ls")
        vw = c.text(x + 52, y, value, 26, "Bold", anchor="ls")
        c.text(x + 56 + vw, y, unit, 15, "Medium", anchor="ls")

    level = co2_level(ind.co2)
    if level:
        bw = c.text_width(level, 16, "Bold") + 16
        c.rect(x + 2, 206, x + 2 + bw, 232, outline=BLACK, width=2)
        c.text(x + 2 + bw / 2, 219, level, 16, "Bold", anchor="mm")


def draw_hourly(c: Canvas, w: Weather | None):
    top, bottom = 246, 396
    c.line(M, top, c.w - M, top, 3)
    c.line(M, bottom, c.w - M, bottom, 3)
    slots = w.hourly if w else []
    n = 8
    cw = (c.w - 2 * M) / n
    for i in range(n):
        x0 = M + i * cw
        if i:
            c.line(x0, top + 6, x0, bottom - 6, 1, fill=LIGHT)
        if i >= len(slots):
            continue
        s, cx = slots[i], x0 + cw / 2
        c.text(cx, 256, f"{s.time.hour}時", 20, "SemiBold", anchor="ma")
        c.weather_icon(s.code, cx, 310, 52, s.is_day)
        c.text(cx, 340, _deg(s.temperature), 26, "Bold", anchor="ma")
        if s.precip_prob is not None:
            label = f"{s.precip_prob}%"
            tw = c.text_width(label, 15, "Medium")
            c.umbrella(cx - tw / 2 - 4, 382, 13)
            c.text(cx - tw / 2 + 6, 382, label, 15, "Medium", anchor="lm")


def draw_heading(c: Canvas, x0, x1, y, title, sub=""):
    tw = c.text(x0 + 4, y, title, 20, "Bold")
    if sub:
        c.text(x0 + 4 + tw + 10, y + 7, sub, 13, "Medium", fill=GRAY)
    c.line(x0, y + 32, x1, y + 32, 2)


def draw_daily(c: Canvas, w: Weather | None):
    x0, x1, y = M, 470, 410
    draw_heading(c, x0, x1, y, "この先の天気")
    for i, d in enumerate(w.daily if w else []):
        top = y + 38 + i * 36
        mid = top + 17
        c.text(x0 + 6, mid, f"{d.date.month}/{d.date.day}({WEEKDAYS[d.date.weekday()]})", 19, "Medium", anchor="lm")
        c.weather_icon(d.code, x0 + 160, mid, 32)
        c.text(x0 + 192, mid, f"{_deg(d.t_max)} / {_deg(d.t_min)}", 20, "SemiBold", anchor="lm")
        c.text(x1 - 4, mid, _pct(d.precip_prob), 17, "Medium", anchor="rm")
        c.line(x0, top + 35, x1, top + 35, 1, fill=LIGHT)


def draw_market(c: Canvas, quotes: list[Quote]):
    x0, x1, y = M, 470, 562
    times = [q.time for q in quotes if q.time]
    t = max(times) if times else None
    sub = f"{t.month}/{t.day} {t:%H:%M}時点" if t else ""
    draw_heading(c, x0, x1, y, "マーケット", sub)
    for i, q in enumerate(quotes[:3]):
        top = y + 38 + i * 39
        mid = top + 19
        c.text(x0 + 6, mid, q.label, 16, "Medium", anchor="lm")
        vw = c.text(x0 + 96, mid, _num(q.price, q.decimals), 25, "Bold", anchor="lm")
        c.text(x0 + 100 + vw, mid + 4, q.unit, 13, "Medium", anchor="lm")
        mark = "▲" if q.change > 0 else "▼" if q.change < 0 else "±"
        change = f"{mark}{_num(abs(q.change), q.decimals)} ({q.change_pct:+.2f}%)"
        c.text(x1 - 4, mid, change, 15, "SemiBold", anchor="rm")
        if i < 2:
            c.line(x0, top + 38, x1, top + 38, 1, fill=LIGHT)


def draw_news(c: Canvas, news: list[str], label: str):
    x0, x1, y = 490, c.w - M, 410
    draw_heading(c, x0, x1, y, "主要ニュース", label)
    if not news:
        c.text(x0 + 8, y + 56, "ニュースを取得できません", 18, "Medium", fill=GRAY, anchor="lm")
    for i, title in enumerate(news[:7]):
        top = y + 38 + i * 38
        mid = top + 18
        c.rect(x0 + 6, mid - 4, x0 + 13, mid + 3, fill=BLACK)
        c.text(x0 + 22, mid, c.fit(title, 17, "Medium", x1 - x0 - 26), 17, "Medium", anchor="lm")
        c.line(x0, top + 37, x1, top + 37, 1, fill=LIGHT)


def draw_footer(c: Canvas, data: DashboardData):
    y = c.h - 16
    c.battery(M, y - 7, 28, 14, data.battery)
    status = "Kindle " + ("—" if data.battery is None else f"{data.battery}%")
    if data.charging:
        status += " 充電中"
    if data.failing:
        status += "　※取得失敗: " + "・".join(data.failing)
    c.text(M + 36, y, status, 14, "Medium", anchor="lm")
    c.text(c.w - M, y, data.credits, 13, "Medium", fill=GRAY, anchor="rm")


def render(data: DashboardData, fonts: Fonts, width: int = 1024, height: int = 758) -> Image.Image:
    """横向きのダッシュボード画像（回転前・グレースケール）を返す。"""
    c = Canvas(width, height, fonts)
    draw_clock(c, data.now)
    c.line(478, 24, 478, 232, 2)
    draw_outdoor(c, data.weather)
    c.line(806, 24, 806, 232, 2)
    draw_indoor(c, data.indoor)
    draw_hourly(c, data.weather)
    draw_daily(c, data.weather)
    draw_market(c, data.quotes)
    draw_news(c, data.news, data.news_label)
    draw_footer(c, data)
    return c.finish()


def to_kindle(img: Image.Image, rotate: int) -> Image.Image:
    """16 階調に丸め、時計回りに rotate 度回転した Kindle 用画像にする。"""
    img = img.convert("L").point(lambda v: round(v / 17) * 17)
    transpose = {90: Image.Transpose.ROTATE_270, 180: Image.Transpose.ROTATE_180,
                 270: Image.Transpose.ROTATE_90}
    return img.transpose(transpose[rotate]) if rotate in transpose else img


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()
