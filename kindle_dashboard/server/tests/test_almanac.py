"""二十四節気・雑節・ゴミ出し。"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from dashboard import almanac, web


@pytest.mark.parametrize("day,name", [
    # 国立天文台の暦要項の日付
    (date(2024, 2, 4), "立春"), (date(2024, 3, 20), "春分"), (date(2024, 6, 21), "夏至"),
    (date(2024, 9, 22), "秋分"), (date(2024, 12, 21), "冬至"),
    (date(2025, 2, 3), "立春"), (date(2025, 9, 23), "秋分"), (date(2025, 12, 22), "冬至"),
    (date(2026, 3, 20), "春分"), (date(2026, 11, 7), "立冬"),
])
def test_sekki_dates(day, name):
    assert almanac.sekki_of(day) == name


def test_24_sekki_per_year():
    names = [n for ns in almanac.year_table(2026).values() for n in ns if n in almanac.SEKKI]
    assert sorted(names) == sorted(almanac.SEKKI)


@pytest.mark.parametrize("day,name", [
    (date(2025, 2, 2), "節分"), (date(2025, 5, 1), "八十八夜"), (date(2025, 6, 11), "入梅"),
    (date(2025, 7, 1), "半夏生"), (date(2025, 7, 19), "夏の土用入り"), (date(2025, 8, 31), "二百十日"),
    (date(2025, 9, 20), "彼岸入り"), (date(2025, 9, 26), "彼岸明け"), (date(2024, 6, 10), "入梅"),
])
def test_zassetsu(day, name):
    assert name in almanac.zassetsu_of(day)


def test_ordinary_day_is_empty():
    assert almanac.sekki_of(date(2026, 11, 8)) is None
    assert almanac.zassetsu_of(date(2026, 11, 8)) == []


CFG = {"garbage": {"rules": [
    {"name": "燃えるゴミ", "weekdays": ["月", "木"]},
    {"name": "不燃ゴミ", "weekdays": ["水"], "weeks": [2, 4]},
    {"name": "粗大ゴミ", "dates": ["2026-11-20"]},
    {"name": "資源", "weekdays": ["金"], "except": ["2026-11-13"]},
], "except": ["12-31", "01-01"]}}


@pytest.mark.parametrize("day,expect", [
    (date(2026, 11, 9), ["燃えるゴミ"]),              # 月
    (date(2026, 11, 11), ["不燃ゴミ"]),               # 第2水曜
    (date(2026, 11, 4), []),                          # 第1水曜
    (date(2026, 11, 25), ["不燃ゴミ"]),               # 第4水曜
    (date(2026, 11, 13), []),                         # 金だが except
    (date(2026, 11, 20), ["粗大ゴミ", "資源"]),        # 個別の日＋金
    (date(2026, 12, 31), ["燃えるゴミ"]),             # 木 → 全体の休み… ではないので下で
])
def test_garbage(day, expect):
    if day == date(2026, 12, 31):
        assert almanac.garbage_on(CFG, day) == []  # 12-31 は全体の休み
        return
    assert almanac.garbage_on(CFG, day) == expect


def test_garbage_unset():
    assert almanac.garbage_on({}, date(2026, 11, 9)) == []


def test_today_info_in_payload():
    now = datetime(2026, 11, 7, 20, 0, tzinfo=ZoneInfo("Asia/Tokyo"))  # 土曜・立冬
    t = web.today_info(CFG, now)
    assert t["sekki"] == "立冬" and t["garbage"] == [] and t["garbage_tomorrow"] == []
    t = web.today_info(CFG, datetime(2026, 11, 8, 20, 0, tzinfo=ZoneInfo("Asia/Tokyo")))
    assert t["garbage_tomorrow"] == ["燃えるゴミ"] and t["garbage_until"] == "09:00"
