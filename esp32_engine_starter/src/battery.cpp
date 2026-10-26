#include "battery.h"

#include "config.h"
#include "settings.h"

void Battery::begin() {
  analogSetPinAttenuation(PIN_VBAT, ADC_11db);
  pinMode(PIN_VBAT, INPUT);
}

float Battery::sampleNow() const {
  uint32_t mv = 0;
  for (int i = 0; i < 4; ++i) mv += analogReadMilliVolts(PIN_VBAT);
  return (mv / 4.0f) / 1000.0f * VBAT_DIVIDER * settings.vbatCal;
}

void Battery::loop(uint32_t nowMs) {
  if (nowMs - lastSampleMs_ < 200) return;
  lastSampleMs_ = nowMs;

  float v = (sampleNow() + sampleNow()) / 2.0f;
  volts_ = valid_ ? volts_ * 0.8f + v * 0.2f : v;  // スターター作動時の瞬間的な落ち込みをならす
  valid_ = true;

  if (!running_ && volts_ >= VBAT_RUNNING_ON) running_ = true;
  if (running_ && volts_ <= VBAT_RUNNING_OFF) running_ = false;

  if (volts_ < VBAT_LOW && volts_ >= VBAT_BENCH) {  // 6V 未満は 12V 未接続（机の上）なので低電圧にしない
    if (!below_) {
      below_ = true;
      belowSinceMs_ = nowMs;
    }
    if (nowMs - belowSinceMs_ >= VBAT_LOW_HOLD_MS) low_ = true;
  } else {
    below_ = false;
    if (volts_ >= VBAT_LOW_RECOVER) low_ = false;
  }
}
