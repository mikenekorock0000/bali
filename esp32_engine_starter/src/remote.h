#pragma once
// 予備リモコンのボタンをフォトカプラで「押す」。ブロックしないキュー方式。
#include <Arduino.h>

#include "config.h"

enum class RemoteAction : uint8_t { Start, Stop, Lock, Unlock };

const char* remoteActionName(RemoteAction a);

class RemoteControl {
 public:
  void begin();
  bool enqueue(RemoteAction a);  // キューが一杯なら false
  void loop(uint32_t nowMs);
  bool idle() const { return !active_ && count_ == 0; }

 private:
  static const ButtonSpec& spec(RemoteAction a);
  void release();

  static constexpr int QUEUE_LEN = 4;
  RemoteAction queue_[QUEUE_LEN];
  int head_ = 0;
  int count_ = 0;

  bool active_ = false;
  bool pressed_ = false;
  ButtonSpec cur_ = {-1, 0, 0, 0};
  uint8_t remaining_ = 0;
  uint32_t phaseEndMs_ = 0;
  uint32_t readyAtMs_ = 0;
};
