"""カラー版（/fire）の背景写真。

標準の写真（dashboard/backgrounds/、Wikimedia Commons のパブリックドメイン・CC0）と、
NAS の config/backgrounds/ に置いた写真（同じ名前なら標準より優先）を、ファイル名（天気-時間帯）で
選べるように一覧にし、画面に合う大きさ（1600x1000 に切り抜き・JPEG）に縮めて配る。スマホの写真をそのまま置いてよい。

  clear-day.jpg      晴れの昼          rain-night.jpg   雨の夜
  clear.jpg          晴れ（時間帯問わず） night.jpg       夜（天気問わず）
  clear-day-2.jpg    同じ組み合わせの 2 枚目（1 時間ごとに入れ替わる）
"""

from __future__ import annotations

import io
import re
import threading
from pathlib import Path

from PIL import Image, ImageOps

EXTS = (".jpg", ".jpeg", ".png", ".webp")
SIZE = (1600, 1000)  # Fire HD 8（1280x800）より少し大きめ。16:10
_NAME = re.compile(r"^[a-z]+(?:-[a-z]+)?(?:-\d+)?$")


def _folders(folder) -> list[Path]:
    if not folder:
        return []
    return [f for f in (folder if isinstance(folder, (list, tuple)) else [folder]) if f]


def _usable(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    return [f for f in sorted(folder.iterdir())
            if f.is_file() and f.suffix.lower() in EXTS and _NAME.match(f.stem.lower()) and f.stem == f.stem.lower()]


def _resolve(folder) -> dict[str, Path]:
    """名前 → ファイル。前のフォルダほど優先（同じ名前（拡張子違いも）は前のもの）。"""
    out: dict[str, Path] = {}
    stems: set[str] = set()
    for d in _folders(folder):
        for f in _usable(d):
            if f.stem in stems:
                continue
            out[f.name] = f
        stems |= {f.stem for f in _usable(d)}
    return out


def list_photos(folder) -> list[str]:
    """使える写真のファイル名（拡張子つき, 小文字の名前だけ）。folder はフォルダかフォルダのリスト（前ほど優先）。"""
    return sorted(_resolve(folder))


class PhotoCache:
    """縮めた JPEG を（ファイルの更新時刻ごとに）覚えておく。"""

    def __init__(self, folder, size: tuple[int, int] = SIZE, quality: int = 82):
        self.folder, self.size, self.quality = folder, size, quality
        self._cache: dict[str, tuple[float, bytes]] = {}
        self._lock = threading.Lock()

    def get(self, name: str) -> bytes | None:
        f = _resolve(self.folder).get(name) if Path(name).name == name else None
        if not f:
            return None
        mtime = f.stat().st_mtime
        with self._lock:
            hit = self._cache.get(str(f))
            if hit and hit[0] == mtime:
                return hit[1]
        with Image.open(f) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")  # スマホ写真の向きを直す
            im = ImageOps.fit(im, self.size, Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=self.quality, optimize=True, progressive=True)
        data = buf.getvalue()
        with self._lock:
            self._cache[str(f)] = (mtime, data)
        return data
