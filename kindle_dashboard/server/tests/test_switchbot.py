import importlib.util
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from dashboard import sources
from dashboard.app import SERVER_DIR, load_config
from dashboard.demo import demo_data
from dashboard.render import Fonts, render

SETUP = Path(__file__).resolve().parents[2] / "tool" / "switchbot_setup.py"
spec = importlib.util.spec_from_file_location("switchbot_setup", SETUP)
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


def fake_api(path, token, secret):
    assert (token, secret) == ("tok", "sec")
    if path == "/devices":
        return {"deviceList": [
            {"deviceId": "BOT1", "deviceName": "ボット", "deviceType": "Bot"},
            {"deviceId": "HUB2", "deviceName": "リビングのハブ", "deviceType": "Hub 2"},
            {"deviceId": "CO2", "deviceName": "寝室", "deviceType": "MeterPro(CO2)"},
        ]}
    return {"BOT1": {"power": "on"},
            "HUB2": {"temperature": 22.4, "humidity": 48, "lightLevel": 10},
            "CO2": {"temperature": 21.0, "humidity": 55, "CO2": 780}}[path.split("/")[2]]


def test_setup_finds_only_sensors():
    sensors = setup.find_sensors("tok", "sec", fetch=fake_api)
    assert [s["id"] for s in sensors] == ["HUB2", "CO2"]
    assert sensors[0]["co2"] is None and sensors[1]["co2"] == 780


def test_setup_choose_and_secrets():
    sensors = setup.find_sensors("tok", "sec", fetch=fake_api)
    answers = iter(["9", "x", "1"])
    chosen = setup.choose(sensors, ask=lambda _: next(answers))
    assert chosen["id"] == "HUB2"
    assert setup.secrets_json(chosen, "tok", "sec") == {
        "indoor": {"provider": "switchbot", "device_id": "HUB2", "token": "tok", "secret": "sec"}}
    assert setup.choose(sensors[:1])["id"] == "HUB2"  # 1 台なら聞かない


def test_setup_signature_matches_server():
    h = setup.headers("tok", "sec")
    assert h["sign"] == sources.switchbot_headers("tok", "sec", t=h["t"], nonce=h["nonce"])["sign"]


def test_secrets_json_is_merged(tmp_path):
    (tmp_path / "config.json").write_text(json.dumps({"location": {"name": "飯塚"}}), encoding="utf-8")
    (tmp_path / "secrets.json").write_text(json.dumps(
        {"indoor": {"provider": "switchbot", "device_id": "HUB2", "token": "t", "secret": "s"}}), encoding="utf-8")
    cfg = load_config(tmp_path / "config.json")
    assert cfg["location"]["name"] == "飯塚"
    assert cfg["indoor"] == {"provider": "switchbot", "device_id": "HUB2", "token": "t", "secret": "s"}


def test_fetch_indoor_uses_config_credentials(monkeypatch):
    seen = {}

    def fake_get_json(url, headers=None, timeout=15):
        seen["url"], seen["auth"] = url, headers["Authorization"]
        return {"statusCode": 100, "body": {"temperature": 22.4, "humidity": 48}}

    monkeypatch.setattr(sources, "http_get_json", fake_get_json)
    cfg = {"indoor": {"provider": "switchbot", "device_id": "HUB2", "token": "t", "secret": "s"}}
    ind = sources.fetch_indoor(cfg, {})
    assert (ind.temperature, ind.humidity, ind.co2) == (22.4, 48, None)
    assert seen["url"].endswith("/devices/HUB2/status") and seen["auth"] == "t"


@pytest.mark.parametrize("humidity,label", [(None, ""), (35, "乾燥"), (50, "快適"), (75, "多湿")])
def test_comfort_level(humidity, label):
    assert sources.comfort_level(humidity) == label


def test_render_indoor_without_co2():
    data = demo_data(datetime(2026, 10, 27, 14, 0, tzinfo=ZoneInfo("Asia/Tokyo")))
    data.indoor = sources.Indoor(22.4, 48, None)
    assert render(data, Fonts(None, SERVER_DIR)).size == (1024, 758)
