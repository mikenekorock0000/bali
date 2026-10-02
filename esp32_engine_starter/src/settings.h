#pragma once
// ユーザー設定（スケジュール・自動ロック・ビーコン）。NVS に JSON で保存する。
#include <Arduino.h>
#include <ArduinoJson.h>

#include "beacon.h"
#include "config.h"
#include "presence.h"
#include "schedule.h"

struct Settings {
  starter::ScheduleEntry schedules[MAX_SCHEDULES];
  int scheduleCount = 0;

  bool autoLockEnabled = false;
  bool lockWhileRunning = false;
  int nearRssi = -75;
  int farRssi = -90;
  uint32_t absentSec = 30;

  starter::BeaconRule beacons[MAX_BEACONS];
  int beaconCount = 0;

  float vbatCal = 1.0f;     // 実測電圧 ÷ 表示電圧 で補正
  float minStartV = 12.2f;  // これ未満なら始動しない

  starter::PresenceConfig presenceConfig() const;
  void toJson(JsonDocument& doc) const;
  // 不正な値があれば err に理由を入れて false。成功時のみ自身を書き換える。
  bool fromJson(const JsonDocument& doc, String& err);

  void load();
  void save() const;
};
