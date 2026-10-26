"""服装指数（tenki.jp の服装指数を参考にした独自の目安）。

その日の外出時間帯（6〜21時。夕方以降は翌日）の体感温度から 10〜90 の指数と
おすすめの服装を決め、傘・寒暖差・強風のひとことを添える。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

DAY_START, DAY_END = 6, 21  # 外出する時間帯
SWITCH_TO_TOMORROW = 18  # この時刻以降は明日の服装を出す

# (この体感温度以上なら, 指数, 服装)
LEVELS = [
    (29, 90, "ノースリーブでもOK"),
    (25, 80, "半袖で快適"),
    (21, 70, "半袖＋薄い羽織りを"),
    (17, 60, "長袖シャツで快適"),
    (13, 50, "薄手のセーターを"),
    (9, 40, "ジャケットが必要"),
    (5, 30, "コートが必要"),
    (0, 20, "厚手のコートを"),
]
COLDEST = (10, "ダウン・手袋で防寒")

UMBRELLA_PROB = 50  # % 以上で傘
TEMP_SWING = 10  # ℃ 以上で寒暖差に注意
STRONG_WIND = 8  # m/s 以上で強風


@dataclass
class HourPoint:
    time: datetime
    temperature: float
    apparent: float
    precip_prob: int | None
    wind_speed: float | None


@dataclass
class Clothing:
    index: int
    phrase: str
    day_label: str  # "今日" / "明日"
    tips: list[str] = field(default_factory=list)


def level_for(feels_like: float) -> tuple[int, str]:
    for threshold, index, phrase in LEVELS:
        if feels_like >= threshold:
            return index, phrase
    return COLDEST


def target_day(now: datetime) -> tuple[date, str]:
    """服装と気温グラフの対象日。夕方以降は明日。"""
    if now.hour >= SWITCH_TO_TOMORROW:
        return (now + timedelta(days=1)).date(), "明日"
    return now.date(), "今日"


def clothing_advice(points: list[HourPoint], now: datetime) -> Clothing | None:
    day, label = target_day(now)
    start = max(DAY_START, now.hour) if label == "今日" else DAY_START
    window = [p for p in points if p.time.date() == day and start <= p.time.hour <= DAY_END]
    if not window:
        return None

    apparent = [p.apparent for p in window]
    # 最高と最低の体感温度の間（やや暖かい側）を、その日の体感とみなす
    feels_like = 0.6 * max(apparent) + 0.4 * min(apparent)
    index, phrase = level_for(feels_like)

    tips = []
    pops = [p.precip_prob for p in window if p.precip_prob is not None]
    if pops and max(pops) >= UMBRELLA_PROB:
        tips.append("傘を持って")
    temps = [p.temperature for p in window]
    if max(temps) - min(temps) >= TEMP_SWING:
        tips.append(f"寒暖差 {round(max(temps) - min(temps))}℃")
    winds = [p.wind_speed for p in window if p.wind_speed is not None]
    if winds and max(winds) >= STRONG_WIND:
        tips.append(f"風が強い {round(max(winds))}m/s")
    return Clothing(index, phrase, label, tips)
