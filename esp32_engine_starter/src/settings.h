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
  String notifyServer;  // 通知だけ別のサーバーに送るとき（例：状態・指示は自前のサーバー、通知は iPhone にすぐ届く ntfy.sh）。空なら ntfyServer
  String notifyToken;   // そのサーバーのアクセストークン（使わなければ空）
  String pin;         // 指示の先頭に付ける暗証番号。設定画面で保存するときにも必要
  String otaPass;
  String hostname;
  String beacons[MAX_BEACONS];  // "aa:bb:cc:dd:ee:ff" か "uuid:..."
  float vbatCal = 1.0f;
  String cmdKey;        // 指示の署名の鍵（32 桁の 16 進。初回に自動で作る。ダッシュボードに入れる）
  bool tlsInsecure = false;  // サーバーの証明書を確かめない（自己署名の自前サーバー用）
  String maint;         // 点検の予定（1 行に 1 件：「車検 2027-05-20」「タイヤ交換 45000km」）
  int32_t odoKm = 0;    // メーターの走行距離を入力したときの値（0 なら未入力）
  float odoGpsKm = 0;   // そのときの GPS の累計距離

  void load();
  void save() const;
  // Wi-Fi と通知先が決まっている（普段どおり動ける）
  bool configured() const { return ssid1.length() > 0 && topic.length() > 0 && cmdTopic.length() > 0; }
  int beaconCount() const;
  const String& notifyBase() const { return notifyServer.length() ? notifyServer : ntfyServer; }
  const String& notifyAuth() const { return notifyServer.length() ? notifyToken : token; }
  // 状態・指示が ntfy.sh でない（自前のサーバー）。1 日の件数の上限を気にせず、短い間隔で送る
  bool selfHosted() const { return ntfyServer.length() && ntfyServer != "https://ntfy.sh"; }
  // 鍵がなければ作って保存する。ESP32 の乱数は無線が動いているときに本当の乱数になるので、Wi-Fi・BLE の開始後に呼ぶ
  void ensureKey();
  static String newKey();  // 32 桁の 16 進の乱数
};

extern Settings settings;
