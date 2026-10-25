#pragma once
// GPS の NMEA 文（RMC）の解析と、2 点間の距離。Arduino 非依存。
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

namespace starter {

struct GpsFix {
  bool valid = false;
  double lat = 0, lon = 0;  // 度（南緯・西経は負）
  float speedKmh = 0;
  int hh = 0, mm = 0, ss = 0;          // UTC
  int day = 0, month = 0, year = 0;  // year は 4 桁
};

inline int hexNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

// "$....*hh" のチェックサムを確認する（末尾の改行はあってもよい）
inline bool nmeaChecksumOk(const char* line) {
  if (!line || line[0] != '$') return false;
  uint8_t sum = 0;
  const char* p = line + 1;
  for (; *p && *p != '*'; ++p) sum ^= static_cast<uint8_t>(*p);
  if (*p != '*') return false;
  int h = hexNibble(p[1]), l = hexNibble(p[2]);
  return h >= 0 && l >= 0 && sum == ((h << 4) | l);
}

// ddmm.mmmm（緯度）/ dddmm.mmmm（経度）を度に変換
inline double nmeaToDeg(const char* field, char hemi) {
  double v = atof(field);
  double deg = floor(v / 100.0);
  double d = deg + (v - deg * 100.0) / 60.0;
  return (hemi == 'S' || hemi == 'W') ? -d : d;
}

// $GPRMC / $GNRMC を解析する。測位が無効（ステータス V）でも時刻は返し、valid=false にする。
inline bool parseRmc(const char* line, GpsFix& out) {
  if (!nmeaChecksumOk(line)) return false;
  if (strncmp(line + 3, "RMC,", 4) != 0) return false;
  char buf[100];
  size_t n = strcspn(line, "*");
  if (n >= sizeof(buf)) return false;
  memcpy(buf, line, n);
  buf[n] = '\0';

  const char* f[13] = {};
  int count = 0;
  char* p = buf;
  while (count < 13) {
    f[count++] = p;
    char* c = strchr(p, ',');
    if (!c) break;
    *c = '\0';
    p = c + 1;
  }
  if (count < 10) return false;

  GpsFix g;
  if (strlen(f[1]) >= 6) {
    g.hh = (f[1][0] - '0') * 10 + (f[1][1] - '0');
    g.mm = (f[1][2] - '0') * 10 + (f[1][3] - '0');
    g.ss = (f[1][4] - '0') * 10 + (f[1][5] - '0');
  }
  if (strlen(f[9]) >= 6) {
    g.day = (f[9][0] - '0') * 10 + (f[9][1] - '0');
    g.month = (f[9][2] - '0') * 10 + (f[9][3] - '0');
    g.year = 2000 + (f[9][4] - '0') * 10 + (f[9][5] - '0');
  }
  g.valid = f[2][0] == 'A' && f[3][0] && f[5][0];
  if (g.valid) {
    g.lat = nmeaToDeg(f[3], f[4][0]);
    g.lon = nmeaToDeg(f[5], f[6][0]);
    g.speedKmh = static_cast<float>(atof(f[7]) * 1.852);
  }
  out = g;
  return true;
}

inline double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000.0, k = M_PI / 180.0;
  double dlat = (lat2 - lat1) * k, dlon = (lon2 - lon1) * k;
  double a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * k) * cos(lat2 * k) * sin(dlon / 2) * sin(dlon / 2);
  return 2 * R * atan2(sqrt(a), sqrt(1 - a));
}

}  // namespace starter
