#pragma once
// BLE をパッシブスキャンし、登録ビーコンの受信を main loop に渡す。
// スキャンのコールバックは NimBLE のタスクで動くため、ここではスピンロックで
// 受信結果を溜めるだけにして、判定は main loop 側（PresenceTracker）で行う。
#include <Arduino.h>
#include <ArduinoJson.h>

#include "beacon.h"
#include "config.h"

class BlePresence {
 public:
  void begin();
  void setRules(const starter::BeaconRule* rules, int n);
  void setEnabled(bool on);  // 低電圧時はスキャンを止めて消費電流を抑える
  bool enabled() const { return enabled_; }
  void loop();

  // 前回呼び出し以降に登録ビーコンを受信していれば最大 RSSI を返す。
  bool takeMatch(int& rssi);

  // 設定画面用：最近見えた BLE 機器（ビーコン登録の候補）
  void nearbyToJson(JsonArray arr, uint32_t nowMs) const;

  // コールバックから呼ばれる
  void onAdvert(const uint8_t mac[6], const char* name, int rssi, const uint8_t* mfg, size_t mfgLen);

 private:
  struct Nearby {
    uint8_t mac[6];
    char name[24];
    int8_t rssi;
    uint32_t seenMs;
    bool isIBeacon;
    starter::IBeacon ib;
  };
  static constexpr int NEARBY_MAX = 16;

  mutable portMUX_TYPE mux_ = portMUX_INITIALIZER_UNLOCKED;
  starter::BeaconRule rules_[MAX_BEACONS];
  int ruleCount_ = 0;
  bool pending_ = false;
  int pendingRssi_ = -127;
  Nearby nearby_[NEARBY_MAX] = {};
  bool enabled_ = false;
};
