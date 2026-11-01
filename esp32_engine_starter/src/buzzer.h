#pragma once
// ブザーの鳴らし方（短く 1 回、2 回、警報）。ブロックしない。
#include <Arduino.h>

class Buzzer {
 public:
  void begin();
  void beep(int times = 1);            // 短く times 回
  void alarm(uint32_t durationMs);     // 警報（断続音）を durationMs の間
  void stop();
  void loop(uint32_t nowMs);
  bool alarming() const { return alarmUntil_ != 0; }

 private:
  void set(bool on);
  int beepsLeft_ = 0;
  bool on_ = false;
  uint32_t nextAt_ = 0;
  uint32_t alarmUntil_ = 0;
};
