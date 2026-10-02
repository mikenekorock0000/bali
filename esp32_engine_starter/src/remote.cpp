#include "remote.h"

const char* remoteActionName(RemoteAction a) {
  switch (a) {
    case RemoteAction::Start: return "始動";
    case RemoteAction::Stop: return "停止";
    case RemoteAction::Lock: return "施錠";
    case RemoteAction::Unlock: return "解錠";
  }
  return "?";
}

const ButtonSpec& RemoteControl::spec(RemoteAction a) {
  switch (a) {
    case RemoteAction::Start: return BTN_START;
    case RemoteAction::Stop: return BTN_STOP;
    case RemoteAction::Lock: return BTN_LOCK;
    default: return BTN_UNLOCK;
  }
}

void RemoteControl::begin() {
  for (const ButtonSpec* b : {&BTN_START, &BTN_STOP, &BTN_LOCK, &BTN_UNLOCK}) {
    digitalWrite(b->pin, LOW);
    pinMode(b->pin, OUTPUT);
  }
}

bool RemoteControl::enqueue(RemoteAction a) {
  if (count_ >= QUEUE_LEN) return false;
  queue_[(head_ + count_) % QUEUE_LEN] = a;
  ++count_;
  return true;
}

void RemoteControl::release() {
  digitalWrite(cur_.pin, LOW);
  pressed_ = false;
}

void RemoteControl::loop(uint32_t nowMs) {
  if (active_) {
    if (static_cast<int32_t>(nowMs - phaseEndMs_) < 0) return;
    if (pressed_) {
      release();
      if (--remaining_ == 0) {
        active_ = false;
        readyAtMs_ = nowMs + ACTION_GAP_MS;
      } else {
        phaseEndMs_ = nowMs + cur_.gapMs;
      }
    } else {
      digitalWrite(cur_.pin, HIGH);
      pressed_ = true;
      phaseEndMs_ = nowMs + cur_.pressMs;
    }
    return;
  }
  if (count_ == 0 || static_cast<int32_t>(nowMs - readyAtMs_) < 0) return;
  RemoteAction a = queue_[head_];
  head_ = (head_ + 1) % QUEUE_LEN;
  --count_;
  cur_ = spec(a);
  remaining_ = cur_.count ? cur_.count : 1;
  active_ = true;
  pressed_ = true;
  digitalWrite(cur_.pin, HIGH);
  phaseEndMs_ = nowMs + cur_.pressMs;
}
