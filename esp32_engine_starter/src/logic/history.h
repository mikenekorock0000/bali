#pragma once
// ダッシュボードのグラフ用の履歴（電圧・車内温度）。決まった間隔で 1 点ずつ記録する輪のバッファ。
// Arduino 非依存なので PC 上でテストできる。ESP32 では RTC メモリに置き、ディープスリープをまたいで残す。
#include <stdint.h>

namespace starter {

struct HistPoint {
  uint32_t t;      // 時刻（UNIX 秒）
  uint16_t cv;     // 電圧 [0.01V]
  int16_t temp10;  // 車内温度 [0.1℃]。不明なら TEMP_NONE
};

constexpr int16_t TEMP_NONE = -32768;

template <int N>
class History {
 public:
  // 前の点から intervalSec 以上たっていれば記録して true。時計が戻った（再起動で 0 から）ときも記録する
  bool maybeAdd(uint32_t t, float volts, float tempC, uint32_t intervalSec) {
    if (count_ > 0) {
      uint32_t last = at(count_ - 1).t;
      if (t >= last && t - last < intervalSec) return false;
    }
    HistPoint p;
    p.t = t;
    float cv = volts * 100.0f + 0.5f;
    p.cv = cv < 0 ? 0 : cv > 65535 ? 65535 : static_cast<uint16_t>(cv);
    if (tempC != tempC || tempC < -100 || tempC > 150) {  // NaN か範囲外
      p.temp10 = TEMP_NONE;
    } else {
      p.temp10 = static_cast<int16_t>(tempC * 10.0f + (tempC >= 0 ? 0.5f : -0.5f));
    }
    buf_[(head_ + count_) % N] = p;
    if (count_ < N) {
      ++count_;
    } else {
      head_ = (head_ + 1) % N;
    }
    return true;
  }

  int size() const { return count_; }
  // 0 が一番古い
  const HistPoint& at(int i) const { return buf_[(head_ + i) % N]; }
  void clear() { head_ = count_ = 0; }
  // RTC メモリに置いたとき、中身が壊れていないか（電源投入直後はでたらめな値）
  bool sane() const { return head_ >= 0 && head_ < N && count_ >= 0 && count_ <= N; }

 private:
  HistPoint buf_[N];
  int head_ = 0;
  int count_ = 0;
};

}  // namespace starter
