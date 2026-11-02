// SwitchBot API v1.1 の最小クライアント（https://github.com/OpenWonderLabs/SwitchBotAPI）
#pragma once

#include <Arduino.h>

#include <string>
#include <vector>

#include "remote_core.h"

struct Remote {
  std::string id;
  std::string name;        // SwitchBot アプリで付けた名前
  std::string remoteType;  // "Air Conditioner" など
  rc::Kind kind;
};

struct Scene {
  std::string id;
  std::string name;
};

struct ApiResult {
  bool ok = false;
  int httpCode = 0;
  int statusCode = 0;  // SwitchBot の statusCode（100 が成功）
  String message;      // 画面に出す短い説明
};

class SwitchBot {
 public:
  SwitchBot(const char* token, const char* secret) : token_(token), secret_(secret) {}

  // ハブ2 に登録した赤外線リモコン一覧と、温湿度が読める機器の ID
  ApiResult listDevices(std::vector<Remote>& remotes, std::string& sensorId);
  ApiResult listScenes(std::vector<Scene>& scenes);
  ApiResult send(const rc::Command& cmd);
  ApiResult readSensor(const std::string& deviceId, float& temp, int& humidity);

 private:
  ApiResult request(const char* method, const String& path, const String& body, String& response);
  void signHeaders(String& t, String& nonce, String& sign);

  const char* token_;
  const char* secret_;
};
