// PC で動かすテスト: pio test -e native
#include <unity.h>

#include "layout.h"

using namespace rc;

static const std::vector<DeviceRef> R = {
    {"ac1", "リビングのエアコン", "Air Conditioner"},
    {"sp1", "スピーカー", "Speaker"},
    {"tv1", "テレビ", "TV"},
};
static const std::vector<DeviceRef> S = {{"sc1", "おやすみ", ""}, {"sc2", "外出", ""}};

void setUp() {}
void tearDown() {}

void test_no_pages_means_auto() {
  auto r = parseLayout("{}", R, S);
  TEST_ASSERT_FALSE(r.usePages);
  TEST_ASSERT_EQUAL(0, r.errors.size());
  r = parseLayout("", R, S);
  TEST_ASSERT_FALSE(r.usePages);
}

void test_bad_json() {
  auto r = parseLayout("{\"pages\": [", R, S);
  TEST_ASSERT_FALSE(r.usePages);
  TEST_ASSERT_EQUAL(1, r.errors.size());
}

void test_builtin_page_and_order() {
  auto r = parseLayout(R"({"pages":[{"remote":"テレビ"},{"remote":"リビングのエアコン","title":"エアコン"},{"scenes":true}]})", R, S);
  TEST_ASSERT_TRUE(r.usePages);
  TEST_ASSERT_EQUAL(3, r.pages.size());
  TEST_ASSERT_EQUAL(2, r.pages[0].remote);
  TEST_ASSERT_FALSE(r.pages[0].custom);
  TEST_ASSERT_EQUAL_STRING("エアコン", r.pages[1].title.c_str());
  TEST_ASSERT_TRUE(r.pages[2].scenes);
  TEST_ASSERT_EQUAL(0, r.errors.size());
}

void test_custom_speaker() {
  auto r = parseLayout(R"({"pages":[{"remote":"スピーカー","color":"#ff6b81",
    "dial":{"label":"音量","up":{"cmd":"volumeAdd"},"down":{"cmd":"volumeSub"}},
    "top":{"label":"入力","btn":"入力切替"},
    "center":{"cmd":"turnOn"},
    "bottom":{"label":"テレビ電源","remote":"テレビ","cmd":"turnOn"},
    "list":[{"btn":"BT"},{"label":"寝る","scene":"おやすみ"}]}]})", R, S);
  TEST_ASSERT_EQUAL(0, r.errors.size());
  const PageSpec& p = r.pages[0];
  TEST_ASSERT_TRUE(p.custom);
  TEST_ASSERT_TRUE(p.hasColor);
  TEST_ASSERT_EQUAL_HEX32(0xFF6B81, p.color);
  TEST_ASSERT_EQUAL_STRING("音量", p.dialLabel.c_str());
  TEST_ASSERT_EQUAL_STRING("volumeAdd", p.dialUp.cmd.command.c_str());
  TEST_ASSERT_EQUAL_STRING("sp1", p.dialUp.cmd.deviceId.c_str());
  TEST_ASSERT_TRUE(p.top.cmd.customize);
  TEST_ASSERT_EQUAL_STRING("入力切替", p.top.cmd.command.c_str());
  TEST_ASSERT_EQUAL_STRING("入力", p.top.label.c_str());
  TEST_ASSERT_EQUAL_STRING("turnOn", p.center.label.c_str());  // label 省略
  TEST_ASSERT_EQUAL_STRING("tv1", p.bottom.cmd.deviceId.c_str());
  TEST_ASSERT_EQUAL(2, p.list.size());
  TEST_ASSERT_EQUAL_STRING("BT", p.list[0].label.c_str());
  TEST_ASSERT_TRUE(p.list[1].cmd.scene);
  TEST_ASSERT_EQUAL_STRING("sc1", p.list[1].cmd.deviceId.c_str());
}

void test_page_without_remote() {
  auto r = parseLayout(R"({"pages":[{"title":"おでかけ","center":{"label":"全部OFF","scene":"外出"},
    "top":{"remote":"テレビ","cmd":"turnOff"}}]})", R, S);
  TEST_ASSERT_EQUAL(0, r.errors.size());
  TEST_ASSERT_EQUAL(-1, r.pages[0].remote);
  TEST_ASSERT_EQUAL_STRING("sc2", r.pages[0].center.cmd.deviceId.c_str());
  TEST_ASSERT_EQUAL_STRING("tv1", r.pages[0].top.cmd.deviceId.c_str());
}

void test_errors_skip_only_bad_parts() {
  auto r = parseLayout(R"({"pages":[
    {"remote":"ないリモコン"},
    {"remote":"テレビ","top":{"btn":"A","cmd":"B"},"list":[{"btn":"OK"},{"scene":"ない"}]},
    {"title":"x","center":{"cmd":"turnOn"}},
    {"title":"空"}]})", R, S);
  // ページ: ないリモコン ×、テレビ ○（top ×・list 1 つだけ）、x ○（center は送り先なし ×）、空 ×
  TEST_ASSERT_EQUAL(2, r.pages.size());
  TEST_ASSERT_FALSE(r.pages[0].top.valid);
  TEST_ASSERT_EQUAL(1, r.pages[0].list.size());
  TEST_ASSERT_FALSE(r.pages[1].center.valid);
  TEST_ASSERT_EQUAL(5, r.errors.size());
}

void test_param_and_color() {
  auto r = parseLayout(R"({"pages":[{"remote":"テレビ","top":{"label":"NHK","cmd":"SetChannel","param":"1"}}]})", R, S);
  TEST_ASSERT_EQUAL_STRING("1", r.pages[0].top.cmd.parameter.c_str());
  uint32_t c;
  TEST_ASSERT_FALSE(parseColor("red", c));
  TEST_ASSERT_TRUE(parseColor("#00ff0A", c));
  TEST_ASSERT_EQUAL_HEX32(0x00FF0A, c);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_no_pages_means_auto);
  RUN_TEST(test_bad_json);
  RUN_TEST(test_builtin_page_and_order);
  RUN_TEST(test_custom_speaker);
  RUN_TEST(test_page_without_remote);
  RUN_TEST(test_errors_skip_only_bad_parts);
  RUN_TEST(test_param_and_color);
  return UNITY_END();
}
