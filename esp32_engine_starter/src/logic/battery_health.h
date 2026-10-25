#pragma once
// バッテリーの健康診断：始動時の電圧の落ち込み（クランキング電圧）と、走行中の充電不良。Arduino 非依存。
#include <stdint.h>

namespace starter {

// ACC が入ってから（エンジンがかかるまで、最長 windowMs）の最低電圧を記録する
class CrankMonitor {
 public:
  explicit CrankMonitor(uint32_t windowMs = 8000) : windowMs_(windowMs) {}

  void start(uint32_t nowMs) {
    active_ = true;
    done_ = false;
    startMs_ = nowMs;
    minV_ = 99.0f;
  }
  // 計測が終わった呼び出しで true を返す（minVolts() で結果を取る）
  bool feed(float volts, uint32_t nowMs) {
    if (!active_) return false;
    if (volts < minV_) minV_ = volts;
    if (static_cast<int32_t>(nowMs - startMs_) >= static_cast<int32_t>(windowMs_)) {
      active_ = false;
      done_ = true;
      return true;
    }
    return false;
  }
  // エンジンがかかったことを検出したら呼ぶ。計測中だったら true（minVolts() が結果）
  bool finish() {
    if (!active_) return false;
    active_ = false;
    done_ = true;
    return true;
  }
  bool active() const { return active_; }
  float minVolts() const { return minV_; }

 private:
  uint32_t windowMs_;
  bool active_ = false;
  bool done_ = false;
  uint32_t startMs_ = 0;
  float minV_ = 99.0f;
};

// エンジン稼働中なのに電圧が上がらない状態が holdMs 続いたら 1 回だけ true
class ChargeCheck {
 public:
  ChargeCheck(float minChargingV = 13.0f, uint32_t holdMs = 60000) : minV_(minChargingV), holdMs_(holdMs) {}

  bool update(bool engineRunning, float volts, uint32_t nowMs) {
    if (!engineRunning) {
      low_ = false;
      reported_ = false;
      return false;
    }
    if (volts >= minV_) {
      low_ = false;
      return false;
    }
    if (!low_) {
      low_ = true;
      since_ = nowMs;
    }
    if (!reported_ && static_cast<int32_t>(nowMs - since_) >= static_cast<int32_t>(holdMs_)) {
      reported_ = true;
      return true;
    }
    return false;
  }

 private:
  float minV_;
  uint32_t holdMs_;
  bool low_ = false;
  bool reported_ = false;
  uint32_t since_ = 0;
};

}  // namespace starter
