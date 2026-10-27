"""ダッシュボード画像の描画。

横 1024 x 縦 758 の論理座標でレイアウトし、画面サイズ（PW3 なら 1448 x 1072）の 2 倍で描いてから縮小し、
16 階調のグレースケールに落として、Kindle の向きに合わせて回転する。
"""

from __future__ import annotations

import io
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from . import icons
from . import gcal
from .gcal import Event
from .sources import Indoor, Quote, Weather, co2_level, icon_kind, weather_label, wind_direction_ja

# E-ink は中間色が薄く出るので、灰色は濃いめにしておく（文字に使う GRAY でもはっきり読める濃さ）
BLACK, DARK, GRAY, LIGHT, WHITE = 0, 34, 68, 153, 255
WEIGHTS = ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"]
WEEKDAYS = "月火水木金土日"

FONT_CANDIDATES = [
    "fonts/NotoSansJP-VF.ttf",
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
    quotes: list[Quote | str] = field(default_factory=list)  # str は未取得の銘柄名
    news: list[str] = field(default_factory=list)
    indoor: Indoor | None = None
    battery: int | None = None
    charging: bool = False
    failing: list[str] = field(default_factory=list)
    news_label: str = "NHKニュース"
    events: list[Event] | None = None  # None ならニュース、リストなら今月のカレンダーを出す
    week_start: str = "sunday"
    credits: str = "Open-Meteo・Yahoo Finance・三菱UFJアセット・投資信託協会"


class Fonts:
    """サイズ・太さごとのフォントをキャッシュする。可変フォントなら太さを切り替える。"""

    def __init__(self, path: str | None = None, base_dir: Path | None = None,
                 clock: dict | None = None, weight_boost: int = 0):
        self.weight_boost = weight_boost  # 指定した太さより何段階太くするか（E-ink 向け）
        candidates = ([path] if path else []) + FONT_CANDIDATES
        base = base_dir or Path.cwd()
        self._clock_path = None
        self._clock_weight = (clock or {}).get("weight", "Regular")
        self._clock_axes = (clock or {}).get("axes")  # 例 {"Weight": 900, "Width": 125}
        if clock and clock.get("font"):
            p = Path(clock["font"])
            p = p if p.is_absolute() else base / "fonts" / p
            self._clock_path = str(p) if p.exists() else None
        for c in candidates:
            p = Path(c) if Path(c).is_absolute() else base / c
            if p.exists():
                self.path = str(p)
                break
        else:
            raise FileNotFoundError(
                "日本語フォントが見つかりません。server/fetch_fonts.py を実行するか config の font_path を設定してください")
        self._cache: dict[tuple[int, str], ImageFont.FreeTypeFont] = {}

    def get(self, size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
        if self.weight_boost and weight in WEIGHTS:
            weight = WEIGHTS[min(len(WEIGHTS) - 1, WEIGHTS.index(weight) + self.weight_boost)]
        key = (size, weight)
        if key not in self._cache:
            font = ImageFont.truetype(self.path, size)
            try:
                font.set_variation_by_name(weight)
            except (OSError, ValueError):
                pass  # 可変フォントでなければ太さは変えられない
            self._cache[key] = font
        return self._cache[key]

    def clock(self, size: int) -> ImageFont.FreeTypeFont:
        """時計の数字用。指定が無い・見つからないときは日本語フォントの Bold。"""
        if not self._clock_path:
            return self.get(size, "Bold")
        key = (size, "clock")
        if key not in self._cache:
            font = ImageFont.truetype(self._clock_path, size)
            try:
                if self._clock_axes:
                    axes = font.get_variation_axes()
                    font.set_variation_by_axes(
                        [self._clock_axes.get(a["name"].decode(), a["default"]) for a in axes])
                else:
                    font.set_variation_by_name(self._clock_weight)
            except (OSError, ValueError):
                pass  # 可変フォントでなければそのまま
            self._cache[key] = font
        return self._cache[key]


LAYOUT_W, LAYOUT_H = 1024, 758  # レイアウトの論理座標（横置き）


class Canvas:
    """論理座標（1024x758）で描き、出力サイズの 2 倍の解像度で描画してから縮小する。"""

    def __init__(self, out_w: int, out_h: int, fonts: Fonts):
        self.w, self.h = LAYOUT_W, LAYOUT_H
        self.out = (out_w, out_h)
        self.s = 2 * out_w / LAYOUT_W  # 論理座標 1 あたりの内部ピクセル数
        self.fonts = fonts
        self.img = Image.new("L", (round(self.w * self.s), round(self.h * self.s)), WHITE)
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

    def garment(self, index, x, y, size, fg=BLACK, bg=WHITE, shade=LIGHT):
        kind = icons.GARMENTS.get(index)
        if kind:
            icons.garment(self.d, kind, x * self.s, y * self.s, size * self.s, fg, bg, shade)

    def umbrella_badge(self, x, y, size):
        icons.umbrella_badge(self.d, x * self.s, y * self.s, size * self.s, fg=BLACK, bg=WHITE)

    def battery(self, x, y, w, h, level):
        icons.battery(self.d, x * self.s, y * self.s, w * self.s, h * self.s, level)

    def label_box(self, x, y, txt) -> float:
        """白抜き文字の見出し。幅を返す。"""
        w = self.text_width(txt, 17, "Bold") + 16
        self.rect(x, y, x + w, y + 27, fill=DARK)
        self.text(x + w / 2, y + 14, txt, 17, "Bold", fill=WHITE, anchor="mm")
        return w

    def finish(self) -> Image.Image:
        return self.img.resize(self.out, Image.LANCZOS)


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
    size = 176
    while size > 60 and c.fonts.clock(round(size * c.s)).getlength(hm) / c.s > 436:
        size -= 4
    # 字形の上下の範囲で、日付の下（70〜224）の中央に置く（横長のフォントでも間延びしない）
    font = c.fonts.clock(round(size * c.s))
    _, top, _, bottom = font.getbbox(hm, anchor="ls")
    baseline = (70 + 224) / 2 * c.s - (top + bottom) / 2
    c.d.text(((M - 2) * c.s, baseline), hm, font=font, fill=BLACK, anchor="ls")


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


def draw_clothing(c: Canvas, w: Weather | None):
    """時計・天気の下の帯の左側: 服のイラスト（雨の日は大きな傘も）、おすすめの服装、ひとこと。"""
    cl = w.clothing if w else None
    if cl is None:
        return
    top = 238
    c.garment(cl.index, M + 4, top + 4, 62)
    rain = any(t.startswith("傘") for t in cl.tips)
    x = M + 84
    if rain:
        c.umbrella_badge(x - 6, top + 4, 62)
        x += 70
    c.text(x, top + 12, f"{cl.day_label}の服装", 14, "Medium", fill=GRAY, anchor="lm")
    c.text(x, top + 36, cl.phrase, 24, "Bold", anchor="lm")

    # ひとこと（傘は太字で先頭に）。入りきらないものは後ろから省く
    x1, y = CHART_X0 - 28, top + 61
    for tip in cl.tips:
        weight = "Bold" if tip.startswith("傘") else "Medium"
        width = c.text_width(tip, 16, weight)
        if x + width > x1:
            break
        c.text(x, y, tip, 16, weight, anchor="lm")
        x += width + 18


CHART_X0 = 494  # 気温グラフの左端（屋外欄・ニュース欄と揃える）


def draw_temp_chart(c: Canvas, w: Weather | None, now: datetime):
    """帯の右側: 対象日の 1 時間ごとの気温の折れ線。背景の棒は降水確率。"""
    hours = w.day_hours if w else []
    if len(hours) < 2:
        return
    x0, x1, y0, y1 = CHART_X0, c.w - M - 4, 264, 290  # 折れ線の範囲（y0 が上）
    base = y1 + 5  # 降水確率の棒の底・目盛りの線
    temps = [p.temperature for p in hours]
    cw = c.text(x0, 250, f"{w.day_label}の気温", 14, "Medium", fill=GRAY, anchor="lm")
    c.text(x0 + cw + 8, 250, f"{round(min(temps))}〜{round(max(temps))}°", 14, "SemiBold", anchor="lm")
    c.text(x1 + 4, 250, "■ 降水確率", 12, "Medium", fill=GRAY, anchor="rm")

    lo, hi = min(temps), max(temps)
    pad = max(0.0, 4 - (hi - lo)) / 2  # 変化が小さい日も平らに見えすぎないように
    lo, hi = lo - pad, hi + pad

    def px(h: float) -> float:
        return x0 + (x1 - x0) * h / 23

    def py(t: float) -> float:
        return y1 - (y1 - y0) * (t - lo) / (hi - lo)

    bar = (x1 - x0) / 23 * 0.7
    for p in hours:
        if p.precip_prob:
            h = (base - y0) * p.precip_prob / 100
            c.rect(px(p.time.hour) - bar / 2, base - h, px(p.time.hour) + bar / 2, base, fill=LIGHT)
    c.line(x0, base, x1, base, 1.5, fill=GRAY)
    for h in (0, 6, 12, 18):
        c.text(px(h), base + 8, str(h), 12, "Medium", fill=GRAY, anchor="mm")
    c.text(x1 + 4, base + 8, "24時", 12, "Medium", fill=GRAY, anchor="rm")

    if w.day_label == "今日":  # 現在時刻の縦線
        nx = px(now.hour + now.minute / 60)
        for yy in range(int(y0) - 6, int(base), 6):
            c.line(nx, yy, nx, yy + 3, 1, fill=DARK)

    pts = [(px(p.time.hour), py(p.temperature)) for p in hours]
    for a, b in zip(pts, pts[1:]):
        c.line(*a, *b, 3.5)

    # 最高・最低の位置に点
    for i in (temps.index(max(temps)), temps.index(min(temps))):
        x, y = pts[i]
        c.d.ellipse(((x - 3.5) * c.s, (y - 3.5) * c.s, (x + 3.5) * c.s, (y + 3.5) * c.s), fill=BLACK)


def draw_hourly(c: Canvas, w: Weather | None):
    top, bottom = 312, 408
    c.line(M, top, c.w - M, top, 2)
    c.line(M, bottom, c.w - M, bottom, 2)
    slots = w.hourly if w else []
    n = 8
    cw = (c.w - 2 * M) / n
    for i in range(n):
        x0 = M + i * cw
        if i >= len(slots):
            continue
        s, cx = slots[i], x0 + cw / 2
        c.text(cx, 315, f"{s.time.hour}時", 17, "SemiBold", anchor="ma")
        c.weather_icon(s.code, cx, 352, 30, s.is_day)
        c.text(cx, 366, _deg(s.temperature), 20, "Bold", anchor="ma")
        if s.precip_prob is not None:
            label = f"{s.precip_prob}%"
            tw = c.text_width(label, 14, "Medium")
            c.umbrella(cx - tw / 2 - 4, 397, 11)
            c.text(cx - tw / 2 + 5, 397, label, 14, "Medium", anchor="lm")


def draw_heading(c: Canvas, x0, x1, y, title, sub=""):
    tw = c.text(x0 + 4, y, title, 20, "Bold")
    if sub:
        c.text(x0 + 4 + tw + 10, y + 6, sub, 14, "Medium", fill=GRAY)
    c.line(x0, y + 32, x1, y + 32, 1.5)


# 下段左列の縦の割り付け: 見出し(38) + 3 行 + 間(24) + 見出し(38) + 3 行 = 418〜722
LOWER_TOP = 418
HEADING_H = 38
ROW_H = 34
SECTION_GAP = 24
LEFT_X0, LEFT_X1 = M, 470


def draw_daily(c: Canvas, w: Weather | None):
    x0, x1, y = LEFT_X0, LEFT_X1, LOWER_TOP
    draw_heading(c, x0, x1, y, "この先の天気")
    for i, d in enumerate(w.daily if w else []):
        mid = y + HEADING_H + i * ROW_H + ROW_H / 2
        c.text(x0 + 6, mid, f"{d.date.month}/{d.date.day}({WEEKDAYS[d.date.weekday()]})", 18, "Medium", anchor="lm")
        c.weather_icon(d.code, x0 + 150, mid, 30)
        c.text(x0 + 236, mid, _deg(d.t_max), 20, "Bold", anchor="rm")
        c.text(x0 + 246, mid, "/", 18, "Medium", fill=GRAY, anchor="mm")
        c.text(x0 + 256, mid, _deg(d.t_min), 20, "Medium", fill=DARK, anchor="lm")
        if d.precip_prob is not None:
            label = f"{d.precip_prob}%"
            c.text(x1 - 4, mid, label, 17, "Medium", anchor="rm")
            c.umbrella(x1 - 4 - c.text_width(label, 17, "Medium") - 11, mid, 13)


def draw_market(c: Canvas, quotes: list[Quote | str]):
    """quotes の要素が str のときは、まだ取得できていない銘柄のラベル。"""
    x0, x1 = LEFT_X0, LEFT_X1
    y = LOWER_TOP + HEADING_H + 3 * ROW_H + SECTION_GAP
    times = [q.time for q in quotes if isinstance(q, Quote) and q.time]
    t = max(times) if times else None
    sub = f"{t.month}/{t.day} {t:%H:%M}時点" if t else ""
    draw_heading(c, x0, x1, y, "マーケット", sub)
    value_right = x0 + 214  # 数値は右揃えで桁を合わせる
    for i, q in enumerate(quotes[:3]):
        mid = y + HEADING_H + i * ROW_H + ROW_H / 2
        if isinstance(q, str):
            c.text(x0 + 6, mid, q, 16, "Medium", anchor="lm")
            c.text(value_right, mid, "—", 24, "Bold", anchor="rm")
            continue
        if q.as_of:  # 投資信託は基準日をラベルの下に出す
            c.text(x0 + 6, mid - 6, q.label, 16, "Medium", anchor="lm")
            c.text(x0 + 6, mid + 10, f"{q.as_of.month}/{q.as_of.day}基準", 12, "Medium", fill=GRAY, anchor="lm")
        else:
            c.text(x0 + 6, mid, q.label, 16, "Medium", anchor="lm")
        c.text(value_right, mid, _num(q.price, q.decimals), 24, "Bold", anchor="rm")
        c.text(value_right + 4, mid + 4, q.unit, 13, "Medium", anchor="lm")
        mark = "▲" if q.change > 0 else "▼" if q.change < 0 else "±"
        change = f"{mark}{_num(abs(q.change), q.decimals)} ({q.change_pct:+.2f}%)"
        c.text(x1 - 4, mid, change, 15, "SemiBold", anchor="rm")


def draw_news(c: Canvas, news: list[str], label: str):
    x0, x1, y = 490, c.w - M, 418
    draw_heading(c, x0, x1, y, "主要ニュース", label)
    if not news:
        c.text(x0 + 8, y + 56, "ニュースを取得できません", 18, "Medium", fill=GRAY, anchor="lm")
    for i, title in enumerate(news[:7]):
        top = y + 38 + i * 38
        mid = top + 18
        c.rect(x0 + 6, mid - 3, x0 + 11, mid + 2, fill=GRAY)
        c.text(x0 + 20, mid, c.fit(title, 17, "Medium", x1 - x0 - 24), 17, "Medium", anchor="lm")


def draw_month(c: Canvas, events: list[Event], now: datetime, week_start: str = "sunday"):
    """ニュース欄の代わりに今月のカレンダー。祝日・終日予定は灰色の帯、今日は日付を白黒反転。"""
    x0, x1, y = 490, c.w - M, LOWER_TOP
    draw_heading(c, x0, x1, y, f"{now.year}年{now.month}月", "Googleカレンダー")
    grid = gcal.month_grid(now.date(), week_start)
    events = events + gcal.holidays(grid[0][0], grid[-1][-1], now.tzinfo)
    names = "日月火水木金土" if week_start == "sunday" else "月火水木金土日"
    cw = (x1 - x0) / 7
    head_y = y + 46
    for i, name in enumerate(names):
        weekend = name in "日土"
        c.text(x0 + cw * i + cw / 2, head_y, name, 13, "Bold" if weekend else "Medium",
               fill=BLACK if weekend else GRAY, anchor="mm")

    top, bottom = head_y + 10, 722
    rh = (bottom - top) / len(grid)
    line_h, size = 14, 11.5
    for r, week in enumerate(grid):
        ry = top + r * rh
        c.line(x0, ry, x1, ry, 1.5, fill=LIGHT)
        for i, day in enumerate(week):
            cx = x0 + i * cw
            in_month = day.month == now.month
            past = day < now.date()
            color = BLACK if in_month and not past else GRAY if in_month else LIGHT
            if day == now.date():
                c.rect(cx + 2, ry + 3, cx + 24, ry + 19, fill=BLACK)
                c.text(cx + 13, ry + 11, str(day.day), 13, "Bold", fill=WHITE, anchor="mm")
            else:
                c.text(cx + 13, ry + 11, str(day.day), 13, "Bold", fill=color, anchor="mm")
            if not in_month:
                continue
            todays = gcal.events_on(events, day)
            room = max(0, int((rh - 21) // line_h))
            shown = todays[:room]
            for k, ev in enumerate(shown):
                ey = ry + 21 + k * line_h + line_h / 2
                fill = GRAY if past else BLACK
                if ev.all_day:  # 終日・祝日は帯
                    c.rect(cx + 2, ey - line_h / 2 + 1, cx + cw - 2, ey + line_h / 2 - 1, fill=LIGHT)
                c.text(cx + 4, ey, c.fit(ev.title, size, "Medium", cw - 8), size, "Medium", fill=fill, anchor="lm")
            if len(todays) > len(shown):  # 入りきらない件数は日付の右に
                c.text(cx + cw - 4, ry + 11, f"+{len(todays) - len(shown)}", 12, "Bold", fill=GRAY, anchor="rm")


def draw_footer(c: Canvas, data: DashboardData):
    y = c.h - 16
    c.battery(M, y - 7, 28, 14, data.battery)
    status = "Kindle " + ("—" if data.battery is None else f"{data.battery}%")
    if data.charging:
        status += " 充電中"
    if data.failing:
        status += "　※取得失敗: " + "・".join(data.failing)
    c.text(M + 36, y, status, 14, "Medium", anchor="lm")
    c.text(c.w - M, y, data.credits, 12, "Medium", fill=GRAY, anchor="rm")


def render(data: DashboardData, fonts: Fonts, width: int = LAYOUT_W, height: int = LAYOUT_H) -> Image.Image:
    """横向きのダッシュボード画像（回転前・グレースケール, width x height px）を返す。

    レイアウトは 1024x758 で組み、出力サイズに合わせて拡大して描く（PW3 の 1448x1072 なら約 1.41 倍）。
    """
    c = Canvas(width, height, fonts)
    draw_clock(c, data.now)
    c.line(478, 24, 478, 232, 2)
    draw_outdoor(c, data.weather)
    c.line(806, 24, 806, 232, 2)
    draw_indoor(c, data.indoor)
    draw_clothing(c, data.weather)
    draw_temp_chart(c, data.weather, data.now)
    draw_hourly(c, data.weather)
    draw_daily(c, data.weather)
    draw_market(c, data.quotes)
    if data.events is None:
        draw_news(c, data.news, data.news_label)
    else:
        draw_month(c, data.events, data.now, data.week_start)
    draw_footer(c, data)
    return c.finish()


def to_kindle(img: Image.Image, rotate: int, gamma: float = 1.0) -> Image.Image:
    """濃さを補正して 16 階調に丸め、時計回りに rotate 度回転した Kindle 用画像にする。

    gamma > 1 で中間色を濃くする（E-ink で文字の輪郭や灰色が飛ばないように）。
    """
    img = img.convert("L").point(lambda v: round(255 * (v / 255) ** gamma / 17) * 17)
    transpose = {90: Image.Transpose.ROTATE_270, 180: Image.Transpose.ROTATE_180,
                 270: Image.Transpose.ROTATE_90}
    return img.transpose(transpose[rotate]) if rotate in transpose else img


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()
