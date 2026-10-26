#pragma once
// 設定画面で入力された値の書式チェック。Arduino 非依存なので PC 上でテストできる。
#include <ctype.h>
#include <string.h>

namespace starter {

// Wi-Fi の SSID：1〜32 バイト
inline bool validSsid(const char* s) {
  size_t n = strlen(s);
  return n >= 1 && n <= 32;
}

// Wi-Fi のパスワード：空（暗号化なし）か 8〜63 文字
inline bool validWifiPass(const char* s) {
  size_t n = strlen(s);
  return n == 0 || (n >= 8 && n <= 63);
}

// ntfy のトピック名：英数字・-・_ の 1〜64 文字。推測されにくいよう 12 文字以上を求める
inline bool validTopic(const char* s) {
  size_t n = strlen(s);
  if (n < 12 || n > 64) return false;
  for (size_t i = 0; i < n; ++i) {
    char c = s[i];
    if (!isalnum(static_cast<unsigned char>(c)) && c != '-' && c != '_') return false;
  }
  return true;
}

// ntfy のサーバー：https:// か http:// で始まり、末尾の / は付けない
inline bool validServer(const char* s) {
  size_t n = strlen(s);
  bool scheme = strncmp(s, "https://", 8) == 0 || strncmp(s, "http://", 7) == 0;
  return scheme && n > 8 && n < 100 && s[n - 1] != '/' && strchr(s, ' ') == nullptr;
}

// 暗証番号：数字 4〜8 桁
inline bool validPin(const char* s) {
  size_t n = strlen(s);
  if (n < 4 || n > 8) return false;
  for (size_t i = 0; i < n; ++i) {
    if (!isdigit(static_cast<unsigned char>(s[i]))) return false;
  }
  return true;
}

// OTA のパスワード：8〜32 文字
inline bool validOtaPass(const char* s) {
  size_t n = strlen(s);
  return n >= 8 && n <= 32;
}

// 電圧の補正係数：0.8〜1.2
inline bool validCal(float v) { return v >= 0.8f && v <= 1.2f; }

}  // namespace starter
