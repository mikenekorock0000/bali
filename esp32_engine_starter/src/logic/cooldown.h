#pragma once
// 同じ種類の通知を一定時間出さないための間引き。Arduino 非依存。
#include <stdint.h>

namespace starter {

template <int N>
class Cooldown {
 public:
  // key（0..N-1）の前回許可から periodMs 経っていれば true にして時刻を記録する
  bool allow(int key, uint32_t nowMs, uint32_t periodMs) {
    if (key < 0 || key >= N) return false;
    if (used_[key] && static_cast<int32_t>(nowMs - last_[key]) < static_cast<int32_t>(periodMs)) return false;
    used_[key] = true;
    last_[key] = nowMs;
    return true;
  }
  void reset(int key) {
    if (key >= 0 && key < N) used_[key] = false;
  }

 private:
  uint32_t last_[N] = {};
  bool used_[N] = {};
};

}  // namespace starter
