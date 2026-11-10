"""カラー版（/fire）の背景写真。

NAS の config/backgrounds/ に置いた写真を、ファイル名（天気-時間帯）で選べるように一覧にし、
画面に合う大きさ（1600x1000 に切り抜き・JPEG）に縮めて配る。スマホの写真をそのまま置いてよい。

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


def list_photos(folder: Path | None) -> list[str]:
    """使える写真のファイル名（拡張子つき, 小文字の名前だけ）。"""
    if not folder or not folder.is_dir():
        return []
    out = []
    for f in sorted(folder.iterdir()):
        if f.is_file() and f.suffix.lower() in EXTS and _NAME.match(f.stem.lower()) and f.stem == f.stem.lower():
            out.append(f.name)
    return out


class PhotoCache:
    """縮めた JPEG を（ファイルの更新時刻ごとに）覚えておく。"""

    def __init__(self, folder: Path | None, size: tuple[int, int] = SIZE, quality: int = 82):
        self.folder, self.size, self.quality = folder, size, quality
        self._cache: dict[str, tuple[float, bytes]] = {}
        self._lock = threading.Lock()

    def get(self, name: str) -> bytes | None:
        if not self.folder or Path(name).name != name or name not in list_photos(self.folder):
            return None
        f = self.folder / name
        mtime = f.stat().st_mtime
        with self._lock:
            hit = self._cache.get(name)
            if hit and hit[0] == mtime:
                return hit[1]
        with Image.open(f) as im:
            im = ImageOps.exif_transpose(im).convert("RGB")  # スマホ写真の向きを直す
            im = ImageOps.fit(im, self.size, Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, "JPEG", quality=self.quality, optimize=True, progressive=True)
        data = buf.getvalue()
        with self._lock:
            self._cache[name] = (mtime, data)
        return data
