#!/usr/bin/env python3
"""ピン配置の照合。gen_pcb.py とは別に、データシートと実物の写真から書き起こした表で確かめる。

- ESP32 DevKit V1（30 ピン、HW-394。基板に直接はんだ付け）のピン名は、購入したボードの写真のシルク印刷から
- 各部品のピン機能はデータシートから
- ファームウェアの config.h のピン番号とも突き合わせる
  python3 check_pins.py hijet_starter.kicad_pcb ../src/config.h
"""
import re
import sys

import pcbnew

# ---- ESP32 DevKit V1（HW-394）のピン。写真のシルク印刷を USB 側から読んだ順 ----
VIN_ROW_FROM_USB = ["VIN", "GND", "D13", "D12", "D14", "D27", "D26", "D25", "D33", "D32", "D35", "D34", "VN", "VP", "EN"]
V33_ROW_FROM_USB = ["3V3", "GND", "D15", "D2", "D4", "D16", "D17", "D5", "D18", "D19", "D21", "RX0", "TX0", "D22", "D23"]
# 基板上では 1 番ピンがアンテナ側（USB と反対）。J5 = VIN 列、J6 = 3V3 列
ESP = {}
for i, name in enumerate(reversed(VIN_ROW_FROM_USB)):
    ESP[name] = ("J5", str(i + 1))
for i, name in enumerate(reversed(V33_ROW_FROM_USB)):
    ESP.setdefault(name, ("J6", str(i + 1)))  # GND は両列にあるので VIN 列を代表にする
ESP["GND_R"] = ("J6", "14")
GPIO = {"VP": 36, "VN": 39}
GPIO.update({f"D{n}": n for n in (2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35)})
INPUT_ONLY = {34, 35, 36, 39}
STRAPPING = {0, 2, 5, 12, 15}
ADC1 = {32, 33, 34, 35, 36, 39}

# ---- 同じネットにつながっているべきピンの組（機能で書く） ----
# "ESP:名前" は ESP32 のピン、"Ux.n" などは部品のピン（番号はデータシート）
SAME_NET = [
    # 電源：J1(1=+12V) → F1（RXEF110）→ D1（SB340LS）アノード(2)… カソード(1) → TVS（P4KE15A）カソード(1)、そのアノード → P4KE6.8CA → GND、C1 +(1)、OKI Vin(1)
    ["J1.1", "F1.1"], ["F1.2", "D1.2", "J1.3", "R1.1"], ["D1.1", "D2.1", "C1.1", "U1.1"], ["D2.2", "D12.1"],
    # M78AR05-1（LM78xx と同じ並び）：1=+Vin、2=GND、3=+Vout → ESP32 の VIN、C2 +、C3、MCP2562 VDD(3)、ブザー +
    ["U1.3", "ESP:VIN", "C2.1", "C3.1", "U9.3", "BZ1.1", "C5.1", "D7.1"],
    ["U1.2", "ESP:GND", "ESP:GND_R", "D12.2", "C1.2", "C2.2", "C3.2", "J1.2"],
    # 電圧測定：R1(12V_F)–VSENSE–R2–GND、C4、BAT43 アノード(2) → VSENSE、カソード(1) → 3V3
    ["R1.2", "R2.2", "C4.1", "D3.2", "ESP:D34"], ["R2.1", "C4.2", "ESP:GND"], ["D3.1", "ESP:3V3"],
    # 絶縁出力：GPIO → 330Ω → PC817 アノード(1)、カソード(2)=GND、3=エミッタ、4=コレクタ → 端子。
    # 端子の 2 本の間に双方向 TVS（D8〜D11、向きなし）
    ["R3.2", "ESP:D25"], ["R3.1", "U2.1"], ["U2.2", "ESP:GND"], ["U2.3", "J2.1", "D8.2"], ["U2.4", "J2.2", "D8.1"],
    ["R4.2", "ESP:D26"], ["R4.1", "U3.1"], ["U3.2", "ESP:GND"], ["U3.3", "J2.3", "D9.2"], ["U3.4", "J2.4", "D9.1"],
    ["R5.2", "ESP:D27"], ["R5.1", "U4.1"], ["U4.2", "ESP:GND"], ["U4.3", "J2.5", "D10.2"], ["U4.4", "J2.6", "D10.1"],
    ["R6.2", "ESP:D32"], ["R6.1", "U5.1"], ["U5.2", "ESP:GND"], ["U5.3", "J2.7", "D11.2"], ["U5.4", "J2.8", "D11.1"],
    # 絶縁入力：IN+ → 3.3k → PC817 アノード(1)、カソード(2) → IN-、1N4148 は K(1)=アノード側 A(2)=IN-
    ["J3.1", "R7.1"], ["R7.2", "U6.1", "D4.1"], ["U6.2", "D4.2", "J3.2"], ["U6.3", "ESP:GND"],
    ["U6.4", "R10.1", "ESP:D33"], ["R10.2", "ESP:3V3"],
    ["J3.3", "R8.1"], ["R8.2", "U7.1", "D5.1"], ["U7.2", "D5.2", "J3.4"], ["U7.3", "ESP:GND"],
    ["U7.4", "R11.1", "ESP:D35"], ["R11.2", "ESP:3V3"],
    ["J3.5", "R9.1"], ["R9.2", "U8.1", "D6.1"], ["U8.2", "D6.2", "J3.6"], ["U8.3", "ESP:GND"],
    ["U8.4", "R12.1", "ESP:VP"], ["R12.2", "ESP:3V3"],
    # MCP2562：1 TXD、2 VSS、3 VDD、4 RXD、5 VIO、6 CANL、7 CANH、8 STBY
    ["U9.1", "ESP:D18"], ["U9.2", "ESP:GND"], ["U9.4", "ESP:D19"], ["U9.5", "ESP:3V3", "C6.1"],
    ["U9.6", "J7.2"], ["U9.7", "J7.1"], ["U9.8", "R15.1", "ESP:D4"], ["R15.2", "ESP:3V3"], ["J7.3", "ESP:GND"],
    ["C5.2", "C6.2", "ESP:GND"],
    # ブザー：GPIO13 → 1k → 2SC1815 ベース(3)、エミッタ(1)=GND、コレクタ(2)=ブザー −、ベース 10k → GND
    ["R13.2", "ESP:D13"], ["R13.1", "R14.1", "Q1.3"], ["R14.2", "Q1.1", "ESP:GND"], ["Q1.2", "BZ1.2", "D7.2"],
    # I2C（J4：GND, 3V3, SCL, SDA）と GPS（J8：GND, 3V3, GPS の RX へ, GPS の TX から）
    ["J4.1", "ESP:GND"], ["J4.2", "ESP:3V3"], ["J4.3", "ESP:D22"], ["J4.4", "ESP:D21"],
    ["J8.1", "ESP:GND"], ["J8.2", "ESP:3V3"], ["J8.3", "ESP:D17"], ["J8.4", "ESP:D16"],
]

# ---- ファームウェアの config.h の定数 → つながるべき ESP32 のピン ----
CONFIG_PINS = {
    "PIN_OUT_LOCK": "D25", "PIN_OUT2": "D26", "PIN_OUT3": "D27", "PIN_OUT4": "D32",
    "PIN_DOOR": "D33", "PIN_IN2": "D35", "PIN_ACC": "VP", "PIN_VBAT": "D34",
    "PIN_CAN_TX": "D18", "PIN_CAN_RX": "D19", "PIN_CAN_STBY": "D4", "PIN_BUZZER": "D13",
    "PIN_GPS_TX": "D17", "PIN_GPS_RX": "D16", "PIN_I2C_SDA": "D21", "PIN_I2C_SCL": "D22",
}
OUTPUT_PINS = {"PIN_OUT_LOCK", "PIN_OUT2", "PIN_OUT3", "PIN_OUT4", "PIN_CAN_TX", "PIN_CAN_STBY", "PIN_BUZZER",
               "PIN_GPS_TX", "PIN_I2C_SDA", "PIN_I2C_SCL"}


def main():
    board = pcbnew.LoadBoard(sys.argv[1])
    config = open(sys.argv[2], encoding="utf-8").read()
    pad_net = {}
    for fp in board.GetFootprints():
        for p in fp.Pads():
            pad_net[f"{fp.GetReference()}.{p.GetNumber()}"] = p.GetNetname()

    def resolve(t):
        if t.startswith("ESP:"):
            ref, num = ESP[t[4:]]
            return f"{ref}.{num}"
        return t

    errors = []
    for group in SAME_NET:
        pins = [resolve(t) for t in group]
        nets = {pin: pad_net.get(pin) for pin in pins}
        if None in nets.values() or "" in nets.values() or len(set(nets.values())) != 1:
            errors.append(f"同じネットのはず: {group} → {nets}")
        if len(group) == 1:
            continue
    print(f"接続の照合: {len(SAME_NET)} 組")

    # 使っている ESP32 のピンの性質
    used = {}
    for name, (ref, num) in ESP.items():
        net = pad_net.get(f"{ref}.{num}", "")
        if net and name in GPIO:
            used[name] = net
    for name in used:
        g = GPIO[name]
        if g in STRAPPING:
            errors.append(f"ESP32 の起動設定ピン GPIO{g}（{name}）を使っている")
    for const, name in CONFIG_PINS.items():
        m = re.search(rf"constexpr int {const} = (\d+);", config)
        if not m:
            errors.append(f"config.h に {const} がない")
            continue
        if int(m.group(1)) != GPIO[name]:
            errors.append(f"config.h の {const} = {m.group(1)} だが基板は GPIO{GPIO[name]}（{name}）")
        if const in OUTPUT_PINS and GPIO[name] in INPUT_ONLY:
            errors.append(f"{const}: GPIO{GPIO[name]} は入力専用なので出力に使えない")
        if name not in used:
            errors.append(f"{const}: ESP32 の {name} が基板でどこにもつながっていない")
    if GPIO["D34"] not in ADC1:
        errors.append("電圧測定は Wi-Fi 使用中も使える ADC1 のピンでなければならない")
    print(f"config.h の照合: {len(CONFIG_PINS)} 本")
    for e in errors:
        print("  NG  ", e)
    print(f"ピン照合: {len(errors)} 件の問題")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
