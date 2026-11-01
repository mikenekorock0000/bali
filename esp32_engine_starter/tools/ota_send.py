#!/usr/bin/env python3
"""ファームウェアを ntfy の指示のトピックに添付して送り、ESP32 に遠隔更新させる。

ダッシュボードの「ファームウェアを更新」と同じことをする（GitHub Actions から自動で呼ぶ。手元からも使える）。
指示は「指示の鍵」で署名し、ファイルの SHA-256 を指示に含める。ESP32 は中身がこの値と一致したときだけ書き込む。

    HIJET_CMD_KEY=… HIJET_NTFY_SERVER=https://ntfy.takuya.win HIJET_CMD_TOPIC=… \\
    HIJET_NTFY_TOKEN=tk_… python3 tools/ota_send.py build/firmware.bin

標準ライブラリだけで動く（CI に余計なものを入れないため）。
"""
import hashlib
import hmac
import os
import sys
import time
import urllib.request

# ESP32 のファームウェアの先頭は必ず 0xE9。違うファイルを送って書き込みに失敗するのを、送る前に防ぐ
ESP_IMAGE_MAGIC = 0xE9
# ntfy.sh の添付の上限は 2MB。自前のサーバーでも server.yml で 4MB にしている
MAX_SIZE = 2 * 1024 * 1024


def sign(key: str, ts: int, cmd: str) -> str:
    """ESP32 の hmac_sha256.h とダッシュボードの signCommand() と同じ計算（先頭 16 バイトを 16 進）"""
    mac = hmac.new(key.encode(), f"{ts} {cmd}".encode(), hashlib.sha256).hexdigest()
    return mac[:32]


def need(name: str) -> str:
    v = os.environ.get(name, "").strip()
    if not v:
        sys.exit(f"環境変数 {name} がありません")
    return v


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("使い方: ota_send.py <firmware.bin>")
    data = open(sys.argv[1], "rb").read()
    if not data or data[0] != ESP_IMAGE_MAGIC:
        sys.exit("ESP32 のファームウェアではありません（先頭が 0xE9 でない）")
    if len(data) > MAX_SIZE:
        sys.exit(f"大きすぎます（{len(data)} バイト。上限 {MAX_SIZE}）")

    key = need("HIJET_CMD_KEY")
    server = need("HIJET_NTFY_SERVER").rstrip("/")
    topic = need("HIJET_CMD_TOPIC")
    token = os.environ.get("HIJET_NTFY_TOKEN", "").strip()

    sha = hashlib.sha256(data).hexdigest()
    cmd = f"ota {sha}"
    ts = int(time.time())
    message = f"sig1 {ts} {sign(key, ts, cmd)} {cmd}"

    req = urllib.request.Request(f"{server}/{topic}", data=data, method="PUT")
    req.add_header("Filename", "firmware.bin")
    req.add_header("X-Message", message)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as r:
        if r.status // 100 != 2:
            sys.exit(f"送れませんでした（HTTP {r.status}）")
    print(f"送りました：{len(data)} バイト、SHA-256 {sha}")


if __name__ == "__main__":
    main()
