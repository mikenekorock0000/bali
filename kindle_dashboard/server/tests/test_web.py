"""カラー版（/fire）の JSON と配信。"""

import json
import threading
import urllib.error
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from dashboard import web
from dashboard.app import DEFAULT_CONFIG, SERVER_DIR, Dashboard, load_config, make_server
from dashboard.demo import demo_data, demo_events
from dashboard.gcal import Event
from dashboard.render import DashboardData, Fonts
from dashboard.sources import Quote
from dashboard.store import DataStore

TZ = ZoneInfo("Asia/Tokyo")
NOW = datetime(2026, 11, 7, 14, 19, tzinfo=TZ)  # 土曜


@pytest.fixture(scope="module")
def fonts():
    return Fonts(None, SERVER_DIR, DEFAULT_CONFIG["clock"])


def test_payload_from_demo_is_json_ready():
    p = web.payload(demo_data(NOW), demo_events(NOW), "v")
    json.dumps(p, ensure_ascii=False)  # そのまま JSON にできる
    w = p["weather"]
    assert w["label"] == "小雨" and w["icon"] == "rain"
    assert len(w["hourly"]) == 8 and w["hourly"][0]["time"].endswith("時")
    assert w["daily"][0] == {"date": "11/8", "weekday": "日", "weekend": True, "icon": "cloudy",
                             "label": "曇り", "max": 24, "min": 16, "pop": 98}
    assert len(w["chart"]) == 24 and w["clothing"]["phrase"]
    assert p["indoor"] == {"temp": 24.5, "humidity": 67, "co2": 623, "level": "良好"}
    assert p["now"].startswith("2026-11-07T14:19")


def test_payload_without_data():
    p = web.payload(DashboardData(now=NOW, quotes=["ドル円"]))
    assert p["weather"] is None and p["indoor"] is None and p["events"] == []
    assert p["quotes"] == [{"label": "ドル円", "missing": True}]


def test_quote_format():
    q = web._quote(Quote("FANG+", "円", 0, 96061, -4195, -4.18, as_of=NOW.date()))
    assert q == {"label": "FANG+", "price": "96,061", "unit": "円", "change": "−4,195", "pct": "-4.18%",
                 "dir": -1, "note": "11/7 基準"}
    q = web._quote(Quote("ドル円", "円", 2, 156.95, 0.46, 0.29, time=NOW))
    assert q["change"] == "+0.46" and q["dir"] == 1 and q["note"] == "14:19"


def test_upcoming_events():
    day = NOW.replace(hour=0, minute=0)
    ev = [
        Event("終わった", day + timedelta(hours=9), day + timedelta(hours=10), False),
        Event("会議", day + timedelta(hours=16), day + timedelta(hours=17), False),
        Event("旅行", day - timedelta(days=1), day + timedelta(days=1), True),  # 昨日から続く
        Event("来週すぎ", day + timedelta(days=9), day + timedelta(days=10), True),
        Event("明日", day + timedelta(days=1, hours=10), day + timedelta(days=1, hours=11), False),
    ]
    out = web.upcoming(ev, NOW)
    titles = [e["title"] for e in out if not e["holiday"]]
    assert titles == ["旅行", "会議", "明日"]
    assert out[0]["today"] and out[0]["time"] == "終日" and out[0]["date"] == "11/7"
    assert out[1]["time"] == "16:00"
    # 11/23 勤労感謝の日（1 週間の範囲外）は出ず、範囲内の祝日だけ出る
    near = web.upcoming([], datetime(2026, 11, 20, 8, tzinfo=TZ))
    assert [e["title"] for e in near] == ["勤労感謝の日"] and near[0]["holiday"]
    assert web.upcoming(None, NOW) == []


def test_http_fire_page_data_and_fonts(fonts):
    cfg = load_config(None)
    dash = Dashboard(cfg, DataStore(), fonts, lambda: NOW)
    server = make_server(dash, "127.0.0.1", 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f"{base}/fire") as res:
            assert res.headers["Content-Type"].startswith("text/html")
            assert b"/data.json" in res.read()
        with opener.open(f"{base}/data.json?demo=1") as res:
            d = json.load(res)
            assert d["weather"]["label"] == "小雨" and d["events"]
            assert d["clock_font"] == "DMSerifDisplay-Regular.ttf"
            assert d["web"]["night"] == ["23:00", "06:00"]
        with opener.open(f"{base}/data.json") as res:  # 未取得でも返す
            assert json.load(res)["weather"] is None
        if (SERVER_DIR / "fonts" / "NotoSansJP-VF.ttf").exists():
            with opener.open(f"{base}/fonts/NotoSansJP-VF.ttf") as res:
                assert res.headers["Cache-Control"] == "max-age=86400"
        for bad in ("/fonts/../serve.py", "/fonts/%2e%2e%2fserve.py", "/fonts/nothing.ttf", "/fonts/config.json"):
            with pytest.raises(urllib.error.HTTPError) as e:
                opener.open(base + bad)
            assert e.value.code == 404
    finally:
        server.shutdown()


def test_month_info():
    cfg = {"garbage": {"rules": [{"name": "燃えるゴミ", "weekdays": ["月"]}]}}
    ev = [Event("旅行", datetime(2026, 11, 20, tzinfo=TZ), datetime(2026, 11, 22, tzinfo=TZ), True)]
    m = web.month_info(cfg, NOW, ev)
    assert m["title"] == "2026年11月" and m["head"] == "日月火水木金土"
    days = {(c["d"], c["in"]): c for w in m["weeks"] for c in w}
    assert len(m["weeks"]) == 5 and m["weeks"][0][0]["d"] == 1  # 2026/11/1 は日曜
    assert days[(7, True)]["today"] and days[(6, True)]["past"]
    assert days[(3, True)]["holiday"] == "文化の日" and days[(23, True)]["holiday"] == "勤労感謝の日"
    assert days[(9, True)]["garbage"] and not days[(10, True)]["garbage"]
    assert days[(20, True)]["event"] and days[(21, True)]["event"] and not days[(22, True)]["event"]
