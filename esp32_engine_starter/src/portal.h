#pragma once
// 設定モード：ESP32 が自分の Wi-Fi（HIJET-SETUP-xxxx）を出し、つないだスマホに設定画面を表示する。
// 入るのは、未設定のとき・DevKit の BOOT ボタンを 3 秒押したとき・ACC ON なのに Wi-Fi につながらないとき・
// 指示 "setup" を受けたとき。保存すると再起動する。一定時間で自動的に終わる（未設定のときは終わらない）。
#include <Arduino.h>
#include <ArduinoJson.h>

class SetupPortal {
 public:
  using NearbyFn = void (*)(JsonArray arr);
  using KmFn = float (*)();

  void start(const char* reason, uint32_t nowMs);
  void stop();
  void loop(uint32_t nowMs);
  bool active() const { return active_; }
  String apName() const;
  void setNearbyProvider(NearbyFn fn) { nearby_ = fn; }
  void setGpsKmProvider(KmFn fn) { gpsKm_ = fn; }  // メーターの値を入れたときの GPS の累計距離

 private:
  void handleRoot();
  void handleSave();
  void handleScan();
  void handleBle();
  void handleRedirect();
  void handleKey();

  bool active_ = false;
  bool serverUp_ = false;
  uint32_t startedMs_ = 0;
  uint32_t restartAt_ = 0;
  String reason_;
  NearbyFn nearby_ = nullptr;
  KmFn gpsKm_ = nullptr;
};

extern SetupPortal portal;
