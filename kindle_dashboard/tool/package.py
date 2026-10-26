#!/usr/bin/env python3
"""NAS 用と Kindle 用の配布 zip を dist/ に作る。

  python kindle_dashboard/tool/package.py
"""

import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"

# NAS（Docker）に置くもの。フォントはイメージ作成時に取得するので入れない
NAS_FILES = [
    "Dockerfile", ".dockerignore", "docker-compose.yml", "requirements.txt",
    "serve.py", "fetch_fonts.py", ".env.example", "config.example.json",
]
NAS_DIRS = ["dashboard"]


def add(z: zipfile.ZipFile, src: Path, arc: str) -> None:
    info = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))  # 中身が同じなら zip も同じに
    info.external_attr = (0o755 if src.suffix in (".sh", ".py") else 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, src.read_bytes())


def build_nas() -> Path:
    server = ROOT / "server"
    out = DIST / "kindle-dashboard-nas.zip"
    with zipfile.ZipFile(out, "w") as z:
        for name in NAS_FILES:
            add(z, server / name, f"kindle-dashboard/{name}")
        for d in NAS_DIRS:
            for f in sorted((server / d).rglob("*.py")):
                add(z, f, f"kindle-dashboard/{f.relative_to(server)}")
        # そのまま使える設定ファイル（緯度・経度だけ直す）
        add(z, server / "config.example.json", "kindle-dashboard/config/config.json")
        add(z, ROOT / "NAS_SETUP.md", "kindle-dashboard/NAS_SETUP.md")
    return out


def build_kindle() -> Path:
    ext = ROOT / "kindle" / "extensions"
    out = DIST / "kindle-dashboard-kindle.zip"
    with zipfile.ZipFile(out, "w") as z:
        for f in sorted((ext / "dashboard").rglob("*")):
            if f.is_file() and f.name != "dashboard.log":
                add(z, f, f"extensions/{f.relative_to(ext)}")
    return out


if __name__ == "__main__":
    DIST.mkdir(exist_ok=True)
    for path in (build_nas(), build_kindle()):
        with zipfile.ZipFile(path) as z:
            print(f"{path.relative_to(ROOT.parent)}  ({len(z.namelist())} files)")
            for n in z.namelist():
                print("   ", n)
