"""YouTube ライブ（/live）。"""

import json
import threading
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from dashboard import live
from dashboard.app import DEFAULT_CONFIG, SERVER_DIR, Dashboard, build_store, load_config, make_server
from dashboard.render import Fonts
from dashboard.store import DataStore

NOW = datetime(2026, 11, 8, 10, 0, tzinfo=ZoneInfo("Asia/Tokyo"))
VID = "dQw4w9WgXcQ"


@pytest.mark.parametrize("text", [
    VID, f"https://www.youtube.com/watch?v={VID}", f"https://www.youtube.com/watch?v={VID}&t=10",
    f"https://youtu.be/{VID}", f"https://youtu.be/{VID}?si=abc", f"https://www.youtube.com/live/{VID}?feature=share",
    f"https://www.youtube.com/embed/{VID}", f"https://m.youtube.com/watch?v={VID}", f"  {VID}  ",
])
def test_video_id(text):
    assert live.video_id(text) == VID


@pytest.mark.parametrize("text", ["", "abc", "https://example.com/watch?v=" + VID, "https://www.youtube.com/@weathernews"])
def test_video_id_rejects(text):
    assert live.video_id(text) is None


@pytest.mark.parametrize("channel,url", [
    ("@weathernews", "https://www.youtube.com/@weathernews/live"),
    ("weathernews", "https://www.youtube.com/@weathernews/live"),
    ("UCNsidkYpIAQ4QaufptQBPHQ", "https://www.youtube.com/channel/UCNsidkYpIAQ4QaufptQBPHQ/live"),
    ("https://www.youtube.com/@weathernews", "https://www.youtube.com/@weathernews/live"),
    ("https://www.youtube.com/@weathernews/live", "https://www.youtube.com/@weathernews/live"),
    ("https://www.youtube.com/channel/UCNsidkYpIAQ4QaufptQBPHQ/", "https://www.youtube.com/channel/UCNsidkYpIAQ4QaufptQBPHQ/live"),
    ("@ウェザーニュース", "https://www.youtube.com/@%E3%82%A6%E3%82%A7%E3%82%B6%E3%83%BC%E3%83%8B%E3%83%A5%E3%83%BC%E3%82%B9/live"),
])
def test_channel_live_url(channel, url):
    assert live.channel_live_url(channel) == url


def page(canonical: str, live_now: bool, title="ライブ &amp; ニュース") -> str:
    return (f'<html><head><link rel="canonical" href="{canonical}"><meta name="title" content="{title}"></head>'
            f'<body><script>var ytInitialPlayerResponse = {{"videoDetails":{{"isLiveContent":true}},'
            f'"microformat":{{"liveBroadcastDetails":{{"isLiveNow":{"true" if live_now else "false"}}}}}}};</script></body></html>')


def test_parse_live_page_live():
    v = live.parse_live_page(page(f"https://www.youtube.com/watch?v={VID}", True))
    assert v == live.LiveVideo(VID, True, "ライブ & ニュース")


def test_parse_live_page_upcoming_and_offline():
    assert live.parse_live_page(page(f"https://www.youtube.com/watch?v={VID}", False)).live is False
    off = live.parse_live_page(page("https://www.youtube.com/channel/UCNsidkYpIAQ4QaufptQBPHQ", False))
    assert off.video is None and off.live is False


def test_fetch_live_fixed_video_needs_no_network(monkeypatch):
    monkeypatch.setattr(live, "http_get", lambda *a, **k: pytest.fail("通信しない"))
    v = live.fetch_live({"live": {"video": f"https://youtu.be/{VID}", "channel": "@x"}})
    assert v.video == VID and v.live


def test_fetch_live_channel(monkeypatch):
    seen = {}

    def fake(url, headers=None, timeout=15):
        seen["url"] = url
        return page(f"https://www.youtube.com/watch?v={VID}", True).encode()

    monkeypatch.setattr(live, "http_get", fake)
    assert live.fetch_live({"live": {"channel": "@weathernews"}}).video == VID
    assert seen["url"] == "https://www.youtube.com/@weathernews/live"
    with pytest.raises(ValueError):
        live.fetch_live({"live": {}})


def test_live_source_registered_only_when_configured():
    cfg = load_config(None)
    assert "live" not in build_store(cfg, lambda: NOW, env={}).sources
    cfg["live"]["channel"] = "@weathernews"
    store = build_store(cfg, lambda: NOW, env={})
    assert store.sources["live"].ttl == 300


def test_http_live_page_and_json(monkeypatch):
    fonts = Fonts(None, SERVER_DIR, DEFAULT_CONFIG["clock"])
    cfg = load_config(None)
    cfg["live"].update(channel="@weathernews", mute=False, clock=True)
    monkeypatch.setattr(live, "http_get", lambda *a, **k: page(f"https://www.youtube.com/watch?v={VID}", True).encode())
    store = build_store(cfg, lambda: NOW, env={})
    store.sources = {"live": store.sources["live"]}  # 他のデータ源は通信するので外す
    store.refresh_due()
    server = make_server(Dashboard(cfg, store, fonts, lambda: NOW), "127.0.0.1", 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f"{base}/live") as res:
            body = res.read()
            assert b"iframe_api" in body and b"/live.json" in body
        with opener.open(f"{base}/live.json") as res:
            d = json.load(res)
        assert d["video"] == VID and d["live"] and d["configured"]
        assert d["mute"] is False and d["clock"] is True and d["error"] == ""
    finally:
        server.shutdown()


def test_live_json_when_not_configured():
    fonts = Fonts(None, SERVER_DIR, DEFAULT_CONFIG["clock"])
    d = Dashboard(load_config(None), DataStore(), fonts, lambda: NOW).live_payload()
    assert d["configured"] is False and d["video"] is None and d["mute"] is True
