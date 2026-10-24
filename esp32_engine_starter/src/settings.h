#pragma once
// 利用者ごとの設定（Wi-Fi、ntfy、暗証番号、ビーコンなど）。ESP32 の NVS（フラッシュ）に保存し、
// 車の近くで設定モード（ESP32 が出す Wi-Fi「HIJET-SETUP-xxxx」）の画面から変える。
// 初めて起動したときだけ、secrets.h（あれば）の値を初期値として使う。
#include <Arduino.h>

#include "config.h"

struct Settings {
  String ssid1, pass1;  // 主に使う Wi-Fi（車内のテザリングなど）
  String ssid2, pass2;  // 予備の Wi-Fi（自宅など。空なら使わない）
  String ntfyServer;
  String topic;       // 通知
  String cmdTopic;    // スマホ・ダッシュボードからの指示
  String stateTopic;  // ダッシュボード用の状態（スマホのアプリでは購読しない）
  String token;       // ntfy のアクセストークン（使わなければ空）
  String pin;         // 指示の先頭に付ける暗証番号。設定画面で保存するときにも必要
  String otaPass;
  String hostname;
  String beacons[MAX_BEACONS];  // "aa:bb:cc:dd:ee:ff" か "uuid:..."
  float vbatCal = 1.0f;

  void load();
  void save() const;
  // Wi-Fi と通知先が決まっている（普段どおり動ける）
  bool configured() const { return ssid1.length() > 0 && topic.length() > 0 && cmdTopic.length() > 0; }
  int beaconCount() const;
};

extern Settings settings;
