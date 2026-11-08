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


# ---------------------------------------------------------------- 無音の見張り

def test_parse_live_page_finds_hls_url():
    html = page(f"https://www.youtube.com/watch?v={VID}", True).replace(
        "</script>", '"streamingData":{"hlsManifestUrl":"https://manifest.googlevideo.com/api/manifest/hls_variant/a/1\\u0026b/2/index.m3u8"}</script>')
    v = live.parse_live_page(html)
    assert v.hls == "https://manifest.googlevideo.com/api/manifest/hls_variant/a/1&b/2/index.m3u8"


def test_pick_variant_lowest_bandwidth():
    master = ("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720\nhttps://cdn/720.m3u8\n"
              "#EXT-X-STREAM-INF:BANDWIDTH=290000,RESOLUTION=256x144\nlow/144.m3u8\n")
    assert live.pick_variant(master, "https://host/master/index.m3u8") == "https://host/master/low/144.m3u8"
    assert live.pick_variant("#EXTM3U\n#EXTINF:2,\nseg0.ts\n", "https://h/p.m3u8") == "https://h/p.m3u8"


def test_parse_volumedetect():
    assert live.parse_volumedetect("[Parsed_volumedetect_0 @ 0x1] max_volume: -3.2 dB") == -3.2
    assert live.parse_volumedetect("max_volume: -inf dB") == float("-inf")
    with pytest.raises(RuntimeError):
        live.parse_volumedetect("Output file is empty, nothing was encoded")


@pytest.fixture(scope="module")
def hls_server(tmp_path_factory):
    """ffmpeg で「無音」と「音あり」の HLS を作って配信する（本物の ffmpeg で測るテスト用）。"""
    import shutil
    import subprocess
    from functools import partial
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    if not shutil.which("ffmpeg"):
        pytest.skip("ffmpeg がない")
    d = tmp_path_factory.mktemp("hls")
    for name, src in (("tone", "sine=frequency=440:duration=6"), ("silent", "anullsrc=r=44100:cl=mono")):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", src, "-t", "6", "-c:a", "aac",
                        "-f", "hls", "-hls_time", "2", "-hls_playlist_type", "vod", str(d / f"{name}.m3u8")], check=True)
    # マスター: 軽い方（音あり）が選ばれるはず
    (d / "master.m3u8").write_text("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=900000\nsilent.m3u8\n"
                                   "#EXT-X-STREAM-INF:BANDWIDTH=64000\ntone.m3u8\n")
    handler = partial(SimpleHTTPRequestHandler, directory=str(d))
    handler.log_message = lambda *a: None
    srv = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


def _local_get(url, headers=None, timeout=15):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=timeout) as r:
        return r.read()


def test_measure_db_with_real_ffmpeg(hls_server, monkeypatch):
    for k in ("http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY", "all_proxy", "ALL_PROXY"):
        monkeypatch.delenv(k, raising=False)  # ffmpeg がローカルの HLS をプロキシ経由で取りに行かないように
    silent = live.measure_db(f"{hls_server}/silent.m3u8", 4, get=_local_get)
    tone = live.measure_db(f"{hls_server}/tone.m3u8", 4, get=_local_get)
    picked = live.measure_db(f"{hls_server}/master.m3u8", 4, get=_local_get)
    assert silent < -80
    assert tone > -20 and picked > -20


def test_measure_db_without_ffmpeg(monkeypatch):
    monkeypatch.setattr(live.shutil, "which", lambda name: None)
    with pytest.raises(RuntimeError, match="ffmpeg"):
        live.measure_db("http://x/a.m3u8")


class FakeYouTube:
    """resolve() が取りに行くページと、測る音量を差し替える。"""

    def __init__(self):
        self.pages = {}   # source → (video, live)
        self.levels = {}  # video → dB（例外を入れると測定失敗）
        self.measured = []

    def get(self, url, headers=None, timeout=15):
        for src, (vid, is_live) in self.pages.items():
            if live.page_url(src) == url:
                if vid is None:
                    return b'<link rel="canonical" href="https://www.youtube.com/channel/UCNsidkYpIAQ4QaufptQBPHQ">'
                html = page(f"https://www.youtube.com/watch?v={vid}", is_live).replace(
                    "</script>", f'"hlsManifestUrl":"https://hls/{vid}.m3u8"</script>')
                return html.encode()
        raise OSError("not found: " + url)

    def measure(self, url, seconds):
        vid = url.rsplit("/", 1)[1].split(".")[0]
        self.measured.append(vid)
        lv = self.levels.get(vid, -5.0)
        if isinstance(lv, Exception):
            raise lv
        return lv


A, B, C = "AAAAAAAAAAA", "BBBBBBBBBBB", "CCCCCCCCCCC"


def selector(yt, **live_cfg):
    cfg = {"live": {"video": f"https://www.youtube.com/live/{A}", "fallbacks": ["@b", "@c"],
                    "silence": {"threshold_db": -50, "seconds": 15, "switch_after": 2}, **live_cfg}}
    return live.LiveSelector(cfg, get=yt.get, measure=yt.measure)


def test_switches_after_silence_and_back():
    yt = FakeYouTube()
    yt.pages = {f"https://www.youtube.com/live/{A}": (A, True), "@b": (B, True), "@c": (C, True)}
    s = selector(yt)
    assert s.check().video == A                       # 音あり
    yt.levels[A] = -91.0
    v = s.check()
    assert v.video == A and v.level_db == -91.0       # 1 回目の無音ではまだ切り替えない
    v = s.check()
    assert v.video == B and v.reason == "無音が続いているため" and v.source == "@b"
    assert s.check().video == B                       # 無音の間は切り替えたまま
    yt.levels[A] = -12.0
    v = s.check()
    assert v.video == A and v.reason == ""           # 音が戻ったら元へ


def test_skips_silent_fallback():
    yt = FakeYouTube()
    yt.pages = {f"https://www.youtube.com/live/{A}": (A, True), "@b": (B, True), "@c": (C, True)}
    yt.levels = {A: -91.0, B: -91.0}
    s = selector(yt, silence={"threshold_db": -50, "seconds": 15, "switch_after": 1})
    assert s.check().video == C


def test_all_fallbacks_silent_uses_first_live():
    yt = FakeYouTube()
    yt.pages = {f"https://www.youtube.com/live/{A}": (A, True), "@b": (None, False), "@c": (C, True)}
    yt.levels = {A: -91.0, C: -91.0}
    s = selector(yt, silence={"threshold_db": -50, "seconds": 15, "switch_after": 1})
    v = s.check()
    assert v.video == C and v.level_db == -91.0  # level_db はいつもの配信の音量


def test_primary_stopped_switches_immediately():
    yt = FakeYouTube()
    yt.pages = {f"https://www.youtube.com/live/{A}": (A, False), "@b": (B, True)}
    v = selector(yt).check()
    assert v.video == B and v.reason == "いつもの配信が止まっているため"
    assert yt.measured == ["BBBBBBBBBBB"]  # 止まっている配信は測らない


def test_measure_failure_never_switches():
    yt = FakeYouTube()
    yt.pages = {f"https://www.youtube.com/live/{A}": (A, True), "@b": (B, True)}
    yt.levels[A] = RuntimeError("ffmpeg がありません")
    s = selector(yt)
    for _ in range(3):
        v = s.check()
        assert v.video == A and "ffmpeg" in v.note


def test_no_fallbacks_means_no_measuring():
    yt = FakeYouTube()
    yt.pages = {f"https://www.youtube.com/live/{A}": (A, True)}
    s = selector(yt, fallbacks=[])
    assert s.check().video == A and yt.measured == []


def test_fixed_video_plays_even_if_youtube_unreachable():
    yt = FakeYouTube()  # どのページも取れない
    s = selector(yt, fallbacks=[])
    v = s.check()
    assert v.video == A and v.live
    with pytest.raises(OSError):
        selector(yt, video="", channel="@a", fallbacks=[]).check()
