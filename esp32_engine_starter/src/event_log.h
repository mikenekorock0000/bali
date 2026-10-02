#pragma once
// 直近の出来事をメモリに残し、Web 画面に表示する。
#include <Arduino.h>
#include <ArduinoJson.h>
#include <time.h>

class EventLog {
 public:
  void add(const String& msg) {
    Entry& e = entries_[(head_ + count_) % N];
    if (count_ == N) head_ = (head_ + 1) % N; else ++count_;
    e.epoch = time(nullptr);
    e.uptimeSec = millis() / 1000;
    strlcpy(e.msg, msg.c_str(), sizeof(e.msg));
    Serial.println(msg);
  }

  // 新しい順
  void toJson(JsonArray arr) const {
    for (int i = count_ - 1; i >= 0; --i) {
      const Entry& e = entries_[(head_ + i) % N];
      JsonObject o = arr.add<JsonObject>();
      o["epoch"] = static_cast<long>(e.epoch);
      o["uptime"] = e.uptimeSec;
      o["msg"] = e.msg;
    }
  }

 private:
  struct Entry {
    time_t epoch;
    uint32_t uptimeSec;
    char msg[96];
  };
  static constexpr int N = 40;
  Entry entries_[N];
  int head_ = 0;
  int count_ = 0;
};
