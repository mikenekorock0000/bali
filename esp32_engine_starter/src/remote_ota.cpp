#include "remote_ota.h"

#include <HTTPClient.h>
#include <Update.h>
#include <WiFiClientSecure.h>
#include <esp_task_wdt.h>

#include "logic/hmac_sha256.h"
#include "notifier.h"
#include "settings.h"

using starter::Sha256;
using starter::toHex;

bool remoteOtaUpdate(Notifier& notifier, const String& url, const String& sha256Hex, String& err) {
  // 自分の ntfy サーバーの添付だけを受け付ける
  if (!url.startsWith(settings.ntfyServer + "/")) {
    err = "添付の場所が ntfy のサーバーと違います";
    return false;
  }
  if (sha256Hex.length() != 64) {
    err = "SHA-256 の値がありません";
    return false;
  }
  WiFiClientSecure client;
  Notifier::secure(client);
  HTTPClient http;
  http.setTimeout(15000);
  if (!http.begin(client, url)) {
    err = "接続できません";
    return false;
  }
  notifier.addAuth(http);
  int code = http.GET();
  if (code != 200) {
    err = "ダウンロードできません（HTTP " + String(code) + "）。添付の期限（3 時間）が切れたかもしれません";
    http.end();
    return false;
  }
  int size = http.getSize();
  if (size <= 0 || !Update.begin(size)) {
    err = "書き込み先の領域が足りません（" + String(size) + " バイト）";
    http.end();
    return false;
  }
  WiFiClient* stream = http.getStreamPtr();
  Sha256 sha;
  uint8_t buf[2048];
  int left = size;
  uint32_t lastData = millis();
  bool first = true;
  while (left > 0) {
    esp_task_wdt_reset();
    size_t avail = stream->available();
    if (!avail) {
      if (!http.connected() || millis() - lastData > 20000) break;
      delay(5);
      continue;
    }
    int n = stream->readBytes(buf, min((int)avail, min((int)sizeof(buf), left)));
    if (n <= 0) continue;
    if (first && buf[0] != 0xE9) {  // ESP32 のファームウェアは 0xE9 で始まる
      err = "ファームウェアのファイルではありません";
      Update.abort();
      http.end();
      return false;
    }
    first = false;
    sha.update(buf, n);
    if (Update.write(buf, n) != (size_t)n) {
      err = "書き込みに失敗しました";
      Update.abort();
      http.end();
      return false;
    }
    left -= n;
    lastData = millis();
  }
  http.end();
  if (left > 0) {
    err = "ダウンロードが途中で止まりました";
    Update.abort();
    return false;
  }
  uint8_t digest[32];
  sha.finish(digest);
  char hex[65];
  toHex(digest, 32, hex);
  hex[64] = 0;
  if (!sha256Hex.equalsIgnoreCase(hex)) {
    err = "ファイルの中身が指示の値と合いません（壊れているか、差し替えられています）";
    Update.abort();
    return false;
  }
  if (!Update.end(true)) {
    err = "書き込みの仕上げに失敗しました";
    return false;
  }
  return true;
}
