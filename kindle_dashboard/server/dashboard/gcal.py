"""Google カレンダー（iCal 形式の非公開 URL）から今日の予定を読む。

Google カレンダー → 設定 → 対象のカレンダー →「カレンダーの統合」→「iCal 形式の非公開 URL」
をコピーして使う。OAuth の設定は不要。繰り返し予定も展開する。
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import recurring_ical_events
from icalendar import Calendar

from .sources import http_get


@dataclass
class Event:
    title: str
    start: datetime  # 終日予定はその日の 0:00
    end: datetime
    all_day: bool


def _to_datetime(value, tz: ZoneInfo) -> tuple[datetime, bool]:
    if isinstance(value, datetime):
        if value.tzinfo is None:  # 時刻だけでタイムゾーンの無い予定は現地時刻とみなす
            return value.replace(tzinfo=tz), False
        return value.astimezone(tz), False
    return datetime.combine(value, time(), tz), True


def parse_events(ics_list: list[bytes], day: date, tz: ZoneInfo) -> list[Event]:
    """その日にかかる予定を、終日 → 開始時刻順に並べて返す。"""
    start = datetime.combine(day, time(), tz)
    end = start + timedelta(days=1)
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


def fetch_events(urls: list[str], now: datetime) -> list[Event]:
    return parse_events([http_get(u, timeout=30) for u in urls], now.date(), now.tzinfo)


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
