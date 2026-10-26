import io
import json
import threading
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from PIL import Image

from dashboard.app import DEFAULT_CONFIG, SERVER_DIR, Dashboard, load_config, make_server
from dashboard.demo import demo_data
from dashboard.render import DashboardData, Fonts, png_bytes, render, to_kindle
from dashboard.store import DataStore

NOW = datetime(2026, 10, 26, 14, 19, tzinfo=ZoneInfo("Asia/Tokyo"))


@pytest.fixture(scope="module")
def fonts():
    return Fonts(None, SERVER_DIR)


def test_render_demo_is_kindle_ready(fonts):
    img = to_kindle(render(demo_data(NOW), fonts), 90)
    assert img.size == (758, 1024)
    assert img.mode == "L"
    hist = img.histogram()
    assert all(v % 17 == 0 for v in range(256) if hist[v])  # 16 階調だけを使う

    decoded = Image.open(io.BytesIO(png_bytes(img)))
    assert decoded.mode == "L" and decoded.size == (758, 1024)


@pytest.mark.parametrize("rotate,size", [(0, (1024, 758)), (90, (758, 1024)), (180, (1024, 758)), (270, (758, 1024))])
def test_rotation(fonts, rotate, size):
    assert to_kindle(render(demo_data(NOW), fonts), rotate).size == size


def test_render_without_any_data(fonts):
    img = render(DashboardData(now=NOW, failing=["天気", "市況", "ニュース"]), fonts)
    assert img.size == (1024, 758)


def test_render_with_unfetched_quotes(fonts):
    data = demo_data(NOW)
    data.quotes = [data.quotes[0], "S&P500", "FANG+"]
    assert render(data, fonts).size == (1024, 758)


def test_market_sources_are_registered_per_symbol():
    from dashboard.app import build_store
    cfg = load_config(None)
    store = build_store(cfg, lambda: NOW)
    labels = [s.label for n, s in store.sources.items() if n.startswith("market")]
    assert labels == ["ドル円", "S&P500", "FANG+"]
    assert store.sources["market1"].ttl == 3600
    dash = Dashboard(cfg, store, None, lambda: NOW)
    assert dash.data().quotes == ["ドル円", "S&P500", "FANG+"]  # 未取得ならラベルだけ


def test_load_config_ignores_directory(tmp_path):
    # docker で config.json が無いままマウントするとディレクトリになる
    assert load_config(tmp_path)["port"] == DEFAULT_CONFIG["port"]


def test_load_config_merges_nested(tmp_path):
    p = tmp_path / "config.json"
    p.write_text(json.dumps({"location": {"name": "札幌"}, "port": 9000}), encoding="utf-8")
    cfg = load_config(p)
    assert cfg["location"]["name"] == "札幌"
    assert cfg["location"]["latitude"] == DEFAULT_CONFIG["location"]["latitude"]
    assert cfg["port"] == 9000
    assert DEFAULT_CONFIG["location"]["name"] == "東京"  # 既定値を書き換えない


def test_store_keeps_last_value_on_failure():
    t = [0.0]
    store = DataStore(clock=lambda: t[0])
    calls = []

    def fetch():
        calls.append(t[0])
        if len(calls) > 1:
            raise RuntimeError("boom")
        return "v1"

    store.add("x", "テスト", fetch, ttl=600)
    store.refresh_due()
    assert store.get("x") == "v1" and store.failing_labels() == []

    t[0] = 600
    store.refresh_due()
    assert store.get("x") == "v1"
    assert store.failing_labels() == ["テスト"]

    t[0] = 630  # 失敗後は 60 秒待ってから再試行
    store.refresh_due()
    assert len(calls) == 2
    t[0] = 660
    store.refresh_due()
    assert len(calls) == 3


def test_http_server_serves_png_and_records_battery(fonts):
    cfg = load_config(None)
    store = DataStore()
    dash = Dashboard(cfg, store, fonts, lambda: NOW)
    server = make_server(dash, "127.0.0.1", 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f"{base}/dash.png?battery=96&charging=1") as res:
            assert res.headers["Content-Type"] == "image/png"
            img = Image.open(io.BytesIO(res.read()))
            assert img.size == (758, 1024)
        assert store.device.battery == 96 and store.device.charging is True

        with opener.open(f"{base}/preview.png") as res:
            assert Image.open(io.BytesIO(res.read())).size == (1024, 758)

        with opener.open(f"{base}/health") as res:
            assert json.load(res)["device"]["battery"] == 96
    finally:
        server.shutdown()


@pytest.mark.parametrize("index", [10, 20, 30, 40, 50, 60, 70, 80, 90])
def test_render_every_clothing_level(fonts, index):
    from dashboard.clothing import Clothing
    from dashboard.icons import GARMENTS
    assert index in GARMENTS
    data = demo_data(NOW)
    data.weather.clothing = Clothing(index, "テスト", "明日", ["傘を持って（降水80%）", "風が強い（9m/s）"])
    assert render(data, fonts).size == (1024, 758)


@pytest.mark.parametrize("hours", [0, 1, 24])
def test_render_temp_chart_with_few_or_flat_hours(fonts, hours):
    data = demo_data(NOW)
    data.weather.day_hours = [p for p in data.weather.day_hours[:hours]]
    for p in data.weather.day_hours:
        p.temperature = 15.0  # 平らでもゼロ除算しない
    assert render(data, fonts).size == (1024, 758)


@pytest.mark.parametrize("tips,expect_badge", [(["傘を持って", "寒暖差 8℃"], True), (["寒暖差 8℃"], False)])
def test_umbrella_badge_only_on_rainy_days(fonts, tips, expect_badge):
    from dashboard.clothing import Clothing
    data = demo_data(NOW)
    data.weather.clothing = Clothing(60, "長袖シャツで快適", "今日", tips)
    img = render(data, fonts)
    # 傘のバッジの位置（服のイラストの右）が黒地になっているか
    badge = img.crop((102, 246, 160, 300))
    dark = sum(1 for v in badge.getdata() if v < 64) / (badge.width * badge.height)
    assert (dark > 0.4) is expect_badge
