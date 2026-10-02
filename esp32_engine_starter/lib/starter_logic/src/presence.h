#pragma once
// BLE ビーコン（キーホルダーに付けたタグ）の在・不在判定。
// Arduino 非依存なので PC 上でテストできる。
#include <stdint.h>

namespace starter {

enum class PresenceState : uint8_t { Unknown, Present, Absent };
enum class PresenceEvent : uint8_t { None, Arrived, Left };

struct PresenceConfig {
  int nearRssi = -75;               // この強さ以上で受信したら「近くに来た」
  int farRssi = -90;                // これより弱い受信は「圏外」とみなす
  uint32_t absentTimeoutMs = 30000; // 圏外がこの時間続いたら「離れた」
};

// 到着は nearRssi、離脱は farRssi 未満が absentTimeoutMs 続くことで判定する
// （ヒステリシスで境界付近のバタつきを防ぐ）。
// 起動直後は Unknown で、一度も Present にならない限り Left は発生しない。
class PresenceTracker {
 public:
  explicit PresenceTracker(const PresenceConfig& cfg = PresenceConfig()) { setConfig(cfg); }

  void setConfig(const PresenceConfig& cfg) {
    cfg_ = cfg;
    if (cfg_.nearRssi < cfg_.farRssi) cfg_.nearRssi = cfg_.farRssi;
  }
  const PresenceConfig& config() const { return cfg_; }

  // nowMs は update() と同じ時計（main loop の millis()）で渡すこと。
  void onSeen(int rssi, uint32_t nowMs) {
    lastRssi_ = rssi;
    lastSeenMs_ = nowMs;
    everSeen_ = true;
    if (rssi >= cfg_.farRssi) lastInRangeMs_ = nowMs;
    if (rssi >= cfg_.nearRssi) nearPending_ = true;
  }

  PresenceEvent update(uint32_t nowMs) {
    bool near = nearPending_;
    nearPending_ = false;
    if (state_ != PresenceState::Present && near) {
      state_ = PresenceState::Present;
      return PresenceEvent::Arrived;
    }
    if (state_ == PresenceState::Present &&
        static_cast<int32_t>(nowMs - lastInRangeMs_) > static_cast<int32_t>(cfg_.absentTimeoutMs)) {
      state_ = PresenceState::Absent;
      return PresenceEvent::Left;
    }
    return PresenceEvent::None;
  }

  PresenceState state() const { return state_; }
  bool everSeen() const { return everSeen_; }
  int lastRssi() const { return lastRssi_; }
  uint32_t lastSeenMs() const { return lastSeenMs_; }

 private:
  PresenceConfig cfg_;
  PresenceState state_ = PresenceState::Unknown;
  bool nearPending_ = false;
  bool everSeen_ = false;
  int lastRssi_ = -127;
  uint32_t lastSeenMs_ = 0;
  uint32_t lastInRangeMs_ = 0;
};

struct AutoLockInputs {
  bool enabled;
  bool engineRunning;
  bool lockWhileRunning;
  bool lowVoltage;
};

enum class AutoLockDecision : uint8_t { Lock, NoEvent, Disabled, EngineRunning, LowVoltage };

inline AutoLockDecision decideAutoLock(PresenceEvent ev, const AutoLockInputs& in) {
  if (ev != PresenceEvent::Left) return AutoLockDecision::NoEvent;
  if (!in.enabled) return AutoLockDecision::Disabled;
  if (in.lowVoltage) return AutoLockDecision::LowVoltage;
  if (in.engineRunning && !in.lockWhileRunning) return AutoLockDecision::EngineRunning;
  return AutoLockDecision::Lock;
}

}  // namespace starter
