#include <math.h>
#include <unity.h>

#include "beacon.h"
#include "presence.h"
#include "battery_health.h"
#include "cooldown.h"
#include "debounce.h"
#include "nmea.h"
#include "obd_logic.h"
#include "park_sleep.h"
#include "history.h"
#include "settings_rules.h"
#include "hmac_sha256.h"
#include "maintenance.h"
#include <string>

using namespace starter;

void setUp() {}
void tearDown() {}

// ---- presence ----

static PresenceConfig cfg() {
  PresenceConfig c;
  c.nearRssi = -70;
  c.farRssi = -90;
  c.absentTimeoutMs = 10000;
  return c;
}

void test_presence_no_left_before_first_arrival() {
  PresenceTracker p(cfg());
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(0));
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(60000));
  p.onSeen(-85, 61000);  // 弱い受信だけでは到着にしない
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(61000));
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(120000));
  TEST_ASSERT_EQUAL(PresenceState::Unknown, p.state());
}

void test_presence_arrive_then_leave() {
  PresenceTracker p(cfg());
  p.onSeen(-60, 1000);
  TEST_ASSERT_EQUAL(PresenceEvent::Arrived, p.update(1000));
  // 弱いが圏内の受信が続く間は離脱しない
  p.onSeen(-88, 9000);
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(15000));
  // 圏外の受信は在席扱いにしない
  p.onSeen(-95, 16000);
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(19000));
  TEST_ASSERT_EQUAL(PresenceEvent::Left, p.update(19001));
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(30000));
  TEST_ASSERT_EQUAL(PresenceState::Absent, p.state());
  p.onSeen(-65, 31000);
  TEST_ASSERT_EQUAL(PresenceEvent::Arrived, p.update(31000));
}

void test_presence_seen_after_update_timestamp_is_not_leave() {
  PresenceTracker p(cfg());
  p.onSeen(-60, 5000);
  p.update(5000);
  p.onSeen(-60, 5100);  // update より新しい時刻（減算が負になるケース）
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(5050));
}

void test_presence_millis_wraparound() {
  PresenceTracker p(cfg());
  p.onSeen(-60, 0xFFFFF000u);
  p.update(0xFFFFF000u);
  TEST_ASSERT_EQUAL(PresenceEvent::None, p.update(0x00000100u));
  TEST_ASSERT_EQUAL(PresenceEvent::Left, p.update(0x00002000u + 10000));
}

void test_autolock_decision() {
  AutoLockInputs in{true, false, false, false};
  TEST_ASSERT_EQUAL(AutoLockDecision::Lock, decideAutoLock(PresenceEvent::Left, in));
  TEST_ASSERT_EQUAL(AutoLockDecision::NoEvent, decideAutoLock(PresenceEvent::Arrived, in));
  in.engineRunning = true;
  TEST_ASSERT_EQUAL(AutoLockDecision::EngineRunning, decideAutoLock(PresenceEvent::Left, in));
  in.lockWhileRunning = true;
  TEST_ASSERT_EQUAL(AutoLockDecision::Lock, decideAutoLock(PresenceEvent::Left, in));
  in.lowVoltage = true;
  TEST_ASSERT_EQUAL(AutoLockDecision::LowVoltage, decideAutoLock(PresenceEvent::Left, in));
  in.enabled = false;
  TEST_ASSERT_EQUAL(AutoLockDecision::Disabled, decideAutoLock(PresenceEvent::Left, in));
}

// ---- beacon ----

void test_parse_ibeacon() {
  uint8_t d[25] = {0x4C, 0x00, 0x02, 0x15, 0xE2, 0xC5, 0x6D, 0xB5, 0xDF, 0xFB, 0x48, 0xD2, 0xB0,
                   0x60, 0xD0, 0xF5, 0xA7, 0x10, 0x96, 0xE0, 0x00, 0x01, 0x00, 0x02, 0xC5};
  IBeacon ib;
  TEST_ASSERT_TRUE(parseIBeacon(d, sizeof(d), ib));
  TEST_ASSERT_EQUAL_UINT16(1, ib.major);
  TEST_ASSERT_EQUAL_UINT16(2, ib.minor);
  TEST_ASSERT_EQUAL_INT8(-59, ib.txPower);
  char s[37];
  formatUuid(ib.uuid, s);
  TEST_ASSERT_EQUAL_STRING("e2c56db5-dffb-48d2-b060-d0f5a71096e0", s);
  d[2] = 0x01;
  TEST_ASSERT_FALSE(parseIBeacon(d, sizeof(d), ib));
}

void test_parse_mac_and_uuid() {
  uint8_t mac[6];
  TEST_ASSERT_TRUE(parseMac("AA:bb:0C:dd:ee:01", mac));
  TEST_ASSERT_EQUAL_HEX8(0xAA, mac[0]);
  TEST_ASSERT_EQUAL_HEX8(0x01, mac[5]);
  TEST_ASSERT_FALSE(parseMac("aa:bb:cc:dd:ee", mac));
  TEST_ASSERT_FALSE(parseMac("aa:bb:cc:dd:ee:fg", mac));
  uint8_t u[16];
  TEST_ASSERT_TRUE(parseUuid("e2c56db5-dffb-48d2-b060-d0f5a71096e0", u));
  TEST_ASSERT_FALSE(parseUuid("e2c56db5-dffb-48d2-b060-d0f5a71096e", u));
}

void test_beacon_matching() {
  uint8_t mac[6] = {1, 2, 3, 4, 5, 6};
  BeaconRule byMac;
  parseMac("01:02:03:04:05:06", byMac.mac);
  TEST_ASSERT_TRUE(beaconMatches(byMac, mac, nullptr));
  mac[5] = 7;
  TEST_ASSERT_FALSE(beaconMatches(byMac, mac, nullptr));

  BeaconRule byId;
  byId.type = BeaconRule::IBeaconId;
  parseUuid("e2c56db5-dffb-48d2-b060-d0f5a71096e0", byId.uuid);
  IBeacon ib;
  memcpy(ib.uuid, byId.uuid, 16);
  ib.major = 1;
  ib.minor = 2;
  TEST_ASSERT_TRUE(beaconMatches(byId, mac, &ib));
  TEST_ASSERT_FALSE(beaconMatches(byId, mac, nullptr));
  byId.minor = 3;
  TEST_ASSERT_FALSE(beaconMatches(byId, mac, &ib));
  byId.minor = 2;
  byId.major = 1;
  TEST_ASSERT_TRUE(beaconMatches(byId, mac, &ib));
}

// ---- beacon rule ----

void test_parse_beacon_rule() {
  BeaconRule r;
  TEST_ASSERT_TRUE(parseBeaconRule("AA:BB:CC:DD:EE:01", r));
  TEST_ASSERT_EQUAL(BeaconRule::Mac, r.type);
  TEST_ASSERT_EQUAL_HEX8(0x01, r.mac[5]);
  TEST_ASSERT_TRUE(parseBeaconRule("uuid:e2c56db5-dffb-48d2-b060-d0f5a71096e0:1:2", r));
  TEST_ASSERT_EQUAL(BeaconRule::IBeaconId, r.type);
  TEST_ASSERT_EQUAL(1, r.major);
  TEST_ASSERT_EQUAL(2, r.minor);
  TEST_ASSERT_TRUE(parseBeaconRule("uuid:e2c56db5-dffb-48d2-b060-d0f5a71096e0", r));
  TEST_ASSERT_EQUAL(-1, r.major);
  TEST_ASSERT_EQUAL(-1, r.minor);
  TEST_ASSERT_FALSE(parseBeaconRule("uuid:zz", r));
  TEST_ASSERT_FALSE(parseBeaconRule("aa:bb", r));
}

// ---- debounce ----

void test_debounce() {
  Debouncer d(50);
  TEST_ASSERT_FALSE(d.update(false, 0));
  TEST_ASSERT_FALSE(d.update(true, 10));   // 変化直後は確定しない
  TEST_ASSERT_FALSE(d.update(false, 30));  // チャタリング
  TEST_ASSERT_FALSE(d.update(true, 40));
  TEST_ASSERT_FALSE(d.update(true, 80));
  TEST_ASSERT_TRUE(d.update(true, 90));    // 40ms から 50ms 続いた
  TEST_ASSERT_TRUE(d.state());
  TEST_ASSERT_EQUAL(90u, d.changedAt());
  TEST_ASSERT_FALSE(d.update(true, 200));
}

// ---- cooldown ----

void test_cooldown() {
  Cooldown<4> c;
  TEST_ASSERT_TRUE(c.allow(1, 1000, 5000));
  TEST_ASSERT_FALSE(c.allow(1, 3000, 5000));
  TEST_ASSERT_TRUE(c.allow(2, 3000, 5000));  // 別の種類は独立
  TEST_ASSERT_TRUE(c.allow(1, 6000, 5000));
  c.reset(1);
  TEST_ASSERT_TRUE(c.allow(1, 6001, 5000));
  TEST_ASSERT_FALSE(c.allow(9, 0, 0));
}

// ---- nmea ----

void test_nmea_rmc() {
  GpsFix g;
  // 東京駅付近、時速 10 ノット
  const char* ok = "$GPRMC,123519.00,A,3540.8100,N,13945.9900,E,10.0,84.4,020126,,,A*5C";
  TEST_ASSERT_TRUE(nmeaChecksumOk(ok));
  TEST_ASSERT_TRUE(parseRmc(ok, g));
  TEST_ASSERT_TRUE(g.valid);
  TEST_ASSERT_TRUE(fabs(g.lat - 35.6801667) < 1e-5);
  TEST_ASSERT_TRUE(fabs(g.lon - 139.7665) < 1e-5);
  TEST_ASSERT_TRUE(fabs(g.speedKmh - 18.52f) < 0.01f);
  TEST_ASSERT_EQUAL(12, g.hh);
  TEST_ASSERT_EQUAL(2026, g.year);
  TEST_ASSERT_EQUAL(1, g.month);

  const char* bad = "$GPRMC,123519.00,A,3540.8100,N,13945.9900,E,10.0,84.4,020126,,,A*5D";
  TEST_ASSERT_FALSE(parseRmc(bad, g));

  const char* nofix = "$GNRMC,000001.00,V,,,,,,,010126,,,N*66";
  TEST_ASSERT_TRUE(nmeaChecksumOk(nofix));
  TEST_ASSERT_TRUE(parseRmc(nofix, g));
  TEST_ASSERT_FALSE(g.valid);

  TEST_ASSERT_FALSE(parseRmc("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47", g));
}

void test_haversine() {
  // 東京駅 → 新宿駅 ≒ 6.1km
  double d = haversineM(35.681236, 139.767125, 35.689592, 139.700413);
  TEST_ASSERT_TRUE(d > 6000 && d < 6200);
}

// ---- obd ----

void test_obd_request_and_parse() {
  uint8_t req[8];
  obdRequest(PID_RPM, req);
  TEST_ASSERT_EQUAL_HEX8(0x02, req[0]);
  TEST_ASSERT_EQUAL_HEX8(0x01, req[1]);
  TEST_ASSERT_EQUAL_HEX8(0x0C, req[2]);

  uint8_t pid;
  float v;
  uint8_t rpm[8] = {0x04, 0x41, 0x0C, 0x1A, 0xF8, 0, 0, 0};  // 0x1AF8/4 = 1726
  TEST_ASSERT_TRUE(obdParse(0x7E8, rpm, 8, pid, v));
  TEST_ASSERT_EQUAL_HEX8(PID_RPM, pid);
  TEST_ASSERT_TRUE(fabs(v - 1726.0f) < 0.01f);

  uint8_t cool[8] = {0x03, 0x41, 0x05, 0x7B, 0, 0, 0, 0};  // 123-40 = 83
  TEST_ASSERT_TRUE(obdParse(0x7E9, cool, 8, pid, v));
  TEST_ASSERT_TRUE(fabs(v - 83.0f) < 0.01f);

  uint8_t st[8] = {0x06, 0x41, 0x01, 0x82, 0x07, 0xE5, 0x00, 0};  // MIL ON、DTC 2 件
  TEST_ASSERT_TRUE(obdParse(0x7E8, st, 8, pid, v));
  TEST_ASSERT_TRUE(obdMilOn(v));
  TEST_ASSERT_EQUAL(2, obdDtcCount(v));

  TEST_ASSERT_FALSE(obdParse(0x123, rpm, 8, pid, v));    // 応答 ID ではない
  uint8_t neg[8] = {0x03, 0x7F, 0x01, 0x12, 0, 0, 0, 0};  // 否定応答
  TEST_ASSERT_FALSE(obdParse(0x7E8, neg, 8, pid, v));
}

// ---- battery health ----

void test_crank_monitor() {
  CrankMonitor m(5000);
  TEST_ASSERT_FALSE(m.feed(12.5f, 0));  // 未開始
  m.start(1000);
  TEST_ASSERT_FALSE(m.feed(12.4f, 1100));
  TEST_ASSERT_FALSE(m.feed(9.8f, 1500));
  TEST_ASSERT_FALSE(m.feed(13.9f, 3000));
  TEST_ASSERT_TRUE(m.feed(14.0f, 6000));
  TEST_ASSERT_TRUE(fabs(m.minVolts() - 9.8f) < 0.001f);
  TEST_ASSERT_FALSE(m.active());
  m.start(10000);
  m.feed(10.5f, 10100);
  TEST_ASSERT_TRUE(m.finish());
  TEST_ASSERT_TRUE(fabs(m.minVolts() - 10.5f) < 0.001f);
  TEST_ASSERT_FALSE(m.finish());
}

void test_charge_check() {
  ChargeCheck c(13.0f, 60000);
  TEST_ASSERT_FALSE(c.update(false, 12.0f, 0));
  TEST_ASSERT_FALSE(c.update(true, 12.6f, 1000));
  TEST_ASSERT_FALSE(c.update(true, 12.6f, 60000));
  TEST_ASSERT_TRUE(c.update(true, 12.6f, 61000));
  TEST_ASSERT_FALSE(c.update(true, 12.6f, 120000));  // 1 回だけ
  TEST_ASSERT_FALSE(c.update(false, 12.6f, 130000)); // エンジン停止でリセット
  TEST_ASSERT_FALSE(c.update(true, 14.2f, 140000));  // 正常に充電
  TEST_ASSERT_FALSE(c.update(true, 14.2f, 300000));
}

void test_park_sleep_timer() {
  ParkSleepTimer t(600000);
  ParkInputs in{true, false, false, true, false, false};
  TEST_ASSERT_FALSE(t.update(in, 1000));
  TEST_ASSERT_FALSE(t.update(in, 600999));
  TEST_ASSERT_TRUE(t.update(in, 601000));
  // 条件が崩れたら数え直す
  in.doorOpen = true;
  TEST_ASSERT_FALSE(t.update(in, 602000));
  in.doorOpen = false;
  TEST_ASSERT_FALSE(t.update(in, 603000));
  TEST_ASSERT_TRUE(t.update(in, 1203000));
  // どれか 1 つでも満たさなければ眠らない
  ParkInputs base{true, false, false, true, false, false};
  ParkInputs v[] = {base, base, base, base, base};
  v[0].enabled = false;
  v[1].acc = true;
  v[2].engineRunning = true;
  v[3].keyAbsent = false;
  v[4].busy = true;
  for (auto& x : v) {
    ParkSleepTimer u(1000);
    u.update(x, 0);
    TEST_ASSERT_FALSE(u.update(x, 100000));
  }
  // millis() の桁あふれをまたいでも数えられる
  ParkSleepTimer w(1000);
  TEST_ASSERT_FALSE(w.update(base, 0xFFFFFF00u));
  TEST_ASSERT_TRUE(w.update(base, 0x00000400u));
}

void test_door_wake_verdict() {
  TEST_ASSERT_EQUAL(DoorWakeVerdict::Owner, judgeDoorWake(true, false, 1000, 15000));
  TEST_ASSERT_EQUAL(DoorWakeVerdict::Owner, judgeDoorWake(false, true, 1000, 15000));
  TEST_ASSERT_EQUAL(DoorWakeVerdict::Waiting, judgeDoorWake(false, false, 14999, 15000));
  TEST_ASSERT_EQUAL(DoorWakeVerdict::Intrusion, judgeDoorWake(false, false, 15000, 15000));
}

void test_presence_assume_absent() {
  PresenceTracker p;
  p.assumeAbsent();
  TEST_ASSERT_EQUAL(PresenceState::Absent, p.state());
  p.onSeen(-60, 100);
  TEST_ASSERT_EQUAL(PresenceEvent::Arrived, p.update(100));
  p.assumeAbsent();  // 在のときは変えない
  TEST_ASSERT_EQUAL(PresenceState::Present, p.state());
}

void test_history_ring() {
  History<4> h;
  TEST_ASSERT_TRUE(h.sane());
  TEST_ASSERT_TRUE(h.maybeAdd(1000, 12.34f, 21.5f, 900));
  TEST_ASSERT_FALSE(h.maybeAdd(1500, 12.0f, 20.0f, 900));  // 間隔が短い
  TEST_ASSERT_TRUE(h.maybeAdd(1900, 12.0f, NAN, 900));
  TEST_ASSERT_EQUAL(2, h.size());
  TEST_ASSERT_EQUAL(1234, h.at(0).cv);
  TEST_ASSERT_EQUAL(215, h.at(0).temp10);
  TEST_ASSERT_EQUAL(TEMP_NONE, h.at(1).temp10);
  for (uint32_t t = 2800; t <= 5500; t += 900) h.maybeAdd(t, 11.0f, -3.25f, 900);
  TEST_ASSERT_EQUAL(4, h.size());  // 一杯になったら古いものから消える
  TEST_ASSERT_EQUAL(2800, h.at(0).t);
  TEST_ASSERT_EQUAL(5500, h.at(3).t);
  TEST_ASSERT_EQUAL(-33, h.at(3).temp10);
  TEST_ASSERT_TRUE(h.maybeAdd(10, 12.0f, 0, 900));  // 時計が戻ったら記録する
  TEST_ASSERT_EQUAL(10, h.at(3).t);
}

void test_settings_rules() {
  TEST_ASSERT_TRUE(validSsid("car"));
  TEST_ASSERT_FALSE(validSsid(""));
  TEST_ASSERT_FALSE(validSsid("123456789012345678901234567890123"));
  TEST_ASSERT_TRUE(validWifiPass(""));
  TEST_ASSERT_FALSE(validWifiPass("short"));
  TEST_ASSERT_TRUE(validWifiPass("12345678"));
  TEST_ASSERT_TRUE(validTopic("hijet-AbC_123456"));
  TEST_ASSERT_FALSE(validTopic("hijet"));          // 短すぎる
  TEST_ASSERT_FALSE(validTopic("hijet topic 1234"));  // 空白
  TEST_ASSERT_FALSE(validTopic("hijet/aaaaaaaaaa"));
  TEST_ASSERT_TRUE(validServer("https://ntfy.sh"));
  TEST_ASSERT_FALSE(validServer("https://ntfy.sh/"));
  TEST_ASSERT_FALSE(validServer("ntfy.sh"));
  TEST_ASSERT_TRUE(validPin("1234"));
  TEST_ASSERT_FALSE(validPin("12a4"));
  TEST_ASSERT_FALSE(validPin("123"));
  TEST_ASSERT_TRUE(validOtaPass("change-me"));
  TEST_ASSERT_FALSE(validOtaPass("short"));
  TEST_ASSERT_TRUE(validCal(1.0f));
  TEST_ASSERT_FALSE(validCal(1.5f));
}

static std::string shaHex(const std::string& m) {
  Sha256 s;
  s.update(reinterpret_cast<const uint8_t*>(m.data()), m.size());
  uint8_t o[32];
  s.finish(o);
  char h[65];
  toHex(o, 32, h);
  return h;
}

void test_sha256_vectors() {
  TEST_ASSERT_EQUAL_STRING("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", shaHex("abc").c_str());
  TEST_ASSERT_EQUAL_STRING("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
                           shaHex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").c_str());
  TEST_ASSERT_EQUAL_STRING("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
                           shaHex(std::string(1000000, 'a')).c_str());
  uint8_t mac[32];
  char h[65];
  const char* m = "what do ya want for nothing?";
  hmacSha256((const uint8_t*)"Jefe", 4, (const uint8_t*)m, strlen(m), mac);
  toHex(mac, 32, h);
  TEST_ASSERT_EQUAL_STRING("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", h);
  std::string longKey(100, 'k');
  hmacSha256((const uint8_t*)longKey.data(), longKey.size(), (const uint8_t*)"msg", 3, mac);
  toHex(mac, 32, h);
  TEST_ASSERT_EQUAL_STRING("bd56a1782c2830e8abc6ed866a57a1230661e650b84c62f7ee3accc5fa5af491", h);
}

void test_signed_command() {
  const char* key = "0123456789abcdef0123456789abcdef";
  char sig[33];
  signCommand(key, 1792836000u, "lock", sig);
  TEST_ASSERT_EQUAL_STRING("af7be9b8d27cf545076722e2949f3068", sig);
  SignedCommand c;
  TEST_ASSERT_TRUE(parseSigned("sig1 1792836000 af7be9b8d27cf545076722e2949f3068 lock", c));
  TEST_ASSERT_EQUAL(1792836000u, c.ts);
  TEST_ASSERT_EQUAL_STRING("lock", c.cmd);
  TEST_ASSERT_EQUAL(SigVerdict::Ok, verifyCommand(key, c, 1792836100u, 0, 1800, 300));
  TEST_ASSERT_EQUAL(SigVerdict::Replayed, verifyCommand(key, c, 1792836100u, 1792836000u, 1800, 300));
  TEST_ASSERT_EQUAL(SigVerdict::TooOld, verifyCommand(key, c, 1792836000u + 1801, 0, 1800, 300));
  TEST_ASSERT_EQUAL(SigVerdict::FromFuture, verifyCommand(key, c, 1792836000u - 301, 0, 1800, 300));
  TEST_ASSERT_EQUAL(SigVerdict::Ok, verifyCommand(key, c, 0, 0, 1800, 300));  // 時計が未設定
  TEST_ASSERT_EQUAL(SigVerdict::BadSignature, verifyCommand("other-key-xxxxxxxxxxxxxxxxxxxxxxx", c, 1792836100u, 0, 1800, 300));
  // 指示を書き換えると署名が合わない
  SignedCommand d;
  TEST_ASSERT_TRUE(parseSigned("sig1 1792836000 af7be9b8d27cf545076722e2949f3068 alarm off", d));
  TEST_ASSERT_EQUAL(SigVerdict::BadSignature, verifyCommand(key, d, 1792836100u, 0, 1800, 300));
  // 書式の誤り
  TEST_ASSERT_FALSE(parseSigned("1234 lock", c));
  TEST_ASSERT_FALSE(parseSigned("sig1 1792836000 AF7BE9B8D27CF545076722E2949F3068 lock", c));  // 大文字
  TEST_ASSERT_FALSE(parseSigned("sig1 1792836000 af7be9b8 lock", c));
  TEST_ASSERT_FALSE(parseSigned("sig1 x af7be9b8d27cf545076722e2949f3068 lock", c));
  TEST_ASSERT_FALSE(parseSigned("sig1 1792836000 af7be9b8d27cf545076722e2949f3068 ", c));
}

void test_maintenance() {
  TEST_ASSERT_EQUAL(0, daysFromCivil(1970, 1, 1));
  TEST_ASSERT_EQUAL(20958, daysFromCivil(2027, 5, 20));
  TEST_ASSERT_EQUAL(11017, daysFromCivil(2000, 3, 1));
  MaintItem a, b, c;
  TEST_ASSERT_TRUE(parseMaintLine("車検 2027-05-20", a));
  TEST_ASSERT_TRUE(a.byDate);
  TEST_ASSERT_EQUAL_STRING("車検", a.name);
  TEST_ASSERT_TRUE(parseMaintLine("タイヤ 交換 45000km", b));
  TEST_ASSERT_FALSE(b.byDate);
  TEST_ASSERT_EQUAL(45000, b.km);
  TEST_ASSERT_EQUAL_STRING("タイヤ 交換", b.name);
  TEST_ASSERT_FALSE(parseMaintLine("車検", c));
  TEST_ASSERT_FALSE(parseMaintLine("車検 2027-13-01", c));
  TEST_ASSERT_FALSE(parseMaintLine("車検 45000", c));
  TEST_ASSERT_FALSE(parseMaintLine(" 2027-05-20", c));
  int32_t d = a.day;
  TEST_ASSERT_EQUAL(0, maintLevel(a, d - 31, 0, false));
  TEST_ASSERT_EQUAL(1, maintLevel(a, d - 30, 0, false));
  TEST_ASSERT_EQUAL(2, maintLevel(a, d - 7, 0, false));
  TEST_ASSERT_EQUAL(3, maintLevel(a, d - 1, 0, false));
  TEST_ASSERT_EQUAL(4, maintLevel(a, d, 0, false));
  TEST_ASSERT_EQUAL(4, maintLevel(a, d + 10, 0, false));
  TEST_ASSERT_EQUAL(0, maintLevel(b, 0, 44000, false));  // メーターの値が不明
  TEST_ASSERT_EQUAL(0, maintLevel(b, 0, 44499, true));
  TEST_ASSERT_EQUAL(1, maintLevel(b, 0, 44500, true));
  TEST_ASSERT_EQUAL(2, maintLevel(b, 0, 44900, true));
  TEST_ASSERT_EQUAL(4, maintLevel(b, 0, 45000, true));
}




int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_presence_no_left_before_first_arrival);
  RUN_TEST(test_presence_arrive_then_leave);
  RUN_TEST(test_presence_seen_after_update_timestamp_is_not_leave);
  RUN_TEST(test_presence_millis_wraparound);
  RUN_TEST(test_autolock_decision);
  RUN_TEST(test_parse_ibeacon);
  RUN_TEST(test_parse_mac_and_uuid);
  RUN_TEST(test_beacon_matching);
  RUN_TEST(test_parse_beacon_rule);
  RUN_TEST(test_debounce);
  RUN_TEST(test_cooldown);
  RUN_TEST(test_nmea_rmc);
  RUN_TEST(test_haversine);
  RUN_TEST(test_obd_request_and_parse);
  RUN_TEST(test_crank_monitor);
  RUN_TEST(test_charge_check);
  RUN_TEST(test_park_sleep_timer);
  RUN_TEST(test_door_wake_verdict);
  RUN_TEST(test_presence_assume_absent);
  RUN_TEST(test_history_ring);
  RUN_TEST(test_settings_rules);
  RUN_TEST(test_sha256_vectors);
  RUN_TEST(test_signed_command);
  RUN_TEST(test_maintenance);
  return UNITY_END();
}
