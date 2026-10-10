#pragma once
// I2C センサー：BME280（車内の温度・湿度・気圧）と MPU6050（振動・傾き）。
// どちらも未接続なら自動で無効になる（あとから挿しても再起動すれば認識）。
#include <Arduino.h>

class Sensors {
 public:
  void begin();
  void loop(uint32_t nowMs);

  bool hasEnv() const { return hasBme_; }
  float tempC() const { return tempC_; }
  float humidity() const { return hum_; }
  float pressureHpa() const { return pres_; }

  bool hasMotion() const { return hasMpu_; }
  // 前回呼び出し以降に、基準の姿勢から MOTION_G を超える揺れがあったら true
  bool takeMotion();
  float lastShakeG() const { return lastShake_; }
  void rebaseline() { baseValid_ = false; }  // 警戒開始時に今の姿勢を基準にする

 private:
  bool readAccel(float& x, float& y, float& z);

  bool hasBme_ = false;
  bool hasMpu_ = false;
  float tempC_ = NAN, hum_ = NAN, pres_ = NAN;
  uint32_t lastEnvMs_ = 0;
  uint32_t lastAccMs_ = 0;
  bool baseValid_ = false;
  float bx_ = 0, by_ = 0, bz_ = 0;
  bool motion_ = false;
  float lastShake_ = 0;
};
