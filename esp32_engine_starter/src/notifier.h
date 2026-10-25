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
  // 指示用トピックに届いた新しいメッセージを 1 件取り出す。添付ファイルがあれば url にその URL（なければ空）
  bool takeCommand(String& cmd, String& url);
  // ダッシュボード用の状態（JSON）を状態のトピックに送る。未送信の古い状態は新しいもので置き換える
  void publishState(const String& json) { state_ = json; }
  // 送っていない通知・状態がない
  bool idle() const { return count_ == 0 && state_.isEmpty(); }
  // 指示用トピックをすぐ読みに行く（loop() の次の回で）
  void pollSoon() { pollNow_ = true; }
  uint32_t pollCount() const { return polls_; }  // 指示用トピックを読めた回数
  uint32_t sentCount() const { return sent_; }   // 送れた通知・状態の数
  // スリープをまたいで「どこまで読んだか」を引き継ぐ（空ならまだ読んでいない）
  String since() const { return since_; }
  void resumeFrom(const String& since) {
    since_ = since;
    firstPoll_ = since_.isEmpty();
  }

 private:
  struct Msg {
    Prio prio;
    String title, body, tags;
  };

 public:
  // ntfy との通信の準備（証明書の確認・アクセストークン）。遠隔更新のダウンロードでも使う
  void addAuth(class HTTPClient& http);
  static void secure(class WiFiClientSecure& client);

 private:
  bool post(const Msg& m);
  bool postState(const String& json);
  void pollCommands();

  static constexpr int QUEUE = 8;
  Msg q_[QUEUE];
  int head_ = 0, count_ = 0;
  uint32_t nextTryMs_ = 0;
  uint32_t lastPollMs_ = 0;
  String since_;  // 最後に読んだメッセージ ID（空ならまだ 1 件も無い）
  bool firstPoll_ = true;
  bool pollNow_ = false;
  uint32_t polls_ = 0;
  uint32_t sent_ = 0;
  String state_;
  String cmds_[4];
  String urls_[4];
  int cmdCount_ = 0;
};
