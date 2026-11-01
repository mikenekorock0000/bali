#include "buzzer.h"

#include "config.h"

void Buzzer::begin() {
  digitalWrite(PIN_BUZZER, LOW);
  pinMode(PIN_BUZZER, OUTPUT);
}

void Buzzer::set(bool on) {
  on_ = on;
  digitalWrite(PIN_BUZZER, on ? HIGH : LOW);
}

void Buzzer::beep(int times) {
  if (alarming()) return;
  beepsLeft_ = times;
  nextAt_ = millis();
}

void Buzzer::alarm(uint32_t durationMs) {
  beepsLeft_ = 0;
  alarmUntil_ = millis() + durationMs;
  if (alarmUntil_ == 0) alarmUntil_ = 1;
  nextAt_ = millis();
}

void Buzzer::stop() {
  beepsLeft_ = 0;
  alarmUntil_ = 0;
  set(false);
}

void Buzzer::loop(uint32_t nowMs) {
  if (static_cast<int32_t>(nowMs - nextAt_) < 0) return;
  if (alarmUntil_) {
    if (static_cast<int32_t>(nowMs - alarmUntil_) >= 0) {
      stop();
      return;
    }
    set(!on_);
    nextAt_ = nowMs + (on_ ? 300 : 200);
    return;
  }
  if (on_) {
    set(false);
    nextAt_ = nowMs + 120;
  } else if (beepsLeft_ > 0) {
    --beepsLeft_;
    set(true);
    nextAt_ = nowMs + 80;
  }
}
