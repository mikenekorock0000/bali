#pragma once
// バッテリー電圧の監視と、電圧からのエンジン稼働・低電圧判定。
#include <Arduino.h>

class Battery {
 public:
  void begin();
  void loop(uint32_t nowMs);
  // 平均をとらない即時値（始動時の電圧の落ち込みを捉えるため）
  float sampleNow() const;
  float volts() const { return volts_; }
  bool valid() const { return valid_; }
  bool chargingVoltage() const { return running_; }  // 発電中の電圧か（OBD が無いときの稼働判定）
  bool lowVoltage() const { return low_; }

 private:
  float volts_ = 0;
  bool valid_ = false;
  bool running_ = false;
  bool low_ = false;
  uint32_t lastSampleMs_ = 0;
  uint32_t belowSinceMs_ = 0;
  bool below_ = false;
};
