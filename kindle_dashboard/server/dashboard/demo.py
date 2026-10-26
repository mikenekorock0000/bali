"""ネットワークなしで見た目を確認するためのダミーデータ。"""

from __future__ import annotations

from datetime import datetime, timedelta

from .clothing import Clothing, HourPoint
from .gcal import Event
from .render import DashboardData
from .sources import Current, DaySlot, HourSlot, Indoor, Quote, Weather


def demo_day_hours(now: datetime) -> list[HourPoint]:
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    temps = [14, 14, 13, 13, 12, 12, 13, 14, 16, 18, 19, 20, 20, 20, 20, 19,
             19, 19, 19, 19, 19, 19, 19, 19]
    pops = [0, 0, 0, 0, 5, 10, 20, 30, 40, 60, 80, 90, 100, 100, 100, 100,
            100, 100, 100, 98, 98, 98, 98, 95]
    return [HourPoint(midnight + timedelta(hours=h), t, t + 1, p, 2.0)
            for h, (t, p) in enumerate(zip(temps, pops))]


def demo_events(now: datetime) -> list[Event]:
    day = now.replace(hour=0, minute=0, second=0, microsecond=0)

    def at(h, m=0):
        return day + timedelta(hours=h, minutes=m)

    return [
        Event("燃えるゴミの日", day, day + timedelta(days=1), True),
        Event("朝ラン", at(6), at(6, 45), False),
        Event("子ども 遠足（お弁当）", at(7, 30), at(8), False),
        Event("チーム定例", at(10), at(11), False),
        Event("歯医者", at(13, 30), at(14, 30), False),
        Event("○○さんと打ち合わせ（オンライン）", at(16), at(17), False),
        Event("ジム", at(19), at(20), False),
    ]


def demo_data(now: datetime) -> DashboardData:
    first = now.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)
    while first.hour % 3:
        first += timedelta(hours=1)
    hourly_spec = [(61, 19, 100), (61, 19, 100), (51, 19, 98), (3, 19, 98),
                   (2, 18, 75), (3, 18, 24), (0, 20, 16), (0, 24, 0)]
    hourly = []
    for i, (code, temp, pop) in enumerate(hourly_spec):
        t = first + timedelta(hours=3 * i)
        hourly.append(HourSlot(t, code, temp, pop, 6 <= t.hour < 18))

    today = now.date()
    daily = [DaySlot(today + timedelta(days=i + 1), code, hi, lo, pop)
             for i, (code, hi, lo, pop) in enumerate([(3, 24, 16, 98), (2, 16, 10, 2), (51, 17, 8, 5)])]

    weather = Weather(
        current=Current(temperature=19.6, apparent=21.0, humidity=93, code=61,
                        wind_speed=2.1, wind_direction=22, is_day=True),
        today_max=20, today_min=19, precip_prob=100, hourly=hourly, daily=daily,
        clothing=Clothing(60, "長袖シャツで快適", "今日", ["傘を持って", "寒暖差 8℃"]),
        day_hours=demo_day_hours(now),
    )
    market_time = now.replace(second=0, microsecond=0) - timedelta(minutes=4)
    fund_date = (now - timedelta(days=3)).date()
    quotes = [
        Quote("ドル円", "円", 2, 156.95, 0.46, 0.29, time=market_time),
        Quote("S&P500", "円", 0, 44943, 369, 0.83, as_of=fund_date),
        Quote("FANG+", "円", 0, 96061, -4195, -4.18, as_of=fund_date),
    ]
    news = [
        "福田康夫元首相が死去 90歳",
        "台風30号は温帯低気圧に 西〜東日本で非常に激しい雨のおそれ",
        "将棋 西山朋佳女流四冠 プロ入り表明 初の女性プロ棋士誕生へ",
        "ドクターイエローの後継「ドクターS」が初運行 JR東海",
        "天皇皇后両陛下 高知市内で「バリアフリー図書」を視察",
        "福岡 北九州 冠水した道路で車1台が立往生 けが人なし",
        "政府 相次ぐ不正アクセス受け今夜関係閣僚会議開催へ",
    ]
    events = demo_events(now) if 3 <= now.hour < 9 else None  # 既定の時間帯は予定を出す
    return DashboardData(now=now, weather=weather, quotes=quotes, news=news, events=events,
                         indoor=Indoor(24.5, 67, 623), battery=96)
