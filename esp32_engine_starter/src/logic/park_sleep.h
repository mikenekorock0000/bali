#pragma once
// 駐車モード（キーが離れて施錠した後、ESP32 をディープスリープさせて駐車中の消費電流を減らす）の判定。
// Arduino 非依存なので PC 上でテストできる。
#include <stdint.h>

namespace starter {

struct ParkInputs {
  bool enabled;        // 駐車モードを使う設定
  bool acc;            // ACC ON
  bool engineRunning;
  bool keyAbsent;      // キー（ビーコン）が「離れている」と確定している
  bool doorOpen;
  bool busy;           // 施錠待ち・ブザー鳴動中・未送信の通知あり・自動ロック一時停止中など
};

// 条件がそろってから idleMs 続いたら眠ってよい。条件が 1 つでも崩れたら数え直す。
class ParkSleepTimer {
 public:
  explicit ParkSleepTimer(uint32_t idleMs) : idleMs_(idleMs) {}

  // 眠ってよいとき true
  bool update(const ParkInputs& in, uint32_t nowMs) {
    bool ok = in.enabled && !in.acc && !in.engineRunning && in.keyAbsent && !in.doorOpen && !in.busy;
    if (!ok) {
      since_ = 0;
      counting_ = false;
      return false;
    }
    if (!counting_) {
      counting_ = true;
      since_ = nowMs;
    }
    return nowMs - since_ >= idleMs_;
  }

  // 起きた直後など、条件がそろっていても最初から数え直したいとき
  void restart() { counting_ = false; }
  void setIdleMs(uint32_t ms) { idleMs_ = ms; }

 private:
  uint32_t idleMs_;
  uint32_t since_ = 0;
  bool counting_ = false;
};

// ドアが開いて起きたとき：猶予時間内にキーが見つからなければ侵入とみなす
enum class DoorWakeVerdict : uint8_t { Waiting, Owner, Intrusion };

inline DoorWakeVerdict judgeDoorWake(bool keySeen, bool acc, uint32_t sinceWakeMs, uint32_t graceMs) {
  if (keySeen || acc) return DoorWakeVerdict::Owner;  // ACC ON はスマートキーが車内にあるときだけ
  if (sinceWakeMs < graceMs) return DoorWakeVerdict::Waiting;
  return DoorWakeVerdict::Intrusion;
}

}  // namespace starter
