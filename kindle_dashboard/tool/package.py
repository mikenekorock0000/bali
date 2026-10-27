#!/usr/bin/env python3
"""NAS 用と Kindle 用の配布 zip を dist/ に作る。

  python kindle_dashboard/tool/package.py
  # 自分用（設定ファイルとポートを入れた完全版。リポジトリには入れない）
  python kindle_dashboard/tool/package.py --config my-config.json --port 8090 --out ~/kindle-dashboard-nas-my.zip
"""

import argparse
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


def build_nas(config: Path | None = None, port: int | None = None, out: Path | None = None) -> Path:
    """config / port を渡すと、その設定を入れた完全版（フォルダごと上書きできる）を作る。"""
    server = ROOT / "server"
    out = out or DIST / "kindle-dashboard-nas.zip"
    with zipfile.ZipFile(out, "w") as z:
        for name in NAS_FILES:
            if name == "docker-compose.yml" and port:
                compose = (server / name).read_text(encoding="utf-8").replace('"8080:8080"', f'"{port}:8080"')
                add_text(z, compose, f"kindle-dashboard/{name}")
            else:
                add(z, server / name, f"kindle-dashboard/{name}")
        for d in NAS_DIRS:
            for f in sorted((server / d).rglob("*.py")):
                add(z, f, f"kindle-dashboard/{f.relative_to(server)}")
        # そのまま使える設定ファイル（既定は example。緯度・経度だけ直す）
        add(z, config or server / "config.example.json", "kindle-dashboard/config/config.json")
        add(z, ROOT / "NAS_SETUP.md", "kindle-dashboard/NAS_SETUP.md")
    return out


def add_text(z: zipfile.ZipFile, text: str, arc: str) -> None:
    info = zipfile.ZipInfo(arc, date_time=(2026, 1, 1, 0, 0, 0))
    info.external_attr = 0o644 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, text.encode("utf-8"))


def build_kindle() -> Path:
    """dashboard/（Kindle のルートへ）と documents/（Scriptlets）を入れる。"""
    kindle = ROOT / "kindle"
    out = DIST / "kindle-dashboard-kindle.zip"
    with zipfile.ZipFile(out, "w") as z:
        for d in ("dashboard", "documents"):
            for f in sorted((kindle / d).rglob("*")):
                if f.is_file() and f.name != "dashboard.log":
                    add(z, f, str(f.relative_to(kindle)))
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, help="同梱する config.json（自分用の完全版を作るとき）")
    parser.add_argument("--port", type=int, help="NAS 側のポート（docker-compose.yml の左側）")
    parser.add_argument("--out", type=Path, help="NAS 用 zip の出力先")
    args = parser.parse_args()
    DIST.mkdir(exist_ok=True)
    paths = [build_nas(args.config, args.port, args.out)]
    if not args.out:
        paths.append(build_kindle())
    for path in paths:
        with zipfile.ZipFile(path) as z:
            print(f"{path}  ({len(z.namelist())} files)")
            for n in z.namelist():
                print("   ", n)
