#pragma once
// OBD-II（ISO 15765-4、11bit ID、500kbps）の要求フレーム作成と応答解析。Arduino 非依存。
// 読み取り（モード 01）だけを扱う。車両の設定を変える要求は作らない。
#include <stdint.h>

namespace starter {

constexpr uint32_t OBD_REQ_ID = 0x7DF;  // 全 ECU 宛ての機能アドレス
constexpr uint8_t PID_STATUS = 0x01;    // MIL（警告灯）と故障コード数
constexpr uint8_t PID_COOLANT = 0x05;   // 冷却水温 [℃]
constexpr uint8_t PID_RPM = 0x0C;       // エンジン回転数 [rpm]
constexpr uint8_t PID_SPEED = 0x0D;     // 車速 [km/h]
constexpr uint8_t PID_VOLTAGE = 0x42;   // ECU 電源電圧 [V]

inline void obdRequest(uint8_t pid, uint8_t out[8]) {
  out[0] = 0x02;  // 後続バイト数
  out[1] = 0x01;  // モード 01（現在値の読み取り）
  out[2] = pid;
  for (int i = 3; i < 8; ++i) out[i] = 0x00;
}

// ECU からの応答（0x7E8〜0x7EF）を解析する。対応 PID なら pid と value を返す。
// PID_STATUS の value は生の A バイト（obdMilOn / obdDtcCount で分解する）。
inline bool obdParse(uint32_t id, const uint8_t* d, uint8_t len, uint8_t& pid, float& value) {
  if (id < 0x7E8 || id > 0x7EF || len < 4) return false;
  uint8_t n = d[0];
  if (n < 3 || n > 7 || d[1] != 0x41) return false;
  pid = d[2];
  uint8_t dataLen = n - 2;
  switch (pid) {
    case PID_RPM:
      if (dataLen < 2) return false;
      value = ((d[3] << 8) | d[4]) / 4.0f;
      return true;
    case PID_VOLTAGE:
      if (dataLen < 2) return false;
      value = ((d[3] << 8) | d[4]) / 1000.0f;
      return true;
    case PID_SPEED:
    case PID_STATUS:
      value = d[3];
      return true;
    case PID_COOLANT:
      value = static_cast<float>(d[3]) - 40.0f;
      return true;
    default:
      return false;
  }
}

inline bool obdMilOn(float statusA) { return (static_cast<uint8_t>(statusA) & 0x80) != 0; }
inline int obdDtcCount(float statusA) { return static_cast<uint8_t>(statusA) & 0x7F; }

}  // namespace starter
