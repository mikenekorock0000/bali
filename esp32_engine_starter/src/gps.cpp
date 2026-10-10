#include "gps.h"

#include "config.h"

using namespace starter;

void Gps::begin() { Serial2.begin(GPS_BAUD, SERIAL_8N1, PIN_GPS_RX, PIN_GPS_TX); }

void Gps::loop(uint32_t nowMs) {
  while (Serial2.available()) {
    char c = (char)Serial2.read();
    if (c == '\n' || c == '\r') {
      if (len_ > 0) {
        buf_[len_] = '\0';
        handleLine(buf_, nowMs);
        len_ = 0;
      }
    } else if (len_ < sizeof(buf_) - 1) {
      buf_[len_++] = c;
    } else {
      len_ = 0;  // 長すぎる行は捨てる
    }
  }
}

void Gps::handleLine(const char* line, uint32_t nowMs) {
  GpsFix f;
  if (!parseRmc(line, f)) return;
  sawData_ = true;
  fix_ = f;
  if (!f.valid) return;
  fixMs_ = nowMs;
  haveLast_ = true;
  lastLat_ = f.lat;
  lastLon_ = f.lon;
  if (!inTrip_) return;
  if (f.speedKmh > tripMaxKmh_) tripMaxKmh_ = f.speedKmh;
  // 停車中の位置のふらつきを距離に足さない
  if (tripHavePrev_ && f.speedKmh > 3.0f) {
    double d = haversineM(prevLat_, prevLon_, f.lat, f.lon);
    if (d < 200) tripDistM_ += d;  // 1 秒で 200m 以上は測位の飛びとみなす
  }
  prevLat_ = f.lat;
  prevLon_ = f.lon;
  tripHavePrev_ = true;
}

void Gps::startTrip(uint32_t nowMs) {
  inTrip_ = true;
  tripStartMs_ = nowMs;
  tripDistM_ = 0;
  tripMaxKmh_ = 0;
  tripHavePrev_ = false;
}

TripSummary Gps::endTrip(uint32_t nowMs) {
  TripSummary s;
  if (!inTrip_) return s;
  inTrip_ = false;
  s.durationSec = (nowMs - tripStartMs_) / 1000;
  s.distanceKm = tripDistM_ / 1000.0f;
  s.maxSpeedKmh = tripMaxKmh_;
  s.hasFix = haveLast_;
  s.endLat = lastLat_;
  s.endLon = lastLon_;
  return s;
}

bool Gps::lastKnown(double& lat, double& lon) const {
  lat = lastLat_;
  lon = lastLon_;
  return haveLast_;
}
