#include "io.h"

#include "config.h"

void Inputs::begin() {
  door_ = starter::Debouncer(DOOR_DEBOUNCE_MS);
  in2_ = starter::Debouncer(DOOR_DEBOUNCE_MS);
  acc_ = starter::Debouncer(ACC_DEBOUNCE_MS);
  pinMode(PIN_DOOR, INPUT_PULLUP);
  pinMode(PIN_IN2, INPUT);  // GPIO35/36 は内部プルアップが無い（基板の 10k を使う）
  pinMode(PIN_ACC, INPUT);
  loop(millis());  // 初期値を確定させる
}

bool Inputs::loop(uint32_t nowMs) {
  // フォトカプラは信号ありで LOW
  doorChanged = door_.update(digitalRead(PIN_DOOR) == LOW, nowMs);
  in2Changed = in2_.update(digitalRead(PIN_IN2) == LOW, nowMs);
  accChanged = acc_.update(digitalRead(PIN_ACC) == LOW, nowMs);
  return doorChanged || in2Changed || accChanged;
}

void PulseOutput::begin() {
  digitalWrite(pin_, LOW);
  pinMode(pin_, OUTPUT);
}

void PulseOutput::pulse(uint32_t ms, uint32_t nowMs) {
  on_ = true;
  pulsing_ = true;
  offAt_ = nowMs + ms;
  digitalWrite(pin_, HIGH);
}

void PulseOutput::set(bool on) {
  if (pulsing_) return;
  on_ = on;
  digitalWrite(pin_, on ? HIGH : LOW);
}

void PulseOutput::loop(uint32_t nowMs) {
  if (pulsing_ && static_cast<int32_t>(nowMs - offAt_) >= 0) {
    pulsing_ = false;
    on_ = false;
    digitalWrite(pin_, LOW);
  }
}
