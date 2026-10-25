#include "notifier.h"

#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "ca_roots.h"
#include "config.h"
#include "settings.h"

void Notifier::begin() {}

// サーバーの証明書を、入れてあるルート証明書で確かめる（設定で「確かめない」にしたときだけ省く）
void Notifier::secure(WiFiClientSecure& client) {
  if (settings.tlsInsecure) {
    client.setInsecure();
  } else {
    client.setCACert(CA_ROOTS);
  }
}

void Notifier::send(Prio prio, const String& title, const String& body, const char* tags) {
  Serial.printf("[notify %d] %s: %s\n", (int)prio, title.c_str(), body.c_str());
  if (count_ == QUEUE) {  // 一杯なら一番古いものを捨てる
    head_ = (head_ + 1) % QUEUE;
    --count_;
  }
  q_[(head_ + count_) % QUEUE] = Msg{prio, title, body, String(tags)};
  ++count_;
}

bool Notifier::post(const Msg& m) {
  // 日本語のタイトルは HTTP ヘッダーに直接入れられないので、ntfy の JSON 形式で
  // サーバーのルート（"https://ntfy.sh/"）に送る。
  JsonDocument doc;
  doc["topic"] = settings.topic;
  doc["title"] = m.title;
  doc["message"] = m.body;
  doc["priority"] = (int)m.prio;
  if (m.tags.length()) doc["tags"].add(m.tags);
  String payload;
  serializeJson(doc, payload);

  WiFiClientSecure client;
  secure(client);
  HTTPClient http;
  http.setTimeout(8000);
  if (!http.begin(client, settings.ntfyServer + "/")) return false;
  http.addHeader("Content-Type", "application/json");
  addAuth(http);
  int code = http.POST(payload);
  http.end();
  return code >= 200 && code < 300;
}

void Notifier::addAuth(HTTPClient& http) {
  if (settings.token.length()) http.addHeader("Authorization", "Bearer " + settings.token);
}

bool Notifier::postState(const String& json) {
  // 状態は JSON をそのまま本文にする。スマホの通知にならないよう優先度は最低
  WiFiClientSecure client;
  secure(client);
  HTTPClient http;
  http.setTimeout(8000);
  if (!http.begin(client, settings.ntfyServer + "/" + settings.stateTopic)) return false;
  http.addHeader("Title", "state");
  http.addHeader("Priority", "1");
  addAuth(http);
  int code = http.POST(json);
  http.end();
  Serial.printf("[state] 送信 %d\n", code);
  return code >= 200 && code < 300;
}

void Notifier::pollCommands() {
  WiFiClientSecure client;
  secure(client);
  HTTPClient http;
  http.setTimeout(8000);
  // 最初の取得は起動前に届いていた指示を読み飛ばすためだけに使う（実行しない）
  String url = settings.ntfyServer + "/" + settings.cmdTopic + "/json?poll=1&since=" + (since_.isEmpty() ? "all" : since_);
  if (!http.begin(client, url)) return;
  addAuth(http);
  int code = http.GET();
  if (code == 200) {
    String body = http.getString();
    // 1 行に 1 件の JSON
    int start = 0;
    while (start < (int)body.length()) {
      int nl = body.indexOf('\n', start);
      if (nl < 0) nl = body.length();
      JsonDocument doc;
      if (!deserializeJson(doc, body.substring(start, nl)) && doc["event"] == "message") {
        since_ = doc["id"].as<String>();
        if (!firstPoll_ && cmdCount_ < 4) {
          urls_[cmdCount_] = doc["attachment"]["url"] | "";
          cmds_[cmdCount_++] = doc["message"].as<String>();
        }
      }
      start = nl + 1;
    }
    firstPoll_ = false;
    ++polls_;
  }
  http.end();
}

void Notifier::loop(uint32_t nowMs) {
  if (WiFi.status() != WL_CONNECTED || !settings.configured()) return;
  if (count_ > 0 && static_cast<int32_t>(nowMs - nextTryMs_) >= 0) {
    if (post(q_[head_])) {
      ++sent_;
      head_ = (head_ + 1) % QUEUE;
      --count_;
      nextTryMs_ = nowMs + 500;
    } else {
      nextTryMs_ = nowMs + 30000;  // 失敗したら 30 秒後に再送
    }
    return;  // 1 回の loop で通信は 1 つだけ
  }
  if (state_.length() && static_cast<int32_t>(nowMs - nextTryMs_) >= 0) {
    if (postState(state_)) {
      ++sent_;
      state_ = "";
      nextTryMs_ = nowMs + 500;
    } else {
      nextTryMs_ = nowMs + 30000;
    }
    return;
  }
  if (pollNow_ || nowMs - lastPollMs_ >= CMD_POLL_MS) {
    pollNow_ = false;
    lastPollMs_ = nowMs;
    pollCommands();
  }
}

bool Notifier::takeCommand(String& cmd, String& url) {
  if (cmdCount_ == 0) return false;
  cmd = cmds_[0];
  url = urls_[0];
  for (int i = 1; i < cmdCount_; ++i) {
    cmds_[i - 1] = cmds_[i];
    urls_[i - 1] = urls_[i];
  }
  --cmdCount_;
  return true;
}
