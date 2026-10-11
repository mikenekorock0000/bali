#!/usr/bin/env python3
"""回路シミュレーション（ngspice）と、データシート値による計算で、定格に収まるかを確認する。"""
import re
import subprocess
import sys

fails = []


def check(name, ok, detail):
    print(f"  {'ok' if ok else 'NG'}  {name}: {detail}")
    if not ok:
        fails.append(name)


def run(cir):
    out = subprocess.run(["ngspice", "-b", cir], capture_output=True, text=True).stdout
    return out


def nums(line):
    return [float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", line)]


print("== 電圧測定（R1 100k / R2 18k、BAT43 クランプ）")
for line in run("vsense.cir").splitlines():
    if "VBAT=" not in line:
        continue
    m = re.search(r"VBAT=(\S+)\s+VSENSE=\s*(\S+)", line)
    vb, vs = float(m.group(1)), float(m.group(2))
    if 9 <= vb <= 16:
        check(f"VBAT {vb}V", vs <= 2.45, f"GPIO34 = {vs:.2f}V（ADC 11dB の精度範囲 2.45V 以下）")
    elif vb > 16:
        check(f"VBAT {vb}V（異常電圧）", vs <= 3.6, f"GPIO34 = {vs:.2f}V（絶対最大 3.6V 以下）")
    elif vb < 0:
        check(f"VBAT {vb}V（逆接続）", vs >= -0.6, f"GPIO34 = {vs:.2f}V（-0.6V 以上なら保護ダイオードの電流は µA 級）")

print("== 絶縁入力（3.3k ＋ PC817 LED、1N4148 逆並列）")
for line in run("opto_in.cir").splitlines():
    if "VIN=" not in line:
        continue
    m = re.search(r"VIN=(\S+)\s+ILED\(mA\)=\s*(\S+)\*1000\s+VLED_rev=\s*(\S+)", line)
    vin, i, vled = float(m.group(1)), float(m.group(2)) * 1000, float(m.group(3))
    p = (i / 1000) ** 2 * 3300 * 1000
    if vin < 0:
        check(f"IN {vin}V（逆接続）", vled > -5.0, f"LED の逆電圧 {vled:.2f}V（最大 6V）")
    elif vin <= 16:
        # PC817 の CTR は低電流側で半分（50%）に見積もっても、プルアップ 10k の 0.33mA を十分引ける必要がある
        check(f"IN {vin}V", 1.0 <= i <= 50 and i * 0.5 >= 0.33 * 2 and p < 125,
              f"LED {i:.1f}mA（最大 50mA）、受光側で {i * 0.5:.1f}mA 以上引ける、3.3k の発熱 {p:.0f}mW（1/4W の半分以下）")
    else:
        # ジャンプスタート（24V）・抑制後のロードダンプ（35V）。抵抗の短時間過負荷は定格の 2.5 倍（5 秒）まで
        check(f"IN {vin}V（異常電圧）", i <= 50 and p < 625,
              f"LED {i:.1f}mA（最大 50mA）、3.3k の発熱 {p:.0f}mW（短時間過負荷 625mW 以下）")

print("== 絶縁出力（GPIO ─ 330Ω ─ PC817 LED）")
for line in run("opto_out.cir").splitlines():
    if "VGPIO=" not in line:
        continue
    m = re.search(r"VGPIO=(\S+)\s+IF\(mA\)=\s*(\S+)\*1000", line)
    vg, i = float(m.group(1)), float(m.group(2)) * 1000
    check(f"GPIO {vg}V", 3.5 <= i <= 20, f"LED {i:.1f}mA → 受光側で {i * 2:.0f}mA 程度まで引ける（GPIO の上限 20mA 以下）")

print("== ブザー駆動（1k / 10k、2SC1815）")
out = run("buzzer.cir")
on = [l for l in out.splitlines() if l.strip().startswith("ON")][0]
off = [l for l in out.splitlines() if l.strip().startswith("OFF")][0]
ib = float(re.search(r"Ib\(mA\)=\s*(\S+)\*1000", on).group(1)) * 1000
ic = float(re.search(r"Ic\(mA\)=\s*(\S+)\*1000", on).group(1)) * 1000
vce = float(re.search(r"Vce=\s*(\S+)", on).group(1))
icoff = float(re.search(r"Ic\(uA\)=\s*(\S+)\*1e6", off).group(1)) * 1e6
check("ON", vce < 0.3 and ib < 5, f"Ib {ib:.1f}mA、Ic {ic:.0f}mA、Vce {vce:.2f}V（飽和）")
check("OFF", icoff < 10, f"Ic {icoff:.3f}µA")

print("== 電源（データシート値による計算）")
# 5V 側のピーク電流 [A]
loads = {"ESP32（Wi-Fi 送信ピーク、3.3V レギュレーター経由）": 0.35, "MCP2562（ドミナント送信）": 0.07,
         "GPS モジュール": 0.05, "ブザー": 0.03, "BME280 / MPU6050": 0.01, "フォトカプラ LED（出力 4ch 最大）": 0.026}
i5 = sum(loads.values())
for k, v in loads.items():
    print(f"     {k}: {v * 1000:.0f}mA")
eff = 0.80  # M78AR05-1 の効率（データシートの代表値より低めに見積もる）
for vin in (9.0, 12.0, 14.7):
    iin = 5 * i5 / eff / (vin - 0.4)
    print(f"     入力 {vin}V のとき 12V 側 {iin * 1000:.0f}mA（効率 {eff:.0%}、SB340LS の降下 0.4V）")
iin9 = 5 * i5 / eff / (9.0 - 0.4)
check("DC-DC の出力電流", i5 <= 1.0, f"5V 側ピーク {i5 * 1000:.0f}mA（M78AR05-1 最大 1A）")
check("ポリスイッチ（85℃で保持電流が約 6 割に低下）", 1.1 * 0.6 >= iin9,
      f"RXEF110 保持 1.1A × 0.6 = {1.1 * 0.6:.2f}A ≥ 最大入力 {iin9:.2f}A（9V 時）")
check("ポリスイッチの耐圧", 72 >= 35, "RXEF110 の最大電圧 72V ≥ 抑制後のロードダンプ 35V")
check("逆接保護ダイオードの電流", 2.2 <= 3.0,
      "ポリスイッチが切れずに流れうる最大 2.2A（トリップ電流）≤ SB340LS の定格 3A")
check("逆接保護ダイオードのサージ電流", 18.9 <= 80, "TVS がクランプするときのピーク 18.9A（P4KE15A の Ipp）≤ SB340LS の IFSM 80A")
# 直列の TVS：P4KE15A（VRWM 12.8V、VBR 14.3〜15.8V、Vc 21.2V @ 18.9A）と P4KE6.8CA（VRWM 5.8V、VBR 6.45〜7.14V、Vc 10.5V @ 38A）。
# 流れる電流は小さい方の Ipp（18.9A）まで。P4KE6.8CA の 18.9A での電圧は VBR max と Vc の間を電流で直線補間（安全側）
i_pp = 18.9
v68 = 7.14 + (10.5 - 7.14) * i_pp / 38.0
vclamp = 21.2 + v68
check("TVS と DC-DC の入力上限", vclamp <= 32,
      f"P4KE15A 21.2V ＋ P4KE6.8CA {v68:.1f}V = {vclamp:.1f}V（{i_pp}A 時）≤ M78AR05-1 の入力上限 32V")
check("TVS が通常時に導通しない", 12.8 + 5.8 >= 14.8, "スタンドオフ 12.8V ＋ 5.8V = 18.6V ≥ 充電電圧の上限 14.8V")
check("DC-DC の最低入力", 6.5 <= 9.0 - 0.4, "M78AR05-1 の最低入力 6.5V。始動時に 9V まで落ちても SB340LS の後で 8.6V")
check("3.3V 系の電流", 0.35 + 0.05 + 0.01 + 0.002 <= 0.8,
      "ESP32 ＋ GPS ＋ センサー ＋ プルアップ 約 0.41A ≤ DevKit の AMS1117（1A、放熱を考え 0.8A まで）")

print("== 出力端子の保護（データシート値）")
check("出力 TVS が通常時に導通しない", 45 >= 24, "SMBJ45CA のスタンドオフ 45V ≥ ジャンプスタート時の 24V")
check("出力 TVS のクランプ電圧", 72.7 <= 80, "SMBJ45CA のクランプ 72.7V（Ipp 時）≤ PC817 X 系の VCEO 80V")
check("出力の電流", 0.05 <= 0.05, "PC817 のコレクタ電流 最大 50mA。リレーのコイルなどは 50mA 以下のもの（またはリレーモジュール）")

print(f"シミュレーション・計算: {len(fails)} 件の問題")
sys.exit(1 if fails else 0)
