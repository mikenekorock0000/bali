#pragma once
// BLE ビーコンの識別（固定 MAC アドレス または iBeacon の UUID/Major/Minor）。Arduino 非依存。
#include <ctype.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace starter {

struct IBeacon {
  uint8_t uuid[16];
  uint16_t major;
  uint16_t minor;
  int8_t txPower;
};

// Apple のメーカーデータ: 4C 00 02 15 <UUID 16> <Major 2> <Minor 2> <TxPower 1>
inline bool parseIBeacon(const uint8_t* d, size_t len, IBeacon& out) {
  if (len < 25 || d[0] != 0x4C || d[1] != 0x00 || d[2] != 0x02 || d[3] != 0x15) return false;
  memcpy(out.uuid, d + 4, 16);
  out.major = static_cast<uint16_t>((d[20] << 8) | d[21]);
  out.minor = static_cast<uint16_t>((d[22] << 8) | d[23]);
  out.txPower = static_cast<int8_t>(d[24]);
  return true;
}

inline int hexVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

// 区切り文字（- や :）を無視して 16 進を n バイト読む。桁数が合わなければ false。
inline bool parseHexBytes(const char* s, uint8_t* out, size_t n) {
  size_t got = 0;
  int hi = -1;
  for (; *s; ++s) {
    if (*s == '-' || *s == ':' || *s == ' ') continue;
    int v = hexVal(*s);
    if (v < 0) return false;
    if (hi < 0) {
      hi = v;
    } else {
      if (got >= n) return false;
      out[got++] = static_cast<uint8_t>((hi << 4) | v);
      hi = -1;
    }
  }
  return got == n && hi < 0;
}

inline bool parseUuid(const char* s, uint8_t out[16]) { return parseHexBytes(s, out, 16); }
inline bool parseMac(const char* s, uint8_t out[6]) { return parseHexBytes(s, out, 6); }

inline void formatUuid(const uint8_t u[16], char out[37]) {
  static const char* hex = "0123456789abcdef";
  size_t p = 0;
  for (int i = 0; i < 16; ++i) {
    if (i == 4 || i == 6 || i == 8 || i == 10) out[p++] = '-';
    out[p++] = hex[u[i] >> 4];
    out[p++] = hex[u[i] & 0xF];
  }
  out[p] = '\0';
}

struct BeaconRule {
  enum Type : uint8_t { Mac, IBeaconId } type = Mac;
  uint8_t mac[6] = {0};
  uint8_t uuid[16] = {0};
  int32_t major = -1;  // -1 はワイルドカード
  int32_t minor = -1;
};

// mac は表示順（aa:bb:...）の 6 バイト。ibeacon は解析済みなら非 null。
inline bool beaconMatches(const BeaconRule& r, const uint8_t mac[6], const IBeacon* ib) {
  if (r.type == BeaconRule::Mac) return memcmp(r.mac, mac, 6) == 0;
  if (!ib || memcmp(r.uuid, ib->uuid, 16) != 0) return false;
  if (r.major >= 0 && r.major != ib->major) return false;
  if (r.minor >= 0 && r.minor != ib->minor) return false;
  return true;
}

}  // namespace starter
