import base64
import hashlib
import hmac
from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from dashboard import sources

TZ = ZoneInfo("Asia/Tokyo")


def open_meteo_fixture():
    hours = [f"2026-10-{d:02d}T{h:02d}:00" for d in (26, 27, 28, 29) for h in range(24)]
    return {
        "current": {"temperature_2m": 19.6, "relative_humidity_2m": 93, "apparent_temperature": 21.0,
                    "weather_code": 61, "wind_speed_10m": 2.2, "wind_direction_10m": 20, "is_day": 1},
        "hourly": {
            "time": hours,
            "temperature_2m": [float(i % 24) for i in range(len(hours))],
            "apparent_temperature": [float(i % 24) + 1 for i in range(len(hours))],
            "wind_speed_10m": [2.0] * len(hours),
            "weather_code": [3] * len(hours),
            "precipitation_probability": [i % 101 for i in range(len(hours))],
            "is_day": [1 if 6 <= i % 24 < 18 else 0 for i in range(len(hours))],
        },
        "daily": {
            "time": ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29"],
            "weather_code": [61, 3, 2, 51],
            "temperature_2m_max": [20, 24, 16, 17],
            "temperature_2m_min": [19, 16, 10, 8],
            "precipitation_probability_max": [100, 98, 2, 5],
        },
    }


def test_parse_open_meteo_picks_next_three_hour_slots():
    now = datetime(2026, 10, 26, 14, 19, tzinfo=TZ)
    w = sources.parse_open_meteo(open_meteo_fixture(), now)

    assert [s.time.hour for s in w.hourly] == [15, 18, 21, 0, 3, 6, 9, 12]
    assert w.hourly[3].time.day == 27
    assert w.hourly[1].is_day is False  # 18時
    assert w.precip_prob == 14  # 14時の降水確率
    assert (w.today_max, w.today_min) == (20, 19)
    assert [d.date for d in w.daily] == [date(2026, 10, 27), date(2026, 10, 28), date(2026, 10, 29)]
    assert w.daily[0].precip_prob == 98
    assert w.current.code == 61
    # 14〜21時の体感 15〜22℃ → 0.6*22 + 0.4*15 = 19.2 → 指数 60
    assert (w.clothing.day_label, w.clothing.index) == ("今日", 60)


def test_parse_open_meteo_day_hours_for_chart():
    w = sources.parse_open_meteo(open_meteo_fixture(), datetime(2026, 10, 26, 9, 0, tzinfo=TZ))
    assert w.day_label == "今日"
    assert [p.time.hour for p in w.day_hours] == list(range(24))
    assert {p.time.day for p in w.day_hours} == {26}

    evening = sources.parse_open_meteo(open_meteo_fixture(), datetime(2026, 10, 26, 19, 0, tzinfo=TZ))
    assert evening.day_label == "明日"
    assert {p.time.day for p in evening.day_hours} == {27}


def test_parse_open_meteo_skips_current_slot_exactly_on_the_hour():
    now = datetime(2026, 10, 26, 15, 0, tzinfo=TZ)
    w = sources.parse_open_meteo(open_meteo_fixture(), now)
    assert w.hourly[0].time.hour == 18


@pytest.mark.parametrize("code,kind", [
    (0, "clear"), (1, "clear"), (2, "partly"), (3, "cloudy"), (45, "fog"), (61, "rain"),
    (81, "rain"), (73, "snow"), (86, "snow"), (95, "thunder"), (99, "thunder"),
])
def test_icon_kind(code, kind):
    assert sources.icon_kind(code) == kind


def test_weather_label():
    assert sources.weather_label(61) == "小雨"
    assert sources.weather_label(12345) == "—"


@pytest.mark.parametrize("deg,label", [(0, "北"), (20, "北北東"), (90, "東"), (200, "南南西"), (350, "北"), (337, "北北西")])
def test_wind_direction(deg, label):
    assert sources.wind_direction_ja(deg) == label


def test_parse_yahoo_chart():
    data = {"chart": {"result": [{"meta": {
        "regularMarketPrice": 62568.0, "previousClose": 62693.0, "chartPreviousClose": 60000.0,
        "regularMarketTime": 1792991700,
    }}]}}
    q = sources.parse_yahoo_chart(data, "日経平均", "円", 0, TZ)
    assert q.change == -125
    assert q.change_pct == pytest.approx(-0.1994, abs=1e-3)
    assert q.time.tzinfo == TZ


def test_parse_yahoo_chart_falls_back_to_chart_previous_close():
    data = {"chart": {"result": [{"meta": {"regularMarketPrice": 156.95, "chartPreviousClose": 156.49}}]}}
    q = sources.parse_yahoo_chart(data, "ドル円", "円", 2, TZ)
    assert q.change == pytest.approx(0.46)
    assert q.time is None


def test_yahoo_chart_url_escapes_symbol():
    assert "/chart/%5EN225?" in sources.yahoo_chart_url("^N225")


def test_parse_rss_titles():
    xml = """<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>NHK</title>
    <item><title> 見出し1 </title></item><item><title>見出し2</title></item>
    <item><title></title></item><item><title>見出し3</title></item></channel></rss>""".encode()
    assert sources.parse_rss_titles(xml, 2) == ["見出し1", "見出し2"]
    assert sources.parse_rss_titles(xml, 10) == ["見出し1", "見出し2", "見出し3"]


def test_parse_atom_titles():
    xml = b"""<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>A</title></entry>
    <entry><title>B</title></entry></feed>"""
    assert sources.parse_rss_titles(xml, 5) == ["A", "B"]


def test_switchbot_headers_sign():
    h = sources.switchbot_headers("token", "secret", t="1700000000000", nonce="abc")
    # base64(HMAC-SHA256("secret", "token1700000000000abc"))
    expected = base64.b64encode(hmac.new(b"secret", b"token1700000000000abc", hashlib.sha256).digest()).decode()
    assert h["sign"] == expected
    assert h["Authorization"] == "token"


def test_parse_switchbot_status():
    ind = sources.parse_switchbot_status(
        {"statusCode": 100, "body": {"temperature": 24.5, "humidity": 67, "CO2": 623}})
    assert (ind.temperature, ind.humidity, ind.co2) == (24.5, 67, 623)
    with pytest.raises(ValueError):
        sources.parse_switchbot_status({"statusCode": 190, "message": "wrong"})


@pytest.mark.parametrize("ppm,label", [(None, ""), (623, "良好"), (1200, "やや高い"), (2000, "換気推奨")])
def test_co2_level(ppm, label):
    assert sources.co2_level(ppm) == label


def test_fetch_indoor_disabled_returns_none():
    assert sources.fetch_indoor({"indoor": {"provider": "none"}}, {}) is None


def test_fetch_indoor_requires_credentials():
    with pytest.raises(ValueError):
        sources.fetch_indoor({"indoor": {"provider": "switchbot", "device_id": "X"}}, {})


def test_parse_mufg_fund():
    # 三菱UFJアセット 投信情報 API の応答例（eMAXIS Slim 米国株式（S&P500））
    data = {
        "result": {"status": 200, "retcount": 1, "errcd": None, "errmsg": None},
        "datasets": [{"fund_cd": "253266", "isin_cd": "JP90C000GKC6", "association_fund_cd": "03311187",
                      "base_date": "20261020", "fund_name": "ｅＭＡＸＩＳ Ｓｌｉｍ 米国株式（Ｓ＆Ｐ５００）",
                      "nav": 44943, "cmp_prev_day": "-369", "percentage_change": "-0.81"}],
    }
    q = sources.parse_mufg_fund(data, "S&P500", "円", 0)
    assert (q.price, q.change, q.change_pct) == (44943, -369, -0.81)
    assert q.as_of == date(2026, 10, 20) and q.time is None


def test_parse_mufg_fund_not_found():
    with pytest.raises(ValueError):
        sources.parse_mufg_fund({"result": {"status": 404, "errmsg": "not found"}}, "x", "円", 0)


def test_parse_toushin_csv():
    csv_text = ("年月日,基準価額(円),純資産総額（百万円）,分配金,決算期\r\n"
                "2026年10月21日,100256,1460000,,\r\n"
                "2026年10月22日,100256,1460000,,\r\n"
                "2026年10月23日,96061,1400000,,\r\n")
    q = sources.parse_toushin_csv(csv_text.encode("cp932"), "FANG+", "円", 0)
    assert q.price == 96061 and q.change == -4195
    assert q.change_pct == pytest.approx(-4.184, abs=1e-3)
    assert q.as_of == date(2026, 10, 23)


def test_parse_toushin_csv_without_rows():
    with pytest.raises(ValueError):
        sources.parse_toushin_csv("年月日,基準価額(円)\r\n".encode("cp932"), "x", "円", 0)


def test_fund_urls():
    assert sources.mufg_fund_url("03311187").endswith("/association_fund_cd/03311187")
    assert sources.toushin_csv_url("JP90C000FZD4", "04311181").endswith(
        "csv-file-download?isinCd=JP90C000FZD4&associFundCd=04311181")


def test_fetch_quote_rejects_unknown_source():
    with pytest.raises(ValueError):
        sources.fetch_quote({"label": "x", "source": "nope"}, TZ)
