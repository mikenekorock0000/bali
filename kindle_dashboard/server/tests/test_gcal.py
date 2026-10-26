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


def test_parse_events_expands_recurrence_over_month():
    events = gcal.parse_events([ICS, OTHER], date(2026, 9, 27), date(2026, 10, 31), TZ)
    weekly = [e.start.day for e in events if e.title == "チーム定例"]
    assert weekly == [5, 12, 19, 26]  # 毎週月曜
    assert "中止" not in [e.title for e in events]


def test_events_on_day_sorted_and_utc_converted():
    events = gcal.parse_events([ICS, OTHER], date(2026, 9, 27), date(2026, 10, 31), TZ)
    day = gcal.events_on(events, date(2026, 10, 26))
    assert [e.title for e in day] == ["燃えるゴミの日", "朝ラン", "家族カレンダーの予定", "チーム定例"]
    assert day[1].start == datetime(2026, 10, 26, 6, 30, tzinfo=TZ)  # UTC → 日本時間
    assert [e.title for e in gcal.events_on(events, date(2026, 10, 27))] == ["明日の予定"]


def test_multi_day_all_day_event_appears_on_each_day():
    ev = gcal.Event("旅行", datetime(2026, 10, 3, tzinfo=TZ), datetime(2026, 10, 5, tzinfo=TZ), True)
    assert [bool(gcal.events_on([ev], date(2026, 10, d))) for d in (2, 3, 4, 5)] == [False, True, True, False]


def test_holidays_come_first():
    hol = gcal.holidays(date(2026, 10, 1), date(2026, 10, 31), TZ)
    assert [(e.start.day, e.title) for e in hol] == [(12, "スポーツの日")]
    ev = gcal.Event("朝の予定", datetime(2026, 10, 12, 7, tzinfo=TZ), datetime(2026, 10, 12, 8, tzinfo=TZ), False)
    assert [e.title for e in gcal.events_on([ev] + hol, date(2026, 10, 12))] == ["スポーツの日", "朝の予定"]


@pytest.mark.parametrize("day,week_start,weeks,first,last", [
    (date(2026, 10, 26), "sunday", 5, date(2026, 9, 27), date(2026, 10, 31)),
    (date(2026, 2, 10), "sunday", 4, date(2026, 2, 1), date(2026, 2, 28)),
    (date(2026, 8, 1), "sunday", 6, date(2026, 7, 26), date(2026, 9, 5)),
    (date(2026, 10, 26), "monday", 5, date(2026, 9, 28), date(2026, 11, 1)),
])
def test_month_grid(day, week_start, weeks, first, last):
    grid = gcal.month_grid(day, week_start)
    assert len(grid) == weeks and grid[0][0] == first and grid[-1][-1] == last
    assert all(len(w) == 7 for w in grid)


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
    events = gcal.parse_events([ICS], date(2026, 9, 27), date(2026, 10, 31), TZ)
    assert _dash(7, events).events == events
    assert _dash(10, events).events is None  # 時間帯外はニュース


def test_dashboard_falls_back_to_news_when_calendar_unavailable():
    assert _dash(7, None).events is None
