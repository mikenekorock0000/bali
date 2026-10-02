#include <unity.h>

#include "beacon.h"
#include "presence.h"
#include "schedule.h"

using namespace starter;

void setUp() {}
void tearDown() {}

static struct tm makeTm(int wday, int hour, int min, int yday = 100) {
  struct tm t = {};
  t.tm_year = 2026 - 1900;
  t.tm_yday = yday;
  t.tm_wday = wday;
  t.tm_hour = hour;
  t.tm_min = min;
  return t;
}

// ---- schedule ----

void test_schedule_fires_in_window() {
  ScheduleEntry e{true, 0b0111110, 6, 50};  // 月〜金 6:50
  TEST_ASSERT_TRUE(scheduleDue(e, makeTm(1, 6, 50), 0));
  TEST_ASSERT_TRUE(scheduleDue(e, makeTm(1, 6, 52), 0));
  TEST_ASSERT_FALSE(scheduleDue(e, makeTm(1, 6, 53), 0));
  TEST_ASSERT_FALSE(scheduleDue(e, makeTm(1, 6, 49), 0));
}

void test_schedule_respects_days_and_enabled() {
  ScheduleEntry e{true, 0b0111110, 6, 50};
  TEST_ASSERT_FALSE(scheduleDue(e, makeTm(0, 6, 50), 0));  // 日曜
  TEST_ASSERT_FALSE(scheduleDue(e, makeTm(6, 6, 50), 0));  // 土曜
  e.enabled = false;
  TEST_ASSERT_FALSE(scheduleDue(e, makeTm(1, 6, 50), 0));
}

void test_schedule_fires_once_per_day() {
  ScheduleEntry e{true, 0x7F, 7, 0};
  struct tm t = makeTm(3, 7, 1, 200);
  TEST_ASSERT_TRUE(scheduleDue(e, t, 0));
  TEST_ASSERT_FALSE(scheduleDue(e, t, dayKey(t)));
  struct tm next = makeTm(4, 7, 0, 201);
  TEST_ASSERT_TRUE(scheduleDue(e, next, dayKey(t)));
}

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

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_schedule_fires_in_window);
  RUN_TEST(test_schedule_respects_days_and_enabled);
  RUN_TEST(test_schedule_fires_once_per_day);
  RUN_TEST(test_presence_no_left_before_first_arrival);
  RUN_TEST(test_presence_arrive_then_leave);
  RUN_TEST(test_presence_seen_after_update_timestamp_is_not_leave);
  RUN_TEST(test_presence_millis_wraparound);
  RUN_TEST(test_autolock_decision);
  RUN_TEST(test_parse_ibeacon);
  RUN_TEST(test_parse_mac_and_uuid);
  RUN_TEST(test_beacon_matching);
  return UNITY_END();
}
