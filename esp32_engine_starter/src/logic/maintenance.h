#pragma once
// 点検・車検などの予定。設定画面で 1 行に 1 件、「名前 日付」か「名前 走行距離km」で書く。
//   車検 2027-05-20
//   タイヤ交換 45000km
// Arduino 非依存なので PC 上でテストできる。
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace starter {

// 1970-01-01 からの日数（グレゴリオ暦）
inline int32_t daysFromCivil(int y, unsigned m, unsigned d) {
  y -= m <= 2;
  const int era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = static_cast<unsigned>(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + static_cast<int32_t>(doe) - 719468;
}

struct MaintItem {
  char name[32] = {0};
  bool byDate = false;
  int32_t day = 0;   // byDate のとき：1970-01-01 からの日数
  int32_t km = 0;    // 走行距離で指定したとき：メーターの値 [km]
};

// "名前 2027-05-20" か "名前 45000km"。名前に空白を含めてもよい（最後の空白で分ける）
inline bool parseMaintLine(const char* line, MaintItem& out) {
  const char* sp = strrchr(line, ' ');
  if (!sp || sp == line) return false;
  size_t nameLen = sp - line;
  while (nameLen > 0 && line[nameLen - 1] == ' ') --nameLen;
  if (nameLen == 0) return false;
  if (nameLen >= sizeof(out.name)) nameLen = sizeof(out.name) - 1;
  const char* v = sp + 1;
  int y, m, d;
  char tail;
  if (sscanf(v, "%4d-%2d-%2d%c", &y, &m, &d, &tail) == 3) {
    if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return false;
    out.byDate = true;
    out.day = daysFromCivil(y, m, d);
  } else {
    char* end;
    long km = strtol(v, &end, 10);
    if (end == v || km <= 0 || km > 2000000 || strcmp(end, "km") != 0) return false;
    out.byDate = false;
    out.km = static_cast<int32_t>(km);
  }
  memcpy(out.name, line, nameLen);
  out.name[nameLen] = '\0';
  return true;
}

// 通知の段階。日付：30 日前・7 日前・前日・当日以降。距離：500km 前・100km 前・到達
// 段階が上がったときだけ通知する（同じ段階は 1 回だけ）
inline int maintLevel(const MaintItem& it, int32_t today, int32_t odoKm, bool odoKnown) {
  if (it.byDate) {
    int32_t left = it.day - today;
    if (left <= 0) return 4;
    if (left <= 1) return 3;
    if (left <= 7) return 2;
    if (left <= 30) return 1;
    return 0;
  }
  if (!odoKnown) return 0;
  int32_t left = it.km - odoKm;
  if (left <= 0) return 4;
  if (left <= 100) return 2;
  if (left <= 500) return 1;
  return 0;
}

}  // namespace starter
