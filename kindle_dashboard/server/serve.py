#!/usr/bin/env python3
"""Kindle ダッシュボードのサーバー。

  python serve.py                   # 配信を開始（http://<このPCのIP>:8080/dash.png）
  python serve.py render --demo     # ダミーデータで out/ に画像を1枚書き出す
  python serve.py render            # 実データを取得して out/ に書き出す
"""

from __future__ import annotations

import argparse
import logging
import socket
import sys
from pathlib import Path

from dashboard.app import SERVER_DIR, Dashboard, build_store, clock, load_config, make_server
from dashboard.demo import demo_data
from dashboard.render import Fonts, png_bytes, render, to_kindle


def lan_ip() -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("192.0.2.1", 80))  # 実際には送信しない（経路の確認だけ）
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def cmd_serve(cfg: dict, fonts: Fonts) -> None:
    now = clock(cfg)
    store = build_store(cfg, now)
    store.run_forever()
    server = make_server(Dashboard(cfg, store, fonts, now), cfg["host"], cfg["port"])
    host = "<NASのIP>" if Path("/.dockerenv").exists() else lan_ip()  # コンテナ内の IP は外から使えない
    print(f"配信中: http://{host}:{cfg['port']}/dash.png  （確認用: /preview.png, /health）")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


def cmd_render(cfg: dict, fonts: Fonts, demo: bool, out: Path) -> None:
    now = clock(cfg)
    if demo:
        data = demo_data(now())
    else:
        store = build_store(cfg, now)
        store.refresh_due()
        for name, s in store.status()["sources"].items():
            print(f"  {name}: {'OK' if s['ok'] else 'NG ' + s['error']}")
        data = Dashboard(cfg, store, fonts, now).data()

    d = cfg["display"]
    img = render(data, fonts, d["width"], d["height"])
    out.mkdir(parents=True, exist_ok=True)
    (out / "preview.png").write_bytes(png_bytes(to_kindle(img, 0)))
    (out / "dash.png").write_bytes(png_bytes(to_kindle(img, d["rotate"])))
    print(f"書き出しました: {out / 'preview.png'}, {out / 'dash.png'}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", type=Path, default=SERVER_DIR / "config.json")
    sub = parser.add_subparsers(dest="cmd")
    sub.add_parser("serve", help="配信を開始（既定）")
    r = sub.add_parser("render", help="画像を1枚書き出す")
    r.add_argument("--demo", action="store_true", help="ダミーデータで描画")
    r.add_argument("--out", type=Path, default=SERVER_DIR / "out")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = load_config(args.config)
    fonts = Fonts(cfg.get("font_path"), SERVER_DIR, cfg.get("clock"))

    if args.cmd == "render":
        cmd_render(cfg, fonts, args.demo, args.out)
    else:
        cmd_serve(cfg, fonts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
