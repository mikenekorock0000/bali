"""外部データの取得と解析（天気・市況・ニュース・室内センサー）。

取得 (fetch_*) と解析 (parse_*) を分けてあり、解析はネットワークなしでテストできる。
"""

from __future__ import annotations

import base64
import csv
import hashlib
import hmac
import io
import json
import re
import time
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from datetime import date, datetime
from zoneinfo import ZoneInfo

from .clothing import Clothing, HourPoint, clothing_advice

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) kindle-dashboard/1.0"


def http_get(url: str, headers: dict[str, str] | None = None, timeout: float = 15) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        return res.read()


def http_get_json(url: str, headers: dict[str, str] | None = None, timeout: float = 15):
    return json.loads(http_get(url, headers, timeout))


# ---------------------------------------------------------------- 天気 (Open-Meteo)

# WMO weather code -> 日本語
WEATHER_LABELS = {
    0: "快晴", 1: "晴れ", 2: "晴れ時々曇り", 3: "曇り",
    45: "霧", 48: "霧氷",
    51: "弱い霧雨", 53: "霧雨", 55: "強い霧雨", 56: "着氷性の霧雨", 57: "着氷性の霧雨",
    61: "小雨", 63: "雨", 65: "大雨", 66: "着氷性の雨", 67: "着氷性の雨",
    71: "小雪", 73: "雪", 75: "大雪", 77: "霧雪",
    80: "にわか雨", 81: "にわか雨", 82: "激しいにわか雨",
    85: "にわか雪", 86: "強いにわか雪",
    95: "雷雨", 96: "雷雨(ひょう)", 99: "雷雨(ひょう)",
}


def weather_label(code: int) -> str:
    return WEATHER_LABELS.get(code, "—")


def icon_kind(code: int) -> str:
    """天気コードをアイコンの種類 (clear/partly/cloudy/fog/rain/snow/thunder) に変換。"""
    if code in (0, 1):
        return "clear"
    if code == 2:
        return "partly"
    if code == 3:
        return "cloudy"
    if code in (45, 48):
        return "fog"
    if 71 <= code <= 77 or code in (85, 86):
        return "snow"
    if code >= 95:
        return "thunder"
    if 51 <= code <= 67 or 80 <= code <= 82:
        return "rain"
    return "cloudy"


WIND_DIRECTIONS = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                   "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]


def wind_direction_ja(degrees: float) -> str:
    return WIND_DIRECTIONS[round(degrees / 22.5) % 16]


@dataclass
class Current:
    temperature: float
    apparent: float
    humidity: float
    code: int
    wind_speed: float
    wind_direction: float
    is_day: bool


@dataclass
class HourSlot:
    time: datetime
    code: int
    temperature: float
    precip_prob: int | None
    is_day: bool


@dataclass
class DaySlot:
    date: date
    code: int
    t_max: float
    t_min: float
    precip_prob: int | None


@dataclass
class Weather:
    current: Current
    today_max: float
    today_min: float
    precip_prob: int | None
    hourly: list[HourSlot]
    daily: list[DaySlot]
    clothing: Clothing | None = None


def open_meteo_url(latitude: float, longitude: float, timezone: str) -> str:
    params = {
        "latitude": latitude,
        "longitude": longitude,
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,"
                   "weather_code,wind_speed_10m,wind_direction_10m,is_day",
        "hourly": "temperature_2m,apparent_temperature,weather_code,precipitation_probability,"
                  "wind_speed_10m,is_day",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "timezone": timezone,
        "wind_speed_unit": "ms",
        "forecast_days": 4,
    }
    return "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(params)


def parse_open_meteo(data: dict, now: datetime, hourly_count: int = 8,
                     hourly_step: int = 3, daily_count: int = 3) -> Weather:
    tz = now.tzinfo
    c = data["current"]
    current = Current(
        temperature=c["temperature_2m"],
        apparent=c["apparent_temperature"],
        humidity=c["relative_humidity_2m"],
        code=int(c["weather_code"]),
        wind_speed=c["wind_speed_10m"],
        wind_direction=c["wind_direction_10m"],
        is_day=bool(c.get("is_day", 1)),
    )

    h = data["hourly"]
    hours = [datetime.fromisoformat(t).replace(tzinfo=tz) for t in h["time"]]
    pops = h.get("precipitation_probability") or [None] * len(hours)
    is_day = h.get("is_day") or [1] * len(hours)

    this_hour = now.replace(minute=0, second=0, microsecond=0)
    precip_prob = next((pops[i] for i, t in enumerate(hours) if t == this_hour), None)

    hourly = [
        HourSlot(t, int(h["weather_code"][i]), h["temperature_2m"][i], pops[i], bool(is_day[i]))
        for i, t in enumerate(hours)
        if t > now and t.hour % hourly_step == 0
    ][:hourly_count]

    points = [
        HourPoint(t, h["temperature_2m"][i], (h.get("apparent_temperature") or h["temperature_2m"])[i],
                  pops[i], (h.get("wind_speed_10m") or [None] * len(hours))[i])
        for i, t in enumerate(hours)
    ]

    d = data["daily"]
    days = [date.fromisoformat(s) for s in d["time"]]
    today = now.date()
    today_idx = days.index(today) if today in days else 0
    d_pops = d.get("precipitation_probability_max") or [None] * len(days)
    daily = [
        DaySlot(days[i], int(d["weather_code"][i]), d["temperature_2m_max"][i],
                d["temperature_2m_min"][i], d_pops[i])
        for i in range(len(days))
        if days[i] > today
    ][:daily_count]

    return Weather(
        current=current,
        today_max=d["temperature_2m_max"][today_idx],
        today_min=d["temperature_2m_min"][today_idx],
        precip_prob=precip_prob,
        hourly=hourly,
        daily=daily,
        clothing=clothing_advice(points, now),
    )


def fetch_weather(cfg: dict, now: datetime) -> Weather:
    loc = cfg["location"]
    url = open_meteo_url(loc["latitude"], loc["longitude"], cfg["timezone"])
    return parse_open_meteo(http_get_json(url), now)


# ---------------------------------------------------------------- 市況（為替・株価指数・投資信託）

@dataclass
class Quote:
    label: str
    unit: str
    decimals: int
    price: float
    change: float
    change_pct: float
    time: datetime | None = None  # 取引中の価格の時刻（為替・指数）
    as_of: date | None = None  # 基準日（投資信託の基準価額）


def yahoo_chart_url(symbol: str) -> str:
    return ("https://query1.finance.yahoo.com/v8/finance/chart/"
            + urllib.parse.quote(symbol, safe="") + "?range=1d&interval=1d")


def parse_yahoo_chart(data: dict, label: str, unit: str, decimals: int, tz: ZoneInfo) -> Quote:
    meta = data["chart"]["result"][0]["meta"]
    price = float(meta["regularMarketPrice"])
    prev = meta.get("previousClose") or meta.get("chartPreviousClose")
    prev = float(prev) if prev else price
    change = price - prev
    ts = meta.get("regularMarketTime")
    return Quote(
        label=label,
        unit=unit,
        decimals=decimals,
        price=price,
        change=change,
        change_pct=(change / prev * 100) if prev else 0.0,
        time=datetime.fromtimestamp(ts, tz) if ts else None,
    )


def mufg_fund_url(association_code: str) -> str:
    """三菱UFJアセットマネジメントの投信情報 API（eMAXIS シリーズなど同社のファンド）。"""
    return ("https://developer.am.mufg.jp/fund_information_latest/association_fund_cd/"
            + urllib.parse.quote(association_code))


def parse_mufg_fund(data: dict, label: str, unit: str, decimals: int) -> Quote:
    result = data.get("result") or {}
    if result.get("status") != 200 or not data.get("datasets"):
        raise ValueError(f"MUFG API error: {result.get('status')} {result.get('errmsg')}")
    d = data["datasets"][0]
    return Quote(
        label=label,
        unit=unit,
        decimals=decimals,
        price=float(d["nav"]),
        change=float(str(d["cmp_prev_day"]).replace(",", "")),
        change_pct=float(d["percentage_change"]),
        as_of=datetime.strptime(str(d["base_date"]), "%Y%m%d").date(),
    )


def toushin_csv_url(isin: str, association_code: str) -> str:
    """投資信託協会「投信総合検索ライブラリー」の基準価額 CSV（全ファンド対応）。"""
    return ("https://toushin-lib.fwg.ne.jp/FdsWeb/FDST030000/csv-file-download?"
            + urllib.parse.urlencode({"isinCd": isin, "associFundCd": association_code}))


def parse_toushin_csv(raw: bytes, label: str, unit: str, decimals: int) -> Quote:
    """1 列目が「2026年10月23日」、2 列目が基準価額の CSV から最新 2 日分で前日比を出す。"""
    rows = []
    for row in csv.reader(io.StringIO(raw.decode("cp932", errors="replace"))):
        m = re.match(r"(\d{4})年(\d{1,2})月(\d{1,2})日", row[0].strip()) if len(row) >= 2 else None
        if not m:
            continue
        try:
            nav = float(row[1].replace(",", ""))
        except ValueError:
            continue
        rows.append((date(*map(int, m.groups())), nav))
    if len(rows) < 2:
        raise ValueError("基準価額の CSV にデータがありません")
    rows.sort()
    (_, prev), (as_of, nav) = rows[-2], rows[-1]
    change = nav - prev
    return Quote(label, unit, decimals, nav, change, change / prev * 100 if prev else 0.0, as_of=as_of)


def fetch_quote(symbol: dict, tz: ZoneInfo) -> Quote:
    label, unit, decimals = symbol["label"], symbol.get("unit", ""), symbol.get("decimals", 0)
    source = symbol.get("source", "yahoo")
    if source == "mufg":
        return parse_mufg_fund(http_get_json(mufg_fund_url(symbol["code"])), label, unit, decimals)
    if source == "toushin":
        raw = http_get(toushin_csv_url(symbol["isin"], symbol["code"]), timeout=30)
        return parse_toushin_csv(raw, label, unit, decimals)
    if source == "yahoo":
        data = http_get_json(yahoo_chart_url(symbol["symbol"]))
        return parse_yahoo_chart(data, label, unit, decimals, tz)
    raise ValueError(f"未対応の source: {source}")


# ---------------------------------------------------------------- ニュース (RSS)

def parse_rss_titles(xml_bytes: bytes, count: int) -> list[str]:
    root = ET.fromstring(xml_bytes)
    titles = [(item.findtext("title") or "").strip() for item in root.iter("item")]
    if not titles:  # Atom フィード
        ns = "{http://www.w3.org/2005/Atom}"
        titles = [e.findtext(f"{ns}title", "").strip() for e in root.iter(f"{ns}entry")]
    return [t for t in titles if t][:count]


def fetch_news(cfg: dict) -> list[str]:
    news = cfg["news"]
    return parse_rss_titles(http_get(news["url"]), news.get("count", 7))


# ---------------------------------------------------------------- 室内 (SwitchBot API v1.1)

@dataclass
class Indoor:
    temperature: float | None
    humidity: float | None
    co2: int | None


def co2_level(ppm: int | None) -> str:
    if ppm is None:
        return ""
    if ppm < 1000:
        return "良好"
    if ppm < 1500:
        return "やや高い"
    return "換気推奨"


def switchbot_headers(token: str, secret: str, t: str | None = None,
                      nonce: str | None = None) -> dict[str, str]:
    t = t or str(int(time.time() * 1000))
    nonce = nonce or uuid.uuid4().hex
    sign = base64.b64encode(
        hmac.new(secret.encode(), (token + t + nonce).encode(), hashlib.sha256).digest()
    ).decode()
    return {"Authorization": token, "sign": sign, "t": t, "nonce": nonce,
            "Content-Type": "application/json; charset=utf8"}


def parse_switchbot_status(data: dict) -> Indoor:
    if data.get("statusCode") != 100:
        raise ValueError(f"SwitchBot API error: {data.get('statusCode')} {data.get('message')}")
    body = data["body"]
    co2 = body.get("CO2")
    return Indoor(body.get("temperature"), body.get("humidity"),
                  int(co2) if co2 is not None else None)


def fetch_indoor(cfg: dict, env: dict[str, str]) -> Indoor | None:
    indoor = cfg.get("indoor") or {}
    if indoor.get("provider") != "switchbot":
        return None
    token, secret = env.get("SWITCHBOT_TOKEN"), env.get("SWITCHBOT_SECRET")
    device_id = indoor.get("device_id")
    if not (token and secret and device_id):
        raise ValueError("SWITCHBOT_TOKEN / SWITCHBOT_SECRET / indoor.device_id が未設定")
    url = f"https://api.switch-bot.com/v1.1/devices/{urllib.parse.quote(device_id)}/status"
    return parse_switchbot_status(http_get_json(url, switchbot_headers(token, secret)))
