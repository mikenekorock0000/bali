"""Fire タブレットなどブラウザで表示するカラー版（/fire）に渡す JSON。

描画は fire.html（ブラウザ側）。ここでは表示する文字列まで作って渡すので、HTML 側は並べるだけ。
"""

from __future__ import annotations

from datetime import datetime, timedelta

from . import gcal
from .gcal import Event
from .render import DashboardData, _num
from .sources import Quote, co2_level, comfort_level, icon_kind, weather_label, wind_direction_ja

WEEKDAYS = "月火水木金土日"


def _r(v: float | None) -> int | None:
    return None if v is None else round(v)


def _weather(data: DashboardData) -> dict | None:
    w = data.weather
    if not w:
        return None
    c = w.current
    out = {
        "temp": round(c.temperature, 1),
        "apparent": _r(c.apparent),
        "humidity": _r(c.humidity),
        "label": weather_label(c.code),
        "icon": icon_kind(c.code),
        "is_day": c.is_day,
        "wind": f"{wind_direction_ja(c.wind_direction)} {c.wind_speed:.0f}m/s",
        "max": _r(w.today_max),
        "min": _r(w.today_min),
        "pop": w.precip_prob,
        "hourly": [{"time": f"{h.time.hour}時", "icon": icon_kind(h.code), "is_day": h.is_day,
                    "temp": _r(h.temperature), "pop": h.precip_prob} for h in w.hourly[:8]],
        "daily": [{"date": f"{d.date.month}/{d.date.day}", "weekday": WEEKDAYS[d.date.weekday()],
                   "weekend": d.date.weekday() >= 5, "icon": icon_kind(d.code), "label": weather_label(d.code),
                   "max": _r(d.t_max), "min": _r(d.t_min), "pop": d.precip_prob} for d in w.daily[:3]],
        "chart_label": w.day_label,
        "chart": [{"h": p.time.hour, "temp": round(p.temperature, 1), "pop": p.precip_prob}
                  for p in w.day_hours],
        "clothing": None,
    }
    if w.clothing:
        cl = w.clothing
        out["clothing"] = {"index": cl.index, "phrase": cl.phrase, "day": cl.day_label, "tips": cl.tips}
    return out


def _indoor(data: DashboardData) -> dict | None:
    ind = data.indoor
    if not ind:
        return None
    return {"temp": None if ind.temperature is None else round(ind.temperature, 1),
            "humidity": _r(ind.humidity), "co2": ind.co2,
            "level": co2_level(ind.co2) if ind.co2 is not None else comfort_level(ind.humidity)}


def _quote(q: Quote | str) -> dict:
    if isinstance(q, str):
        return {"label": q, "missing": True}
    note = (f"{q.as_of.month}/{q.as_of.day} 基準" if q.as_of
            else f"{q.time:%H:%M}" if q.time else "")
    return {"label": q.label, "price": _num(q.price, q.decimals), "unit": q.unit,
            "change": ("+" if q.change > 0 else "−" if q.change < 0 else "±") + _num(abs(q.change), q.decimals),
            "pct": f"{q.change_pct:+.2f}%", "dir": (q.change > 0) - (q.change < 0), "note": note}


def upcoming(events: list[Event] | None, now: datetime, days: int = 7, limit: int = 8) -> list[dict]:
    """今日から days 日分の予定（祝日を含む）。終わった予定は出さない。"""
    if events is None:
        return []
    start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=days)
    allev = list(events) + gcal.holidays(start.date(), end.date(), now.tzinfo)
    out = []
    for e in sorted(allev, key=lambda e: (e.start, not e.all_day)):
        if e.end <= now or e.start >= end:
            continue
        day = max(e.start, start)  # 前日から続く終日予定は今日の欄に
        out.append({"title": e.title, "date": f"{day.month}/{day.day}", "weekday": WEEKDAYS[day.weekday()],
                    "time": "終日" if e.all_day else f"{e.start:%H:%M}",
                    "today": day.date() == now.date(), "holiday": e.holiday})
        if len(out) >= limit:
            break
    return out


def payload(data: DashboardData, events: list[Event] | None = None, version: str = "") -> dict:
    now = data.now
    return {
        "version": version,
        "now": now.isoformat(),
        "weather": _weather(data),
        "indoor": _indoor(data),
        "quotes": [_quote(q) for q in data.quotes],
        "news": data.news,
        "news_label": data.news_label,
        "events": upcoming(events, now),
        "failing": data.failing,
        "credits": data.credits,
    }
