#!/usr/bin/env python3
"""SwitchBot の室内センサーを Kindle ダッシュボードにつなぐための設定ファイル（secrets.json）を作る。

Mac のターミナルで:
  python3 switchbot_setup.py

1. SwitchBot アプリでトークンとシークレットを取っておく
   （プロフィール → 設定 → アプリバージョンを 10 回タップ → 開発者向けオプション）
2. このスクリプトを実行して貼り付ける
3. できた secrets.json を NAS の docker/kindle-dashboard/config/ に置いて、プロジェクトを再起動

温度を測れる機器（ハブ2・ハブ3・温湿度計・CO2センサー）を自動で探し、実際に値が読めるか確かめる。
標準ライブラリだけで動く（追加インストール不要）。
"""

from __future__ import annotations

import base64
import getpass
import hashlib
import hmac
import json
import ssl
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://api.switch-bot.com/v1.1"


def headers(token: str, secret: str) -> dict[str, str]:
    t = str(int(time.time() * 1000))
    nonce = uuid.uuid4().hex
    sign = base64.b64encode(
        hmac.new(secret.encode(), (token + t + nonce).encode(), hashlib.sha256).digest()
    ).decode()
    return {"Authorization": token, "sign": sign, "t": t, "nonce": nonce,
            "Content-Type": "application/json; charset=utf8"}


def get(path: str, token: str, secret: str) -> dict:
    req = urllib.request.Request(API + path, headers=headers(token, secret))
    with urllib.request.urlopen(req, timeout=15) as res:
        data = json.load(res)
    if data.get("statusCode") != 100:
        raise RuntimeError(f"SwitchBot API エラー: {data.get('statusCode')} {data.get('message')}")
    return data["body"]


def find_sensors(token: str, secret: str, fetch=get) -> list[dict]:
    """温度が読める機器を、今の値と一緒に返す。"""
    devices = fetch("/devices", token, secret).get("deviceList", [])
    sensors = []
    for d in devices:
        try:
            status = fetch(f"/devices/{d['deviceId']}/status", token, secret)
        except Exception:  # noqa: BLE001 - 状態を返さない機器（ボット等）は飛ばす
            continue
        if status.get("temperature") is not None:
            sensors.append({"id": d["deviceId"], "name": d.get("deviceName", ""),
                            "type": d.get("deviceType", ""), "temperature": status.get("temperature"),
                            "humidity": status.get("humidity"), "co2": status.get("CO2")})
    return sensors


def choose(sensors: list[dict], ask=input) -> dict:
    if len(sensors) == 1:
        return sensors[0]
    for i, s in enumerate(sensors, 1):
        co2 = f"  CO2 {s['co2']}ppm" if s["co2"] is not None else ""
        print(f"  {i}. {s['name']}（{s['type']}）  {s['temperature']}℃  {s['humidity']}%{co2}")
    while True:
        n = ask(f"どれを使いますか？ 1〜{len(sensors)} の番号: ").strip()
        if n.isdigit() and 1 <= int(n) <= len(sensors):
            return sensors[int(n) - 1]


def secrets_json(sensor: dict, token: str, secret: str) -> dict:
    return {"indoor": {"provider": "switchbot", "device_id": sensor["id"], "token": token, "secret": secret}}


def main() -> int:
    print("SwitchBot アプリ → プロフィール → 設定 → アプリバージョンを 10 回タップ → 開発者向けオプション")
    token = getpass.getpass("トークンを貼り付けて Enter（画面には出ません）: ").strip()
    secret = getpass.getpass("クライアントシークレットを貼り付けて Enter（画面には出ません）: ").strip()
    if not token or not secret:
        print("トークンとシークレットの両方が必要です")
        return 1

    print("機器を探しています…")
    try:
        sensors = find_sensors(token, secret)
    except urllib.error.URLError as e:
        if isinstance(getattr(e, "reason", None), ssl.SSLError):
            print("証明書のエラーです。python.org 版の Python なら「Applications/Python 3.x/Install Certificates.command」を実行してから再度お試しください。")
        else:
            print(f"接続できませんでした: {e}")
        return 1
    except RuntimeError as e:
        print(e, "（トークン・シークレットが正しいか確認してください）")
        return 1

    if not sensors:
        print("温度を測れる機器が見つかりませんでした（ハブ2・温湿度計などがアプリに登録されているか確認してください）")
        return 1

    sensor = choose(sensors)
    out = Path.cwd() / "secrets.json"
    out.write_text(json.dumps(secrets_json(sensor, token, secret), ensure_ascii=False, indent=2) + "\n",
                   encoding="utf-8")
    co2 = f" / CO2 {sensor['co2']}ppm" if sensor["co2"] is not None else ""
    print(f"\n✅ {sensor['name']}（{sensor['type']}）: {sensor['temperature']}℃ / {sensor['humidity']}%{co2}")
    print(f"✅ {out} を作りました")
    print("   → NAS の docker/kindle-dashboard/config/ に置いて、Container Manager でプロジェクトを再起動してください")
    print("   ※ トークンが入っているので、人に送ったり Git に入れたりしないこと")
    return 0


if __name__ == "__main__":
    sys.exit(main())
