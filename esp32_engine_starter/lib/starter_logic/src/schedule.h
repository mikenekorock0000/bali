#pragma once
// 曜日・時刻指定のスケジュール始動の判定。Arduino 非依存。
#include <stdint.h>
#include <time.h>

namespace starter {

struct ScheduleEntry {
  bool enabled = false;
  uint8_t days = 0;    // bit0=日, bit1=月 ... bit6=土（struct tm の tm_wday と同じ並び）
  uint8_t hour = 0;
  uint8_t minute = 0;
};

// 同じ日に二重起動しないための日付キー。
inline int32_t dayKey(const struct tm& t) { return (t.tm_year + 1900) * 1000 + t.tm_yday; }

// 指定時刻から windowMin 分以内で、その日まだ発火していなければ true。
// ループの遅れや再起動で指定の 1 分を逃しても始動できるよう幅を持たせている。
// 日付をまたぐ幅（例: 23:59 + 3 分）は考慮しない。
inline bool scheduleDue(const ScheduleEntry& e, const struct tm& now, int32_t lastFiredDay,
                        int windowMin = 3) {
  if (!e.enabled || e.hour > 23 || e.minute > 59) return false;
  if (!(e.days & (1u << now.tm_wday))) return false;
  if (lastFiredDay == dayKey(now)) return false;
  int diff = (now.tm_hour * 60 + now.tm_min) - (e.hour * 60 + e.minute);
  return diff >= 0 && diff < windowMin;
}

}  // namespace starter
