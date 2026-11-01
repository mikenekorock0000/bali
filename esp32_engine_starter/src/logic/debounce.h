#pragma once
// 入力（ドア・ACC など）のチャタリング除去。stableMs の間同じ値が続いたら確定する。Arduino 非依存。
#include <stdint.h>

namespace starter {

class Debouncer {
 public:
  explicit Debouncer(uint32_t stableMs = 50) : stableMs_(stableMs) {}

  // 確定値が変わったときだけ true。最初の呼び出しは初期値の確定のみで false。
  bool update(bool raw, uint32_t nowMs) {
    if (!init_) {
      init_ = true;
      state_ = last_ = raw;
      since_ = changedAt_ = nowMs;
      return false;
    }
    if (raw != last_) {
      last_ = raw;
      since_ = nowMs;
    }
    if (raw != state_ && static_cast<int32_t>(nowMs - since_) >= static_cast<int32_t>(stableMs_)) {
      state_ = raw;
      changedAt_ = nowMs;
      return true;
    }
    return false;
  }

  bool state() const { return state_; }
  uint32_t changedAt() const { return changedAt_; }  // 最後に確定値が変わった時刻

 private:
  uint32_t stableMs_;
  bool init_ = false;
  bool state_ = false;
  bool last_ = false;
  uint32_t since_ = 0;
  uint32_t changedAt_ = 0;
};

}  // namespace starter
