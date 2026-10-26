from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from dashboard import gcal
from dashboard.app import Dashboard, load_config
from dashboard.store import DataStore

TZ = ZoneInfo("Asia/Tokyo")

ICS = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Google Inc//Google Calendar 70.9054//EN
X-WR-TIMEZONE:Asia/Tokyo
BEGIN:VEVENT
UID:weekly@example
DTSTART;TZID=Asia/Tokyo:20261005T100000
DTEND;TZID=Asia/Tokyo:20261005T110000
RRULE:FREQ=WEEKLY;BYDAY=MO
SUMMARY:チーム定例
END:VEVENT
BEGIN:VEVENT
UID:allday@example
DTSTART;VALUE=DATE:20261026
DTEND;VALUE=DATE:20261027
SUMMARY:燃えるゴミの日
END:VEVENT
BEGIN:VEVENT
UID:utc@example
DTSTART:20261025T213000Z
DTEND:20261025T220000Z
SUMMARY:朝ラン
END:VEVENT
BEGIN:VEVENT
UID:cancelled@example
DTSTART;TZID=Asia/Tokyo:20261026T150000
DTEND;TZID=Asia/Tokyo:20261026T160000
STATUS:CANCELLED
SUMMARY:中止
END:VEVENT
BEGIN:VEVENT
UID:other-day@example
DTSTART;TZID=Asia/Tokyo:20261027T090000
DTEND;TZID=Asia/Tokyo:20261027T100000
SUMMARY:明日の予定
END:VEVENT
END:VCALENDAR
""".encode()

OTHER = """BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:x@example
DTSTART;TZID=Asia/Tokyo:20261026T083000
DTEND;TZID=Asia/Tokyo:20261026T090000
SUMMARY:家族カレンダーの予定
END:VEVENT
END:VCALENDAR
""".encode()


def test_parse_events_expands_recurrence_and_sorts():
    events = gcal.parse_events([ICS, OTHER], date(2026, 10, 26), TZ)
    assert [e.title for e in events] == ["燃えるゴミの日", "朝ラン", "家族カレンダーの予定", "チーム定例"]
    assert events[0].all_day
    assert events[1].start == datetime(2026, 10, 26, 6, 30, tzinfo=TZ)  # UTC → 日本時間
    assert events[3].start.hour == 10


def test_parse_events_other_weekday_has_no_weekly_event():
    titles = [e.title for e in gcal.parse_events([ICS], date(2026, 10, 27), TZ)]
    assert titles == ["明日の予定"]


@pytest.mark.parametrize("hhmm,expected", [("02:59", False), ("03:00", True), ("08:59", True), ("09:00", False)])
def test_in_window(hhmm, expected):
    h, m = map(int, hhmm.split(":"))
    assert gcal.in_window(datetime(2026, 10, 26, h, m, tzinfo=TZ), ("03:00", "09:00")) is expected


def test_in_window_across_midnight():
    assert gcal.in_window(datetime(2026, 10, 26, 23, 0, tzinfo=TZ), ("22:00", "02:00"))
    assert not gcal.in_window(datetime(2026, 10, 26, 12, 0, tzinfo=TZ), ("22:00", "02:00"))


def test_calendar_urls_from_config_and_env():
    cfg = {"calendar": {"ics_urls": ["https://a/basic.ics"]}}
    assert gcal.calendar_urls(cfg, {"CALENDAR_ICS_URLS": "https://b.ics, https://c.ics"}) == [
        "https://a/basic.ics", "https://b.ics", "https://c.ics"]


def _dash(hour, value):
    cfg = load_config(None)
    store = DataStore()
    store.add("calendar", "予定", lambda: value, 900)
    store.refresh_due()
    now = datetime(2026, 10, 26, hour, 0, tzinfo=TZ)
    return Dashboard(cfg, store, None, lambda: now).data()


def test_dashboard_shows_events_only_in_window():
    events = gcal.parse_events([ICS], date(2026, 10, 26), TZ)
    assert _dash(7, events).events == events
    assert _dash(10, events).events is None  # 時間帯外はニュース


def test_dashboard_falls_back_to_news_when_calendar_unavailable():
    assert _dash(7, None).events is None
