"""ネットワークなしで見た目を確認するためのダミーデータ。"""

from __future__ import annotations

from datetime import datetime, timedelta

from .render import DashboardData
from .sources import Current, DaySlot, HourSlot, Indoor, Quote, Weather


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
    )
    market_time = now.replace(second=0, microsecond=0) - timedelta(minutes=4)
    quotes = [
        Quote("ドル円", "円", 2, 156.95, 0.46, 0.29, market_time),
        Quote("日経平均", "円", 0, 62568, -125, -0.20, market_time),
        Quote("NYダウ", "ドル", 0, 52215, -653, -1.23, market_time),
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
    return DashboardData(now=now, weather=weather, quotes=quotes, news=news,
                         indoor=Indoor(24.5, 67, 623), battery=96)
