#pragma once
// 絶縁入力（ドア・ACC など、チャタリング除去付き）と絶縁出力（施錠信号などのパルス）。
#include <Arduino.h>

#include "logic/debounce.h"

class Inputs {
 public:
  void begin();
  // 確定値が変わった入力があれば true
  bool loop(uint32_t nowMs);
  bool doorOpen() const { return door_.state(); }
  bool acc() const { return acc_.state(); }
  bool in2() const { return in2_.state(); }
  uint32_t doorChangedAt() const { return door_.changedAt(); }

  // 前回の loop() で変化したもの
  bool doorChanged = false;
  bool accChanged = false;
  bool in2Changed = false;

 private:
  starter::Debouncer door_{0}, acc_{0}, in2_{0};
};

class PulseOutput {
 public:
  explicit PulseOutput(int pin) : pin_(pin) {}
  void begin();
  void pulse(uint32_t ms, uint32_t nowMs);  // ms の間 ON にして自動で OFF
  void set(bool on);                         // パルス中でなければそのまま ON/OFF
  void loop(uint32_t nowMs);
  bool on() const { return on_; }

 private:
  int pin_;
  bool on_ = false;
  bool pulsing_ = false;
  uint32_t offAt_ = 0;
};
