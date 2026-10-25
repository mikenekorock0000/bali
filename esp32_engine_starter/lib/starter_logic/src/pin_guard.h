#pragma once
// 暗証番号の総当たり対策。決まった回数続けて間違えたら、しばらく受け付けない。
// ロックのたびに待ち時間を倍にする（上限あり）。Arduino 非依存なので PC 上でテストできる。
#include <stdint.h>

namespace starter {

class PinGuard {
 public:
  PinGuard(int maxFails, uint32_t lockMs, uint32_t maxLockMs)
      : maxFails_(maxFails), baseLockMs_(lockMs), maxLockMs_(maxLockMs) {}

  // 今、暗証番号を試してよいか
  bool allowed(uint32_t nowMs) const {
    return !locked_ || static_cast<int32_t>(nowMs - lockUntil_) >= 0;
  }
  // ロックが解けるまでの残り [ms]
  uint32_t remainingMs(uint32_t nowMs) const { return allowed(nowMs) ? 0 : lockUntil_ - nowMs; }

  void fail(uint32_t nowMs) {
    if (locked_ && allowed(nowMs)) locked_ = false;  // ロックが解けた後の最初の失敗
    if (++fails_ >= maxFails_) {
      fails_ = 0;
      locked_ = true;
      lockUntil_ = nowMs + lockMs();
      ++lockCount_;
    }
  }
  void success() {
    fails_ = 0;
    lockCount_ = 0;
    locked_ = false;
  }
  int lockCount() const { return lockCount_; }

 private:
  uint32_t lockMs() const {
    uint32_t ms = baseLockMs_;
    for (int i = 0; i < lockCount_ && ms < maxLockMs_; ++i) ms *= 2;
    return ms > maxLockMs_ ? maxLockMs_ : ms;
  }

  int maxFails_;
  uint32_t baseLockMs_, maxLockMs_;
  int fails_ = 0;
  int lockCount_ = 0;
  bool locked_ = false;
  uint32_t lockUntil_ = 0;
};

}  // namespace starter
