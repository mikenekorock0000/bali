#include "sensors.h"

#include <Adafruit_BME280.h>
#include <Wire.h>

#include "config.h"

namespace {
Adafruit_BME280 bme;
constexpr uint8_t MPU_ADDR = 0x68;
constexpr uint8_t MPU_PWR_MGMT_1 = 0x6B;
constexpr uint8_t MPU_ACCEL_CONFIG = 0x1C;
constexpr uint8_t MPU_ACCEL_XOUT_H = 0x3B;
constexpr uint8_t MPU_WHO_AM_I = 0x75;

bool writeReg(uint8_t addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission() == 0;
}
}  // namespace

void Sensors::begin() {
  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  Wire.setTimeOut(50);
  hasBme_ = bme.begin(0x76, &Wire) || bme.begin(0x77, &Wire);

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_WHO_AM_I);
  if (Wire.endTransmission(false) == 0 && Wire.requestFrom(MPU_ADDR, (uint8_t)1) == 1) {
    uint8_t who = Wire.read();
    // 互換チップ（MPU6500 など）も WHO_AM_I が違うだけで加速度の読み方は同じ
    hasMpu_ = who == 0x68 || who == 0x70 || who == 0x71 || who == 0x98;
  }
  if (hasMpu_) {
    writeReg(MPU_ADDR, MPU_PWR_MGMT_1, 0x00);    // スリープ解除
    writeReg(MPU_ADDR, MPU_ACCEL_CONFIG, 0x00);  // ±2g（16384 LSB/g）
  }
}

void Sensors::sleep() {
  if (hasMpu_) writeReg(MPU_ADDR, MPU_PWR_MGMT_1, 0x40);  // SLEEP ビット（約 4mA → 数 µA）
  if (hasBme_) {
    bme.setSampling(Adafruit_BME280::MODE_SLEEP);
  }
}

bool Sensors::readAccel(float& x, float& y, float& z) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_ACCEL_XOUT_H);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(MPU_ADDR, (uint8_t)6) != 6) return false;
  int16_t raw[3];
  for (int i = 0; i < 3; ++i) raw[i] = (int16_t)((Wire.read() << 8) | Wire.read());
  x = raw[0] / 16384.0f;
  y = raw[1] / 16384.0f;
  z = raw[2] / 16384.0f;
  return true;
}

void Sensors::loop(uint32_t nowMs) {
  if (hasBme_ && nowMs - lastEnvMs_ >= 10000) {
    lastEnvMs_ = nowMs;
    tempC_ = bme.readTemperature();
    hum_ = bme.readHumidity();
    pres_ = bme.readPressure() / 100.0f;
  }
  if (hasMpu_ && nowMs - lastAccMs_ >= 50) {
    lastAccMs_ = nowMs;
    float x, y, z;
    if (!readAccel(x, y, z)) return;
    if (!baseValid_) {
      bx_ = x, by_ = y, bz_ = z;
      baseValid_ = true;
      return;
    }
    float d = sqrtf((x - bx_) * (x - bx_) + (y - by_) * (y - by_) + (z - bz_) * (z - bz_));
    if (d > MOTION_G) {
      motion_ = true;
      if (d > lastShake_) lastShake_ = d;
    }
    // ゆっくりした傾きの変化（気温による沈み込みなど）には基準を追従させる
    bx_ += (x - bx_) * 0.01f;
    by_ += (y - by_) * 0.01f;
    bz_ += (z - bz_) * 0.01f;
  }
}

bool Sensors::takeMotion() {
  bool m = motion_;
  motion_ = false;
  if (!m) lastShake_ = 0;
  return m;
}
