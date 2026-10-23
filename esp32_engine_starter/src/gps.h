#pragma once
// GPS（UART、NMEA）の読み取りと、走行（ACC ON〜OFF）ごとの距離・最高速度の集計。
#include <Arduino.h>

#include "nmea.h"

struct TripSummary {
  uint32_t durationSec = 0;
  float distanceKm = 0;
  float maxSpeedKmh = 0;
  bool hasFix = false;
  double endLat = 0, endLon = 0;
};

class Gps {
 public:
  void begin();
  void loop(uint32_t nowMs);
  bool present() const { return sawData_; }       // モジュールから文が届いているか
  bool hasFix(uint32_t nowMs) const { return fix_.valid && nowMs - fixMs_ < 5000; }
  const starter::GpsFix& fix() const { return fix_; }

  void startTrip(uint32_t nowMs);
  TripSummary endTrip(uint32_t nowMs);
  bool inTrip() const { return inTrip_; }

  // 最後に測位できた位置（駐車位置の通知用）
  bool lastKnown(double& lat, double& lon) const;
  void setLastKnown(double lat, double lon) {  // スリープから起きたとき、前回の駐車位置を戻す
    lastLat_ = lat;
    lastLon_ = lon;
    haveLast_ = true;
  }
  // 駐車モードに入る前にモジュールを待機させる（MediaTek 系・u-blox 系の両方の命令を送る）。
  // どちらも UART に何か届けば起きるので、begin() で起こす
  void standby();

 private:
  void handleLine(const char* line, uint32_t nowMs);
  char buf_[100];
  size_t len_ = 0;
  bool sawData_ = false;
  starter::GpsFix fix_;
  uint32_t fixMs_ = 0;
  bool haveLast_ = false;
  double lastLat_ = 0, lastLon_ = 0;

  bool inTrip_ = false;
  uint32_t tripStartMs_ = 0;
  double tripDistM_ = 0;
  float tripMaxKmh_ = 0;
  bool tripHavePrev_ = false;
  double prevLat_ = 0, prevLon_ = 0;
};
