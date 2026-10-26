from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from dashboard.clothing import HourPoint, clothing_advice, level_for

TZ = ZoneInfo("Asia/Tokyo")


def day_points(start: datetime, temps, apparent=None, pops=None, winds=None):
    n = len(temps)
    apparent = apparent or temps
    pops = pops or [0] * n
    winds = winds or [1.0] * n
    return [HourPoint(start + timedelta(hours=i), temps[i], apparent[i], pops[i], winds[i]) for i in range(n)]


@pytest.mark.parametrize("feels,index,phrase", [
    (31, 90, "ノースリーブでもOK"), (25, 80, "半袖で快適"), (22, 70, "半袖＋薄い羽織りを"),
    (19, 60, "長袖シャツで快適"), (14, 50, "薄手のセーターを"), (10, 40, "ジャケットが必要"),
    (6, 30, "コートが必要"), (0, 20, "厚手のコートを"), (-3, 10, "ダウン・手袋で防寒"),
])
def test_level_for(feels, index, phrase):
    assert level_for(feels) == (index, phrase)


def test_uses_remaining_daytime_hours_today():
    now = datetime(2026, 10, 26, 9, 30, tzinfo=TZ)
    # 0時から 24 時間分: 早朝は寒いが 9 時以降は 18〜20℃
    temps = [5] * 9 + [18, 19, 20, 20, 20, 20, 19, 19, 18, 18, 18, 18, 18, 10, 10]
    c = clothing_advice(day_points(now.replace(hour=0, minute=0), temps), now)
    assert c.day_label == "今日"
    assert c.index == 60 and c.tips == []


def test_switches_to_tomorrow_in_the_evening():
    now = datetime(2026, 10, 26, 19, 0, tzinfo=TZ)
    today = day_points(now.replace(hour=0, minute=0), [20] * 24)
    tomorrow = day_points(now.replace(hour=0, minute=0) + timedelta(days=1), [6] * 24)
    c = clothing_advice(today + tomorrow, now)
    assert c.day_label == "明日"
    assert (c.index, c.phrase) == (30, "コートが必要")


def test_tips_for_rain_swing_and_wind():
    now = datetime(2026, 10, 26, 6, 0, tzinfo=TZ)
    temps = [8, 10, 12, 14, 16, 18, 19, 19, 18, 16, 14, 12, 11, 10, 9, 9]  # 6〜21時
    pops = [0] * 10 + [70] + [0] * 5
    winds = [3.0] * 15 + [9.4]
    c = clothing_advice(day_points(now, temps, pops=pops, winds=winds), now)
    assert c.tips == ["傘を持って", "寒暖差 11℃", "風が強い 9m/s"]


def test_no_data_for_the_day():
    now = datetime(2026, 10, 26, 10, 0, tzinfo=TZ)
    assert clothing_advice([], now) is None
