"""YouTube ライブを Fire などで流し続ける（/live）ための、今のライブの動画 ID 探し。

ライブは配信が切れて再開すると動画 ID が変わるので、チャンネルの「/live」ページから
今の配信の ID を数分ごとに調べ直す（API キー不要）。動画 ID を固定で指定することもできる。
"""

from __future__ import annotations

import html as _html
import re
import urllib.parse
from dataclasses import dataclass

from .sources import http_get

_ID = r"[A-Za-z0-9_-]{11}"


@dataclass
class LiveVideo:
    video: str | None  # None なら配信していない（または見つからない）
    live: bool         # 今まさに配信中か（予定だけの配信は False）
    title: str = ""


def video_id(text: str) -> str | None:
    """動画 ID・watch / youtu.be / live / embed の URL から動画 ID を取り出す。"""
    text = (text or "").strip()
    if re.fullmatch(_ID, text):
        return text
    u = urllib.parse.urlparse(text)
    if "youtu" not in u.netloc:
        return None
    v = urllib.parse.parse_qs(u.query).get("v")
    if v and re.fullmatch(_ID, v[0]):
        return v[0]
    m = re.match(r"^/(?:live/|embed/|shorts/)?(" + _ID + r")(?:[/?]|$)", u.path)
    if m and (u.netloc.endswith("youtu.be") or u.path.startswith(("/live/", "/embed/", "/shorts/"))):
        return m.group(1)
    return None


def channel_live_url(channel: str) -> str:
    """"@handle"・"UC…"（チャンネル ID）・チャンネルの URL → そのチャンネルの /live ページ。"""
    c = channel.strip()
    if c.startswith("http"):
        path = urllib.parse.urlparse(c).path.rstrip("/")
        if path.endswith("/live"):
            path = path[: -len("/live")]
        return "https://www.youtube.com" + urllib.parse.quote(urllib.parse.unquote(path), safe="@/") + "/live"
    if c.startswith("@"):
        return "https://www.youtube.com/" + urllib.parse.quote(c, safe="@") + "/live"
    if re.fullmatch(r"UC[A-Za-z0-9_-]{22}", c):
        return f"https://www.youtube.com/channel/{c}/live"
    return "https://www.youtube.com/@" + urllib.parse.quote(c.lstrip("@")) + "/live"


def parse_live_page(html: str) -> LiveVideo:
    """チャンネルの /live ページ。配信中なら canonical が watch?v=ID になり、isLiveNow が true。"""
    m = re.search(r'<link rel="canonical" href="https://www\.youtube\.com/watch\?v=(' + _ID + r')"', html)
    if not m:
        return LiveVideo(None, False)
    live = '"isLiveNow":true' in html
    t = re.search(r'<meta name="title" content="([^"]*)"', html)
    title = _html.unescape(t.group(1)) if t else ""
    return LiveVideo(m.group(1), live, title)


def fetch_live(cfg: dict) -> LiveVideo:
    live = cfg.get("live") or {}
    fixed = video_id(live.get("video", ""))
    if fixed:
        return LiveVideo(fixed, True)
    channel = live.get("channel", "")
    if not channel:
        raise ValueError("config の live.channel か live.video を設定してください")
    # 日本語ページで取り、EU 向けの同意画面を避ける
    html = http_get(channel_live_url(channel),
                    {"Accept-Language": "ja,en;q=0.8", "Cookie": "CONSENT=YES+1"}, timeout=20)
    return parse_live_page(html.decode("utf-8", "replace"))
