"""設定の読み込み、データ源の登録、HTTP サーバー。"""

from __future__ import annotations

import json
import logging
import os
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable
from urllib.parse import parse_qs, urlparse
from zoneinfo import ZoneInfo

from . import gcal, live, sources, web
from .demo import demo_data, demo_events
from .render import DashboardData, Fonts, png_bytes, render, to_kindle
from .store import DataStore

log = logging.getLogger(__name__)

SERVER_DIR = Path(__file__).resolve().parent.parent

# /health に出す。NAS に新しいプログラムが反映されたかの確認用（変更したら上げる）
VERSION = "2026.11.10-dense"

FIRE_HTML = Path(__file__).resolve().parent / "fire.html"
LIVE_HTML = Path(__file__).resolve().parent / "live.html"

DEFAULT_CONFIG = {
    "location": {"name": "東京", "latitude": 35.6812, "longitude": 139.7671},
    "timezone": "Asia/Tokyo",
    # 横置きの画面サイズ（Kindle Paperwhite 第7世代 = 1448x1072）。rotate で縦の画面向きに回す
    # gamma: 中間色を濃くする補正（E-ink 向け, 1.0 で補正なし）
    "display": {"width": 1448, "height": 1072, "rotate": 90, "gamma": 1.4},
    # 文字を指定より何段階太くするか（E-ink 向け。0 で元の太さ）
    "font_weight_boost": 1,
    "font_path": None,
    # 時計の数字のフォント（fonts/ 内のファイル名と太さ）。候補は README 参照
    "clock": {"font": "DMSerifDisplay-Regular.ttf"},
    "host": "0.0.0.0",
    "port": 8080,
    "refresh_minutes": {"weather": 10, "market": 5, "news": 15, "indoor": 5, "calendar": 15},
    "news": {"url": "https://www.nhk.or.jp/rss/news/cat0.xml", "count": 7, "label": "NHKニュース"},
    # source: yahoo（為替・指数, symbol）/ mufg（三菱UFJアセットの投信, code=協会コード）
    #         / toushin（投信協会 CSV・全ファンド対応, isin と code=協会コード）
    "market": {"symbols": [
        {"label": "ドル円", "source": "yahoo", "symbol": "JPY=X", "unit": "円", "decimals": 2},
        {"label": "S&P500", "source": "mufg", "code": "03311187", "unit": "円", "decimals": 0,
         "refresh_minutes": 60},  # eMAXIS Slim 米国株式（S&P500）
        {"label": "FANG+", "source": "toushin", "isin": "JP90C000FZD4", "code": "04311181",
         "unit": "円", "decimals": 0, "refresh_minutes": 60},  # iFreeNEXT FANG+インデックス
    ]},
    "indoor": {"provider": "none", "device_id": ""},
    # Google カレンダー: window の時間帯だけニュース欄を今月のカレンダーに替える。
    # ics_urls は「iCal 形式の非公開 URL」（環境変数 CALENDAR_ICS_URLS でも可）
    "calendar": {"ics_urls": [], "window": ["03:00", "09:00"], "week_start": "sunday"},
    "credits": "Open-Meteo・Yahoo Finance・三菱UFJアセット・投資信託協会",
    # カラー版（/fire）: night は画面を暗くする時間帯。Fully Kiosk Browser なら本体の明るさも変える
    "web": {"night": ["23:00", "06:00"], "brightness": {"day": 180, "night": 10}},
    # ゴミ出しの日（/fire に表示）。rules: name と weekdays（"月"〜"日"）、weeks（第何週, 省略で毎週）、
    # dates（"2026-12-30" など個別の日）、except（その日は除く, "MM-DD" も可）。except は全体の休み
    "garbage": {"until": "09:00", "evening": "17:00", "rules": [], "except": []},
    # YouTube ライブを流し続ける（/live）。channel は "@handle"・"UC…"・チャンネル URL。
    # video に動画 ID / URL を書くとそれを固定で流す。mute: 音を消して流す（自動再生が確実）
    # clock: 右下に小さく時計を出す
    # fallbacks: いつもの配信が無音・停止のときに切り替える先（上から順に、配信中のもの）
    # silence: 無音の判定（最大音量が threshold_db 未満を switch_after 回続けて無音とみなす。ffmpeg が必要）
    "live": {"channel": "", "video": "", "mute": True, "check_minutes": 5, "clock": False,
             "fallbacks": [], "silence": {"threshold_db": -50, "seconds": 15, "switch_after": 2}},
}


def load_config(path: Path | None) -> dict:
    """既定値に config.json を重ね、同じフォルダに secrets.json があればさらに重ねる。

    secrets.json は SwitchBot のトークンなど人に見せない値の置き場（配布 zip には入らない）。
    """
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    files = [path, path.parent / "secrets.json"] if path else []
    for f in files:
        if not f.is_file():
            continue
        for key, value in json.loads(f.read_text(encoding="utf-8")).items():
            if isinstance(value, dict) and isinstance(cfg.get(key), dict):
                cfg[key].update(value)
            else:
                cfg[key] = value
    return cfg


def build_store(cfg: dict, now: Callable[[], datetime], env=os.environ) -> DataStore:
    store = DataStore()
    ttl = {k: v * 60 for k, v in cfg["refresh_minutes"].items()}
    store.add("weather", "天気", lambda: sources.fetch_weather(cfg, now()), ttl["weather"])
    tz = ZoneInfo(cfg["timezone"])
    for i, sym in enumerate(cfg["market"]["symbols"]):
        minutes = sym.get("refresh_minutes", cfg["refresh_minutes"]["market"])
        store.add(f"market{i}", sym["label"], lambda sym=sym: sources.fetch_quote(sym, tz), minutes * 60)
    store.add("news", "ニュース", lambda: sources.fetch_news(cfg), ttl["news"])
    if (cfg.get("indoor") or {}).get("provider") == "switchbot":
        store.add("indoor", "室内", lambda: sources.fetch_indoor(cfg, env), ttl["indoor"])
    lv = cfg.get("live") or {}
    if lv.get("channel") or lv.get("video"):
        selector = live.LiveSelector(cfg)
        store.add("live", "YouTube", selector.check, lv.get("check_minutes", 5) * 60)
    urls = gcal.calendar_urls(cfg, env)
    if urls:
        week_start = cfg["calendar"].get("week_start", "sunday")
        store.add("calendar", "予定", lambda: gcal.fetch_events(urls, now(), week_start), ttl["calendar"])
    return store


class Dashboard:
    def __init__(self, cfg: dict, store: DataStore, fonts: Fonts, now: Callable[[], datetime]):
        self.cfg, self.store, self.fonts, self.now = cfg, store, fonts, now
        self._lock = threading.Lock()  # Pillow の描画はスレッドごとに分けず直列化する

    def data(self) -> DashboardData:
        dev = self.store.device
        get = lambda name: self.store.get(name) if name in self.store.sources else None  # noqa: E731
        now = self.now()
        cal = self.cfg["calendar"]
        # 時間帯内で予定が取得できていればニュースの代わりに月表示（取得失敗中はニュースのまま）
        events = get("calendar") if gcal.in_window(now, cal["window"]) else None
        return DashboardData(
            now=now,
            events=events,
            week_start=cal.get("week_start", "sunday"),
            weather=get("weather"),
            quotes=[src.value or src.label for n, src in self.store.sources.items() if n.startswith("market")],
            news=get("news") or [],
            indoor=get("indoor"),
            battery=dev.battery,
            charging=dev.charging,
            failing=self.store.failing_labels(),
            news_label=self.cfg["news"].get("label", ""),
            credits=self.cfg.get("credits", ""),
        )

    def web_payload(self, demo: bool = False) -> dict:
        """カラー版（/fire）用。予定は時間帯に関係なく、今日からの 1 週間を出す。"""
        now = self.now()
        if demo:
            data, events = demo_data(now), demo_events(now)
        else:
            data = self.data()
            events = self.store.get("calendar") if "calendar" in self.store.sources else None
        out = web.payload(data, events, VERSION, self.cfg)
        if demo:  # 見た目の確認用に、ゴミの日（月・木）と今日・明日のゴミ、暦を必ず出す
            demo_cfg = {**self.cfg, "garbage": {"rules": [{"name": "燃えるゴミ", "weekdays": ["月", "木"]}]}}
            out["month"] = web.month_info(demo_cfg, now, events)
            out["today"].update(garbage=["燃えるゴミ"], garbage_tomorrow=["プラスチック資源"],
                                sekki=out["today"]["sekki"] or "立冬",
                                zassetsu=out["today"]["zassetsu"] or ["八十八夜"])
        out["clock_font"] = Path((self.cfg.get("clock") or {}).get("font") or "").name
        out["web"] = self.cfg.get("web") or {}
        return out

    def live_payload(self) -> dict:
        lv = self.cfg.get("live") or {}
        src = self.store.sources.get("live")
        v = src.value if src else None
        return {
            "video": v.video if v else None,
            "live": bool(v and v.live),
            "title": v.title if v else "",
            "reason": v.reason if v else "",          # 切り替え中なら理由（いつもの配信なら空）
            "source": v.source if v else "",
            "level_db": None if not v or v.level_db is None or v.level_db == float("-inf") else round(v.level_db, 1),
            "note": v.note if v else "",
            "configured": src is not None,
            "error": src.error if src and not src.ok and src.next_at else "",
            "mute": bool(lv.get("mute", True)),
            "clock": bool(lv.get("clock", False)),
            "now": self.now().isoformat(),
        }

    def render_png(self, rotate: bool = True) -> bytes:
        d = self.cfg["display"]
        with self._lock:
            img = render(self.data(), self.fonts, d["width"], d["height"])
            img = to_kindle(img, d["rotate"] if rotate else 0, d.get("gamma", 1.0))
            return png_bytes(img)


def make_handler(dash: Dashboard):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            url = urlparse(self.path)
            if url.path in ("/", "/dash.png"):
                q = parse_qs(url.query)
                if "battery" in q:
                    try:
                        battery = int(q["battery"][0].rstrip("%"))
                    except ValueError:
                        battery = None
                    charging = q.get("charging", ["0"])[0] in ("1", "true", "yes")
                    dash.store.set_device(battery, charging)
                self._send(200, "image/png", dash.render_png())
            elif url.path == "/preview.png":
                self._send(200, "image/png", dash.render_png(rotate=False))
            elif url.path in ("/fire", "/fire/"):
                # 毎回読む（NAS 上で fire.html を差し替えたらすぐ反映される）
                self._send(200, "text/html; charset=utf-8", FIRE_HTML.read_bytes())
            elif url.path in ("/live", "/live/"):
                self._send(200, "text/html; charset=utf-8", LIVE_HTML.read_bytes())
            elif url.path == "/live.json":
                body = json.dumps(dash.live_payload(), ensure_ascii=False)
                self._send(200, "application/json; charset=utf-8", body.encode())
            elif url.path == "/data.json":
                demo = parse_qs(url.query).get("demo", ["0"])[0] in ("1", "true")
                body = json.dumps(dash.web_payload(demo), ensure_ascii=False)
                self._send(200, "application/json; charset=utf-8", body.encode())
            elif url.path.startswith("/fonts/"):
                # fonts/ の中のフォントだけ（../ などは通さない）
                name = Path(url.path).name
                f = SERVER_DIR / "fonts" / name
                if name.endswith((".ttf", ".otf", ".woff2")) and f.is_file():
                    self._send(200, "font/ttf", f.read_bytes(), cache=86400)
                else:
                    self._send(404, "text/plain; charset=utf-8", b"not found")
            elif url.path == "/health":
                body = json.dumps({"version": VERSION, **dash.store.status()}, ensure_ascii=False, indent=2)
                self._send(200, "application/json; charset=utf-8", body.encode())
            else:
                self._send(404, "text/plain; charset=utf-8", b"not found")

        def _send(self, code: int, ctype: str, body: bytes, cache: int = 0):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", f"max-age={cache}" if cache else "no-store")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            log.info("%s %s", self.address_string(), fmt % args)

    return Handler


def make_server(dash: Dashboard, host: str, port: int) -> ThreadingHTTPServer:
    return ThreadingHTTPServer((host, port), make_handler(dash))


def clock(cfg: dict) -> Callable[[], datetime]:
    tz = ZoneInfo(cfg["timezone"])
    return lambda: datetime.now(tz)
