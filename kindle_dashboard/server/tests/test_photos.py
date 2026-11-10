"""/fire の背景写真（config/backgrounds/）。"""

import io
import json
import threading
import urllib.error
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from PIL import Image

from dashboard import photos
from dashboard.app import Dashboard, load_config, make_server
from dashboard.store import DataStore

NOW = datetime(2026, 11, 10, 12, 0, tzinfo=ZoneInfo("Asia/Tokyo"))


@pytest.fixture
def bgdir(tmp_path):
    d = tmp_path / "backgrounds"
    d.mkdir()
    Image.new("RGB", (4000, 3000), (40, 110, 210)).save(d / "clear-day.jpg")
    Image.new("RGB", (800, 1200), (90, 90, 90)).save(d / "rain.JPG")   # スマホの大文字の拡張子・縦長
    Image.new("RGB", (100, 100)).save(d / "clear-day-2.png")
    Image.new("RGB", (100, 100)).save(d / "Bad Name.jpg")               # 使えない名前
    Image.new("RGB", (100, 100)).save(d / "Clear-Day.jpg")              # 大文字の名前は使わない
    (d / "notes.txt").write_text("x")
    return d


def test_list_photos(bgdir):
    assert photos.list_photos(bgdir) == ["clear-day-2.png", "clear-day.jpg", "rain.JPG"]
    assert photos.list_photos(None) == [] and photos.list_photos(bgdir / "none") == []


def test_photo_is_resized_to_screen(bgdir):
    cache = photos.PhotoCache(bgdir)
    for name in ("clear-day.jpg", "rain.JPG"):
        im = Image.open(io.BytesIO(cache.get(name)))
        assert im.format == "JPEG" and im.size == photos.SIZE  # 縦長の写真も 16:10 に切り抜く
    assert cache.get("clear-day.jpg") is cache.get("clear-day.jpg")  # 2 回目はキャッシュ


@pytest.mark.parametrize("name", ["../config.json", "Bad Name.jpg", "notes.txt", "none.jpg", "Clear-Day.jpg", ""])
def test_photo_rejects(bgdir, name):
    assert photos.PhotoCache(bgdir).get(name) is None


def test_http_bg_and_data_json(bgdir):
    dash = Dashboard(load_config(None), DataStore(), None, lambda: NOW, bgdir)
    server = make_server(dash, "127.0.0.1", 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f"{base}/data.json") as res:
            assert json.load(res)["photos"] == ["clear-day-2.png", "clear-day.jpg", "rain.JPG"]
        with opener.open(f"{base}/bg/clear-day.jpg") as res:
            assert res.headers["Content-Type"] == "image/jpeg"
            assert Image.open(io.BytesIO(res.read())).size == photos.SIZE
        for bad in ("/bg/..%2Fconfig.json", "/bg/Bad%20Name.jpg", "/bg/notes.txt"):
            with pytest.raises(urllib.error.HTTPError) as e:
                opener.open(base + bad)
            assert e.value.code == 404
    finally:
        server.shutdown()


def test_user_photos_override_bundled(tmp_path, bgdir):
    bundled = tmp_path / "bundled"
    bundled.mkdir()
    Image.new("RGB", (100, 100), (255, 0, 0)).save(bundled / "rain.jpg")   # 自分の rain.JPG が優先
    Image.new("RGB", (100, 100), (0, 255, 0)).save(bundled / "night.jpg")  # 自分のに無いので使う
    dirs = [bgdir, bundled, tmp_path / "missing"]
    assert photos.list_photos(dirs) == ["clear-day-2.png", "clear-day.jpg", "night.jpg", "rain.JPG"]
    cache = photos.PhotoCache(dirs)
    assert cache.get("night.jpg") and cache.get("rain.JPG")
    assert cache.get("rain.jpg") is None
