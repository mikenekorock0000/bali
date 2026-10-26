"""Google カレンダー（iCal 形式の非公開 URL）から今月の予定を読む。

Google カレンダー → 設定 → 対象のカレンダー →「カレンダーの統合」→「iCal 形式の非公開 URL」
をコピーして使う。OAuth の設定は不要。繰り返し予定も展開する。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import jpholiday
import recurring_ical_events
from icalendar import Calendar

from .sources import http_get


@dataclass
class Event:
    title: str
    start: datetime  # 終日予定はその日の 0:00
    end: datetime
    all_day: bool
    holiday: bool = False  # 祝日（カレンダーではなく jpholiday から）


def _to_datetime(value, tz: ZoneInfo) -> tuple[datetime, bool]:
    if isinstance(value, datetime):
        if value.tzinfo is None:  # 時刻だけでタイムゾーンの無い予定は現地時刻とみなす
            return value.replace(tzinfo=tz), False
        return value.astimezone(tz), False
    return datetime.combine(value, time(), tz), True


def parse_events(ics_list: list[bytes], first: date, last: date, tz: ZoneInfo) -> list[Event]:
    """first〜last（両端含む）にかかる予定を、終日 → 開始時刻順に並べて返す。"""
    start = datetime.combine(first, time(), tz)
    end = datetime.combine(last + timedelta(days=1), time(), tz)
    events = []
    for ics in ics_list:
        cal = Calendar.from_ical(ics)
        for comp in recurring_ical_events.of(cal).between(start, end):
            if str(comp.get("STATUS", "")).upper() == "CANCELLED":
                continue
            s, all_day = _to_datetime(comp.decoded("DTSTART"), tz)
            if "DTEND" in comp:
                e, _ = _to_datetime(comp.decoded("DTEND"), tz)
            else:
                e = s + (timedelta(days=1) if all_day else timedelta(0))
            title = str(comp.get("SUMMARY", "")).strip() or "（無題）"
            events.append(Event(title, s, e, all_day))
    return sorted(events, key=lambda ev: (not ev.all_day, ev.start, ev.title))


def month_grid(day: date, week_start: str = "sunday") -> list[list[date]]:
    """day を含む月のカレンダー（週ごとの日付。前後の月の日も含む）。"""
    first = day.replace(day=1)
    offset = (first.weekday() + (1 if week_start == "sunday" else 0)) % 7
    d = first - timedelta(days=offset)
    weeks = []
    while not weeks or d.month == day.month:
        weeks.append([d + timedelta(days=i) for i in range(7)])
        d += timedelta(days=7)
    return weeks


def holidays(first: date, last: date, tz: ZoneInfo) -> list[Event]:
    return [Event(name, datetime.combine(d, time(), tz), datetime.combine(d + timedelta(days=1), time(), tz),
                  True, holiday=True)
            for d, name in jpholiday.between(first, last)]


def events_on(events: list[Event], day: date) -> list[Event]:
    """その日にかかる予定（祝日 → 終日 → 時刻順）。"""
    tz = events[0].start.tzinfo if events else None
    start = datetime.combine(day, time(), tz)
    end = start + timedelta(days=1)
    hits = [e for e in events if e.start < end and (e.end > start or (e.end == e.start and e.start >= start))]
    return sorted(hits, key=lambda e: (not e.holiday, not e.all_day, e.start, e.title))


def fetch_events(urls: list[str], now: datetime, week_start: str = "sunday") -> list[Event]:
    """今月のカレンダーに表示する範囲（前後の週の端数を含む）の予定。"""
    grid = month_grid(now.date(), week_start)
    return parse_events([http_get(u, timeout=30) for u in urls], grid[0][0], grid[-1][-1], now.tzinfo)


def calendar_urls(cfg: dict, env: dict[str, str]) -> list[str]:
    """config の calendar.ics_urls と、環境変数 CALENDAR_ICS_URLS（カンマ区切り）。"""
    urls = list((cfg.get("calendar") or {}).get("ics_urls") or [])
    urls += [u.strip() for u in env.get("CALENDAR_ICS_URLS", "").split(",") if u.strip()]
    return urls


def in_window(now: datetime, window: tuple[str, str]) -> bool:
    """now が "HH:MM"〜"HH:MM" の間か（日をまたぐ指定にも対応）。"""
    def minutes(hhmm: str) -> int:
        h, m = hhmm.split(":")
        return int(h) * 60 + int(m)

    t, a, b = now.hour * 60 + now.minute, minutes(window[0]), minutes(window[1])
    return a <= t < b if a <= b else (t >= a or t < b)
