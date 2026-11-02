// PC で動かすテスト: pio test -e native
#include <unity.h>

#include "remote_core.h"

using namespace rc;

void setUp() {}
void tearDown() {}

void test_kind_mapping() {
  TEST_ASSERT(kindFromRemoteType("Air Conditioner") == Kind::AirCon);
  TEST_ASSERT(kindFromRemoteType("TV") == Kind::TV);
  TEST_ASSERT(kindFromRemoteType("Set Top Box") == Kind::TV);
  TEST_ASSERT(kindFromRemoteType("Speaker") == Kind::Media);
  TEST_ASSERT(kindFromRemoteType("Light") == Kind::Light);
  TEST_ASSERT(kindFromRemoteType("Fan") == Kind::Fan);
  TEST_ASSERT(kindFromRemoteType("DIY Air Conditioner") == Kind::Generic);
  TEST_ASSERT(kindFromRemoteType("Others") == Kind::Generic);
  TEST_ASSERT(kindFromRemoteType("Projector") == Kind::Generic);
}

void test_ac_temp_clamps() {
  AcState s;
  s.temp = 29;
  TEST_ASSERT_TRUE(s.addTemp(1));
  TEST_ASSERT_EQUAL(30, s.temp);
  TEST_ASSERT_FALSE(s.addTemp(1));
  TEST_ASSERT_EQUAL(30, s.temp);
  s.addTemp(-100);
  TEST_ASSERT_EQUAL(16, s.temp);
}

void test_ac_parameter() {
  AcState s;
  s.temp = 27; s.mode = 5; s.fan = 3; s.power = true;
  TEST_ASSERT_EQUAL_STRING("27,5,3,on", s.toParameter().c_str());
  s.power = false;
  TEST_ASSERT_EQUAL_STRING("27,5,3,off", s.toParameter().c_str());
}

void test_ac_mode_cycle() {
  AcState s;  // 冷房から
  s.nextMode(); TEST_ASSERT_EQUAL(5, s.mode);  // 暖房
  s.nextMode(); TEST_ASSERT_EQUAL(3, s.mode);  // 除湿
  s.nextMode(); TEST_ASSERT_EQUAL(4, s.mode);  // 送風
  s.nextMode(); TEST_ASSERT_EQUAL(1, s.mode);  // 自動
  s.nextMode(); TEST_ASSERT_EQUAL(2, s.mode);  // 冷房
  s.mode = 0;   // 想定外の値でも止まらない
  s.nextMode(); TEST_ASSERT_EQUAL(2, s.mode);
}

void test_ac_fan_cycle() {
  AcState s;
  s.nextFan(); s.nextFan(); s.nextFan();
  TEST_ASSERT_EQUAL(4, s.fan);
  s.nextFan();
  TEST_ASSERT_EQUAL(1, s.fan);
}

void test_ac_pack_roundtrip() {
  AcState s;
  s.temp = 18; s.mode = 3; s.fan = 4; s.power = true;
  AcState r = AcState::unpack(s.pack());
  TEST_ASSERT_EQUAL(18, r.temp);
  TEST_ASSERT_EQUAL(3, r.mode);
  TEST_ASSERT_EQUAL(4, r.fan);
  TEST_ASSERT_TRUE(r.power);
  AcState d = AcState::unpack(0);  // 未保存
  TEST_ASSERT_EQUAL(26, d.temp);
  TEST_ASSERT_FALSE(d.power);
}

void test_command_json() {
  Command c{"02-ABC", "setAll", "26,2,1,on"};
  TEST_ASSERT_EQUAL_STRING(
      "{\"command\":\"setAll\",\"parameter\":\"26,2,1,on\",\"commandType\":\"command\"}",
      commandJson(c).c_str());
  Command k{"02-ABC", "常夜灯 \"小\""};
  k.customize = true;
  TEST_ASSERT_EQUAL_STRING(
      "{\"command\":\"常夜灯 \\\"小\\\"\",\"parameter\":\"default\",\"commandType\":\"customize\"}",
      commandJson(k).c_str());
}

void test_generic_items() {
  auto a = genericItems("id1", "DIY Light", {"常夜灯"});
  TEST_ASSERT_EQUAL(3, a.size());
  TEST_ASSERT_EQUAL_STRING("turnOn", a[0].cmd.command.c_str());
  TEST_ASSERT_TRUE(a[2].cmd.customize);
  auto b = genericItems("id2", "Others", {"A", "B"});
  TEST_ASSERT_EQUAL(2, b.size());
  TEST_ASSERT_EQUAL_STRING("A", b[0].label.c_str());
}

void test_debouncer() {
  Debouncer d(800);
  TEST_ASSERT_FALSE(d.due(1000));
  d.touch(1000);
  TEST_ASSERT_FALSE(d.due(1500));
  d.touch(1500);  // まだ回している
  TEST_ASSERT_FALSE(d.due(2000));
  TEST_ASSERT_TRUE(d.due(2300));
  TEST_ASSERT_FALSE(d.due(5000));  // 1 回だけ
}

void test_idle_timer() {
  IdleTimer t(20000, 60000);
  t.activity(0);
  TEST_ASSERT(t.state(1000) == Backlight::On);
  TEST_ASSERT(t.state(25000) == Backlight::Dim);
  TEST_ASSERT(t.state(70000) == Backlight::Off);
  TEST_ASSERT_TRUE(t.activity(70000));   // 消灯中の操作は起こすだけ
  TEST_ASSERT_FALSE(t.activity(71000));
  TEST_ASSERT(t.state(72000) == Backlight::On);
}

void test_zone_and_wrap() {
  TEST_ASSERT(zoneOf(10) == Zone::Top);
  TEST_ASSERT(zoneOf(120) == Zone::Center);
  TEST_ASSERT(zoneOf(230) == Zone::Bottom);
  TEST_ASSERT_EQUAL(4, wrapIndex(-1, 5));
  TEST_ASSERT_EQUAL(0, wrapIndex(5, 5));
  TEST_ASSERT_EQUAL(0, wrapIndex(3, 0));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_kind_mapping);
  RUN_TEST(test_ac_temp_clamps);
  RUN_TEST(test_ac_parameter);
  RUN_TEST(test_ac_mode_cycle);
  RUN_TEST(test_ac_fan_cycle);
  RUN_TEST(test_ac_pack_roundtrip);
  RUN_TEST(test_command_json);
  RUN_TEST(test_generic_items);
  RUN_TEST(test_debouncer);
  RUN_TEST(test_idle_timer);
  RUN_TEST(test_zone_and_wrap);
  return UNITY_END();
}
