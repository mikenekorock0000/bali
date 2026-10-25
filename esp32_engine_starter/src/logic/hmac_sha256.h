#pragma once
// SHA-256 と HMAC-SHA256（FIPS 180-4 / RFC 2104）。指示の署名の確認に使う。
// Arduino 非依存なので PC 上でテストでき、ダッシュボードの JavaScript 版と同じ結果になることを確かめている。
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

namespace starter {

class Sha256 {
 public:
  Sha256() { reset(); }
  void reset() {
    static const uint32_t init[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                     0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memcpy(h_, init, sizeof(h_));
    len_ = 0;
    used_ = 0;
  }
  void update(const uint8_t* p, size_t n) {
    len_ += n;
    while (n--) {
      buf_[used_++] = *p++;
      if (used_ == 64) {
        block(buf_);
        used_ = 0;
      }
    }
  }
  void update(const char* s) { update(reinterpret_cast<const uint8_t*>(s), strlen(s)); }
  void finish(uint8_t out[32]) {
    uint64_t bits = len_ * 8;
    uint8_t pad = 0x80;
    update(&pad, 1);
    uint8_t zero = 0;
    while (used_ != 56) update(&zero, 1);
    uint8_t l[8];
    for (int i = 0; i < 8; ++i) l[i] = static_cast<uint8_t>(bits >> (56 - 8 * i));
    update(l, 8);
    for (int i = 0; i < 8; ++i) {
      out[4 * i] = h_[i] >> 24;
      out[4 * i + 1] = h_[i] >> 16;
      out[4 * i + 2] = h_[i] >> 8;
      out[4 * i + 3] = h_[i];
    }
  }

 private:
  static uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
  void block(const uint8_t* b) {
    static const uint32_t k[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
    uint32_t w[64];
    for (int i = 0; i < 16; ++i) {
      w[i] = (uint32_t)b[4 * i] << 24 | (uint32_t)b[4 * i + 1] << 16 | (uint32_t)b[4 * i + 2] << 8 | b[4 * i + 3];
    }
    for (int i = 16; i < 64; ++i) {
      uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = h_[0], bb = h_[1], c = h_[2], d = h_[3], e = h_[4], f = h_[5], g = h_[6], h = h_[7];
    for (int i = 0; i < 64; ++i) {
      uint32_t t1 = h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k[i] + w[i];
      uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & bb) ^ (a & c) ^ (bb & c));
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = bb;
      bb = a;
      a = t1 + t2;
    }
    h_[0] += a;
    h_[1] += bb;
    h_[2] += c;
    h_[3] += d;
    h_[4] += e;
    h_[5] += f;
    h_[6] += g;
    h_[7] += h;
  }

  uint32_t h_[8];
  uint8_t buf_[64];
  uint64_t len_;
  size_t used_;
};

inline void hmacSha256(const uint8_t* key, size_t keyLen, const uint8_t* msg, size_t msgLen, uint8_t out[32]) {
  uint8_t k[64] = {0};
  if (keyLen > 64) {
    Sha256 s;
    s.update(key, keyLen);
    s.finish(k);
  } else {
    memcpy(k, key, keyLen);
  }
  uint8_t ipad[64], opad[64];
  for (int i = 0; i < 64; ++i) {
    ipad[i] = k[i] ^ 0x36;
    opad[i] = k[i] ^ 0x5c;
  }
  uint8_t inner[32];
  Sha256 s;
  s.update(ipad, 64);
  s.update(msg, msgLen);
  s.finish(inner);
  s.reset();
  s.update(opad, 64);
  s.update(inner, 32);
  s.finish(out);
}

inline void toHex(const uint8_t* p, size_t n, char* out) {
  static const char* d = "0123456789abcdef";
  for (size_t i = 0; i < n; ++i) {
    out[2 * i] = d[p[i] >> 4];
    out[2 * i + 1] = d[p[i] & 15];
  }
  out[2 * n] = '\0';
}

// ---- 指示の署名 ----
// 書式："sig1 <時刻(UNIX 秒)> <署名(32 桁の 16 進)> <指示>"
// 署名 = HMAC-SHA256(鍵の文字列, "<時刻> <指示>") の先頭 16 バイト
struct SignedCommand {
  uint32_t ts = 0;
  char sig[33] = {0};
  const char* cmd = nullptr;  // 元の文字列の中を指す
};

// "sig1 " で始まる行を分解する。書式が違えば false
inline bool parseSigned(const char* line, SignedCommand& out) {
  if (strncmp(line, "sig1 ", 5) != 0) return false;
  const char* p = line + 5;
  uint32_t ts = 0;
  int digits = 0;
  while (*p >= '0' && *p <= '9' && digits < 11) {
    ts = ts * 10 + (*p - '0');
    ++p;
    ++digits;
  }
  if (digits == 0 || *p != ' ') return false;
  ++p;
  for (int i = 0; i < 32; ++i) {
    char c = p[i];
    bool hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
    if (!hex) return false;
    out.sig[i] = c;
  }
  out.sig[32] = '\0';
  if (p[32] != ' ' || p[33] == '\0') return false;
  out.ts = ts;
  out.cmd = p + 33;
  return true;
}

inline void signCommand(const char* key, uint32_t ts, const char* cmd, char out[33]) {
  char msg[160];
  int n = snprintf(msg, sizeof(msg), "%lu %s", (unsigned long)ts, cmd);
  if (n < 0) n = 0;
  if (n >= (int)sizeof(msg)) n = sizeof(msg) - 1;
  uint8_t mac[32];
  hmacSha256(reinterpret_cast<const uint8_t*>(key), strlen(key), reinterpret_cast<const uint8_t*>(msg), n, mac);
  toHex(mac, 16, out);
}

enum class SigVerdict : uint8_t { Ok, BadSignature, Replayed, TooOld, FromFuture };

// lastTs：最後に受け付けた指示の時刻（同じ・古い時刻は使い回しとみなす）。
// nowTs が 0（時計が未設定）のときは、時刻の範囲は見ずに使い回しだけ防ぐ
inline SigVerdict verifyCommand(const char* key, const SignedCommand& c, uint32_t nowTs, uint32_t lastTs,
                                uint32_t maxAgeSec, uint32_t maxFutureSec) {
  char expect[33];
  signCommand(key, c.ts, c.cmd, expect);
  uint8_t diff = 0;  // 比較にかかる時間を一定にする
  for (int i = 0; i < 32; ++i) diff |= static_cast<uint8_t>(expect[i] ^ c.sig[i]);
  if (diff) return SigVerdict::BadSignature;
  if (c.ts <= lastTs) return SigVerdict::Replayed;
  if (nowTs) {
    if (c.ts + maxAgeSec < nowTs) return SigVerdict::TooOld;
    if (c.ts > nowTs + maxFutureSec) return SigVerdict::FromFuture;
  }
  return SigVerdict::Ok;
}

}  // namespace starter
