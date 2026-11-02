#!/usr/bin/env python3
"""まとめリモコン（M5Stack Dial）の設定ファイル firmware/include/config.h を作る。

Mac のターミナルで:
  python3 universal_remote/tool/remote_setup.py
  python3 universal_remote/tool/remote_setup.py --secrets secrets.json   # Kindle ダッシュボード用に作った secrets.json を流用

1. Wi-Fi（2.4GHz）の SSID とパスワード、SwitchBot のトークンとシークレットを入れる
2. ハブ2 に登録してある赤外線リモコンを一覧にして、それぞれどの画面になるかを表示する
3. config.h を書き出す（学習ボタンの欄は、表示された候補を見て手で書き足す）

標準ライブラリだけで動く。
"""

from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import hmac
import json
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://api.switch-bot.com/v1.1"
FIRMWARE = Path(__file__).resolve().parent.parent / "firmware"

# firmware/lib/remote_core の kindFromRemoteType と同じ分け方
SCREENS = {
    "Air Conditioner": "エアコン画面（ダイヤル=温度、上=モード、真ん中=電源、下=風量）",
    "TV": "テレビ画面（ダイヤル=音量、上下=チャンネル、真ん中=電源）",
    "IPTV": "テレビ画面", "Streamer": "テレビ画面", "Set Top Box": "テレビ画面",
    "Speaker": "オーディオ画面（ダイヤル=音量、上=再生、下=一時停止）", "DVD": "オーディオ画面",
    "Light": "照明画面（ダイヤル=明るさ、真ん中=ON/OFF）",
    "Fan": "扇風機画面（ダイヤル=風量、上=首振り、下=タイマー）",
}


def headers(token: str, secret: str) -> dict[str, str]:
    t = str(int(time.time() * 1000))
    nonce = uuid.uuid4().hex
    sign = base64.b64encode(
        hmac.new(secret.encode(), (token + t + nonce).encode(), hashlib.sha256).digest()
    ).decode()
    return {"Authorization": token, "sign": sign, "t": t, "nonce": nonce,
            "Content-Type": "application/json; charset=utf8"}


def get(path: str, token: str, secret: str) -> dict:
    hdrs = headers(token, secret)
    try:
        req = urllib.request.Request(API + path, headers=hdrs)
        with urllib.request.urlopen(req, timeout=15) as res:
            data = json.load(res)
    except (urllib.error.URLError, ssl.SSLError) as e:
        reason = getattr(e, "reason", e)
        if not isinstance(reason, ssl.SSLError):
            raise
        # Python の証明書が入っていない Mac では macOS 標準の curl で通信する
        cmd = ["curl", "-sS", "--max-time", "15"]
        for k, v in hdrs.items():
            cmd += ["-H", f"{k}: {v}"]
        data = json.loads(subprocess.run(cmd + [API + path], capture_output=True, text=True,
                                         check=True).stdout)
    if data.get("statusCode") != 100:
        raise RuntimeError(f"SwitchBot API エラー: {data.get('statusCode')} {data.get('message')}")
    return data["body"]


def screen_for(remote_type: str) -> str:
    if remote_type.startswith("DIY"):
        return "ボタン一覧（電源 ON/OFF ＋ config.h に書いた学習ボタン）"
    if remote_type == "Others":
        return "ボタン一覧（config.h に書いた学習ボタンだけ）"
    return SCREENS.get(remote_type, "ボタン一覧（電源 ON/OFF ＋ 学習ボタン）")


def c_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_config(ssid: str, password: str, token: str, secret: str, remotes: list[dict],
                  template: str) -> str:
    out = template
    out = out.replace('#define WIFI_SSID "your-ssid"', f"#define WIFI_SSID {c_str(ssid)}")
    out = out.replace('#define WIFI_PASS "your-password"', f"#define WIFI_PASS {c_str(password)}")
    out = out.replace('#define SWITCHBOT_TOKEN "your-token"', f"#define SWITCHBOT_TOKEN {c_str(token)}")
    out = out.replace('#define SWITCHBOT_SECRET "your-secret"', f"#define SWITCHBOT_SECRET {c_str(secret)}")
    # 学習ボタンが要りそうなリモコンの書き方の見本を入れておく
    hints = [r for r in remotes if r["remoteType"].startswith("DIY") or r["remoteType"] == "Others"]
    if hints:
        lines = "".join(f'    // {{{c_str(r["deviceName"])}, "ボタン名"}},\n' for r in hints)
        out = out.replace("    {nullptr, nullptr},", lines + "    {nullptr, nullptr},")
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--secrets", help="Kindle ダッシュボードの secrets.json（トークンを流用）")
    ap.add_argument("--out", default=str(FIRMWARE / "include" / "config.h"))
    args = ap.parse_args(argv)

    token = secret = ""
    if args.secrets:
        indoor = json.loads(Path(args.secrets).read_text(encoding="utf-8")).get("indoor", {})
        token, secret = indoor.get("token", ""), indoor.get("secret", "")
    if not (token and secret):
        print("SwitchBot アプリ → プロフィール → 設定 → アプリバージョンを 10 回タップ → 開発者向けオプション")
        token = getpass.getpass("トークンを貼り付けて Enter（画面には出ません）: ").strip()
        secret = getpass.getpass("クライアントシークレットを貼り付けて Enter（画面には出ません）: ").strip()
    if not (token and secret):
        print("トークンとシークレットの両方が必要です")
        return 1

    print("リモコンを探しています…")
    try:
        body = get("/devices", token, secret)
        scenes = get("/scenes", token, secret)
    except (urllib.error.URLError, subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"接続できませんでした: {e}")
        return 1
    except RuntimeError as e:
        print(e, "（トークン・シークレットが正しいか確認してください）")
        return 1

    remotes = body.get("infraredRemoteList", [])
    hubs = [d for d in body.get("deviceList", []) if str(d.get("deviceType", "")).startswith("Hub")]
    if not remotes:
        print("赤外線リモコンが登録されていません。SwitchBot アプリでハブ2 にリモコンを追加してから、もう一度実行してください。")
        return 1

    print(f"\nハブ: {', '.join(h.get('deviceName', '') + '（' + h.get('deviceType', '') + '）' for h in hubs) or 'なし'}")
    print(f"リモコン {len(remotes)} 台（この順でダイヤルに並ぶ）:")
    for r in remotes:
        print(f"  ・{r['deviceName']}  [{r['remoteType']}] → {screen_for(r['remoteType'])}")
    if scenes:
        print(f"シーン {len(scenes)} 個: {', '.join(s['sceneName'] for s in scenes)}（最後のページに並ぶ）")

    print("\nリモコンをつなぐ Wi-Fi（2.4GHz）")
    ssid = input("SSID: ").strip()
    password = getpass.getpass("パスワード（画面には出ません）: ")

    template = (FIRMWARE / "include" / "config.example.h").read_text(encoding="utf-8")
    out = Path(args.out)
    if out.exists() and input(f"{out} を上書きしますか？ [y/N]: ").strip().lower() != "y":
        print("やめました")
        return 1
    out.write_text(render_config(ssid, password, token, secret, remotes, template), encoding="utf-8")
    print(f"\n✅ {out} を作りました")
    print("   学習ボタン（アプリでリモコンに追加したボタン）を使うなら CUSTOM_BUTTONS に書き足してください")
    print("   ※ パスワードとトークンが入っているので、人に送ったり Git に入れたりしないこと（.gitignore 済み）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
