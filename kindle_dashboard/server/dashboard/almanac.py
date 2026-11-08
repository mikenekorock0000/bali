"""暦（二十四節気・雑節）とゴミ出しの日。

二十四節気は太陽の黄経が 15° の倍数になる日。黄経は Meeus『Astronomical Algorithms』の
簡略式（精度 0.01° ≒ 15 分）で計算するので、毎年の表は要らない。
"""

from __future__ import annotations

import math
from datetime import date, datetime, time, timedelta, timezone
from functools import lru_cache

JST = timezone(timedelta(hours=9))

# 黄経 0° = 春分 から 15° ごと
SEKKI = ["春分", "清明", "穀雨", "立夏", "小満", "芒種", "夏至", "小暑", "大暑", "立秋", "処暑", "白露",
         "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至", "小寒", "大寒", "立春", "雨水", "啓蟄"]
# 黄経で決まる雑節（その黄経を過ぎた日）
LONGITUDE_ZASSETSU = {80: "入梅", 100: "半夏生", 27: "春の土用入り", 117: "夏の土用入り",
                      207: "秋の土用入り", 297: "冬の土用入り"}
WEEKDAYS = "月火水木金土日"


def solar_longitude(dt: datetime) -> float:
    """太陽の視黄経（度, 0〜360）。"""
    jd = dt.timestamp() / 86400 + 2440587.5
    t = (jd - 2451545.0) / 36525
    l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
    m = math.radians(357.52911 + 35999.05029 * t - 0.0001537 * t * t)
    c = ((1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(m)
         + (0.019993 - 0.000101 * t) * math.sin(2 * m) + 0.000289 * math.sin(3 * m))
    omega = math.radians(125.04 - 1934.136 * t)
    return (l0 + c - 0.00569 - 0.00478 * math.sin(omega)) % 360


def _crossed(day: date, deg: float) -> bool:
    """その日（日本時間 0:00〜24:00）の間に、太陽の黄経が deg 度を通過するか。"""
    a = solar_longitude(datetime.combine(day, time(), JST))
    b = solar_longitude(datetime.combine(day + timedelta(days=1), time(), JST))
    return ((deg - a) % 360) < ((b - a) % 360)


@lru_cache(maxsize=8)
def year_table(year: int) -> dict[date, list[str]]:
    """その年の 二十四節気・雑節 → 日付。"""
    table: dict[date, list[str]] = {}
    d = date(year, 1, 1)
    sekki_day: dict[str, date] = {}
    while d.year == year:
        for i, name in enumerate(SEKKI):
            if _crossed(d, i * 15):
                table.setdefault(d, []).append(name)
                sekki_day[name] = d
        for deg, name in LONGITUDE_ZASSETSU.items():
            if _crossed(d, deg):
                table.setdefault(d, []).append(name)
        d += timedelta(days=1)

    def add(day: date | None, name: str):
        if day and day.year == year:
            table.setdefault(day, []).append(name)

    risshun = sekki_day.get("立春")
    if risshun:
        add(risshun - timedelta(days=1), "節分")
        add(risshun + timedelta(days=87), "八十八夜")
        add(risshun + timedelta(days=209), "二百十日")
    for eq in ("春分", "秋分"):
        if eq in sekki_day:
            add(sekki_day[eq] - timedelta(days=3), "彼岸入り")
            add(sekki_day[eq] + timedelta(days=3), "彼岸明け")
    return table


def sekki_of(day: date) -> str | None:
    names = year_table(day.year).get(day, [])
    return next((n for n in names if n in SEKKI), None)


def zassetsu_of(day: date) -> list[str]:
    return [n for n in year_table(day.year).get(day, []) if n not in SEKKI]


# ---------------------------------------------------------------- ゴミ出し

def _matches(rule: dict, day: date) -> bool:
    key_full, key_md = day.isoformat(), day.strftime("%m-%d")
    if key_full in rule.get("except", []) or key_md in rule.get("except", []):
        return False
    if key_full in rule.get("dates", []):
        return True
    weekdays = rule.get("weekdays") or []
    if WEEKDAYS[day.weekday()] not in weekdays and day.weekday() not in weekdays:
        return False
    weeks = rule.get("weeks")  # 第何週（その曜日が月の何回目か）
    return not weeks or (day.day - 1) // 7 + 1 in weeks


def garbage_on(cfg: dict, day: date) -> list[str]:
    """config の garbage.rules から、その日に出せるゴミの名前。"""
    g = cfg.get("garbage") or {}
    skip = g.get("except", [])  # 全部休み（年末年始など）
    if day.isoformat() in skip or day.strftime("%m-%d") in skip:
        return []
    return [r["name"] for r in g.get("rules", []) if r.get("name") and _matches(r, day)]
