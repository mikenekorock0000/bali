#pragma once
// OBD-II の読み取り（ESP32 内蔵 CAN = TWAI ＋ MCP2562）。モード 01 の現在値だけを要求する。
// ACC OFF のときは MCP2562 を待機（STBY=HIGH）にして、車両の CAN に一切関与しない。
#include <Arduino.h>

class Obd {
 public:
  void begin();
  void setActive(bool on, uint32_t nowMs);  // ACC に合わせて ON/OFF
  void loop(uint32_t nowMs);
  bool active() const { return active_; }

  // 直近の値（stale なら無効）
  bool fresh(uint32_t nowMs) const { return active_ && nowMs - lastRxMs_ < 5000; }
  float rpm = NAN;
  float speedKmh = NAN;
  float coolantC = NAN;
  bool milOn = false;
  int dtcCount = 0;
  bool statusKnown = false;

 private:
  bool active_ = false;
  bool driverUp_ = false;
  uint32_t lastTxMs_ = 0;
  uint32_t lastRxMs_ = 0;
  uint8_t next_ = 0;
};
