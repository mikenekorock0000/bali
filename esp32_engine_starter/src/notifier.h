#pragma once
// ntfy への通知（キュー付き、Wi-Fi が切れていても後で送る）と、指示用トピックの読み取り。
#include <Arduino.h>

enum class Prio : uint8_t { Min = 1, Low = 2, Default = 3, High = 4, Urgent = 5 };

class Notifier {
 public:
  void begin();
  // title・本文は UTF-8。tags は ntfy の絵文字タグ（例 "warning"）
  void send(Prio prio, const String& title, const String& body, const char* tags = "");
  void loop(uint32_t nowMs);
  // 指示用トピックに届いた新しいメッセージを 1 件取り出す
  bool takeCommand(String& cmd);

 private:
  struct Msg {
    Prio prio;
    String title, body, tags;
  };
  bool post(const Msg& m);
  void pollCommands();

  static constexpr int QUEUE = 8;
  Msg q_[QUEUE];
  int head_ = 0, count_ = 0;
  uint32_t nextTryMs_ = 0;
  uint32_t lastPollMs_ = 0;
  String since_;  // 最後に読んだメッセージ ID（空ならまだ 1 件も無い）
  bool firstPoll_ = true;
  String cmds_[4];
  int cmdCount_ = 0;
};
