"""YouTube ライブを Fire などで流し続ける（/live）ための、今のライブ選び。

- ライブは配信が切れて再開すると動画 ID が変わるので、チャンネルの「/live」ページから
  今の配信の ID を数分ごとに調べ直す（API キー不要）。動画 ID を固定で指定することもできる。
- 無音の見張り: いつもの配信の音声を数秒だけ ffmpeg で聞いて音量を測り、
  無音が続いたら・配信が止まったら fallbacks の配信に切り替える。音が戻れば元に戻す。
"""

from __future__ import annotations

import html as _html
import json
import logging
import re
import shutil
import subprocess
import urllib.parse
from dataclasses import dataclass
from typing import Callable

from .sources import http_get

_ID = r"[A-Za-z0-9_-]{11}"


log = logging.getLogger(__name__)


@dataclass
class LiveVideo:
    video: str | None  # None なら配信していない（または見つからない）
    live: bool         # 今まさに配信中か（予定だけの配信は False）
    title: str = ""
    hls: str = ""             # 音量を測るための HLS（m3u8）の URL
    source: str = ""          # 設定に書いた元（"@channel" や URL）
    reason: str = ""          # いつもの配信でない理由（切り替え中だけ）
    level_db: float | None = None  # いつもの配信の最後に測った音量（最大値, dB）
    note: str = ""            # 音量を測れなかった理由など


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
    h = re.search(r'"hlsManifestUrl":"((?:[^"\\]|\\.)+)"', html)
    hls = json.loads(f'"{h.group(1)}"') if h else ""
    return LiveVideo(m.group(1), live, title, hls)


HEADERS = {"Accept-Language": "ja,en;q=0.8", "Cookie": "CONSENT=YES+1"}  # 日本語ページ・EU の同意画面を避ける


def page_url(source: str) -> str:
    vid = video_id(source)
    return f"https://www.youtube.com/watch?v={vid}" if vid else channel_live_url(source)


def resolve(source: str, get: Callable | None = None) -> LiveVideo:
    """動画 URL / ID・チャンネルのどれでも、今の状態（配信中か・HLS の URL）を調べる。"""
    html = (get or http_get)(page_url(source), HEADERS, timeout=20).decode("utf-8", "replace")
    v = parse_live_page(html)
    v.source = source
    return v


# ---------------------------------------------------------------- 音量を測る

def pick_variant(master: str, base_url: str) -> str:
    """HLS のマスタープレイリストから一番軽い（帯域の小さい）ものを選ぶ。音を聞くだけなので画質は要らない。"""
    best, best_bw, want = None, None, False
    for line in master.splitlines():
        line = line.strip()
        if line.startswith("#EXT-X-STREAM-INF"):
            m = re.search(r"BANDWIDTH=(\d+)", line)
            bw, want = (int(m.group(1)) if m else 0), True
            continue
        if want and line and not line.startswith("#"):
            if best_bw is None or bw < best_bw:
                best, best_bw = urllib.parse.urljoin(base_url, line), bw
            want = False
    return best or base_url


def parse_volumedetect(stderr: str) -> float:
    m = re.search(r"max_volume:\s*(-?inf|-?[\d.]+) dB", stderr)
    if not m:
        raise RuntimeError("音声が取れませんでした")
    return float("-inf") if "inf" in m.group(1) else float(m.group(1))


def measure_db(hls_url: str, seconds: float = 15, get: Callable | None = None,
               run: Callable = subprocess.run, ffmpeg: str | None = None) -> float:
    """配信の音声を seconds 秒聞いて、最大音量（dB）を返す。-91 dB や -inf は完全な無音。"""
    ffmpeg = ffmpeg or shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("ffmpeg がありません（Docker で動かすか、ffmpeg を入れてください）")
    url = hls_url
    try:
        text = (get or http_get)(hls_url, {}, timeout=15).decode("utf-8", "replace")
        if "#EXT-X-STREAM-INF" in text:
            url = pick_variant(text, hls_url)
    except Exception as e:  # noqa: BLE001 - プレイリストが読めなくても ffmpeg に任せる
        log.info("HLS のプレイリストを読めません: %s", e)
    cmd = [ffmpeg, "-hide_banner", "-nostats", "-loglevel", "info", "-t", str(seconds),
           "-i", url, "-vn", "-af", "volumedetect", "-f", "null", "-"]
    r = run(cmd, capture_output=True, text=True, timeout=seconds + 45)
    return parse_volumedetect(r.stderr)


# ---------------------------------------------------------------- どれを流すか

class LiveSelector:
    """数分ごとに check() を呼ぶ（DataStore のデータ源）。無音が続いた回数を覚えておく。"""

    def __init__(self, cfg: dict, get: Callable | None = None, measure: Callable | None = None):
        self.cfg, self.get = cfg, get  # None なら呼ぶたびに http_get / measure_db を使う
        self.measure = measure or (lambda url, seconds: measure_db(url, seconds, self.get))
        self.silent_count = 0

    def _opts(self) -> tuple[str, list[str], dict]:
        lv = self.cfg.get("live") or {}
        primary = lv.get("video") or lv.get("channel") or ""
        if not primary:
            raise ValueError("config の live.channel か live.video を設定してください")
        fallbacks = [f for f in lv.get("fallbacks") or [] if f]
        sil = {"enabled": bool(fallbacks), "threshold_db": -50, "seconds": 15, "switch_after": 2,
               **(lv.get("silence") or {})}
        return primary, fallbacks, sil

    def _silent(self, v: LiveVideo, sil: dict) -> bool | None:
        """無音なら True、音ありなら False、測れなければ None（測れないときは切り替えない）。"""
        if not v.hls:
            v.note = "音声の URL が見つかりません"
            return None
        try:
            v.level_db = self.measure(v.hls, sil["seconds"])
        except Exception as e:  # noqa: BLE001
            v.note = f"音量を測れません: {e}"
            log.warning("%s の音量を測れません: %s", v.source, e)
            return None
        return v.level_db < sil["threshold_db"]

    def check(self) -> LiveVideo:
        primary, fallbacks, sil = self._opts()
        fixed = video_id(primary)
        try:
            p = resolve(primary, self.get)
        except Exception:
            if fixed and not fallbacks:  # 動画を固定しているなら、調べられなくてもそのまま流す
                return LiveVideo(fixed, True, source=primary)
            if not fallbacks:
                raise
            p = LiveVideo(None, False, source=primary, note="いつもの配信を調べられません")

        if p.video and p.live:
            if sil["enabled"]:
                silent = self._silent(p, sil)
                self.silent_count = self.silent_count + 1 if silent else 0
            if self.silent_count < sil["switch_after"]:
                return p
            reason = "無音が続いているため"
        else:
            self.silent_count = 0
            reason = "いつもの配信が止まっているため"

        if not fallbacks:
            return p
        first = None
        for fb in fallbacks:
            try:
                f = resolve(fb, self.get)
            except Exception as e:  # noqa: BLE001
                log.warning("切り替え先 %s を調べられません: %s", fb, e)
                continue
            if not (f.video and f.live):
                continue
            f.reason, f.level_db = reason, p.level_db
            first = first or f
            if not sil["enabled"] or self._silent(f, sil) is not True:  # 切り替え先も無音なら次の候補へ
                f.level_db = p.level_db
                return f
        if first:
            first.level_db = p.level_db
            return first
        return p


def fetch_live(cfg: dict) -> LiveVideo:
    """（無音の見張りなし）いつもの配信だけを調べる。"""
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
