#include "ble_presence.h"

#include <NimBLEDevice.h>

using namespace starter;

namespace {

class ScanCallbacks : public NimBLEAdvertisedDeviceCallbacks {
 public:
  explicit ScanCallbacks(BlePresence* owner) : owner_(owner) {}

  void onResult(NimBLEAdvertisedDevice* dev) override {
    // NimBLE の getNative() は逆順（LSB 先頭）なので表示順に並べ替える
    const uint8_t* le = dev->getAddress().getNative();
    uint8_t mac[6];
    for (int i = 0; i < 6; ++i) mac[i] = le[5 - i];
    std::string name = dev->haveName() ? dev->getName() : std::string();
    std::string mfg = dev->haveManufacturerData() ? dev->getManufacturerData() : std::string();
    owner_->onAdvert(mac, name.c_str(), dev->getRSSI(), reinterpret_cast<const uint8_t*>(mfg.data()),
                     mfg.size());
  }

 private:
  BlePresence* owner_;
};

}  // namespace

void BlePresence::begin() {
  NimBLEDevice::init("");
  NimBLEScan* scan = NimBLEDevice::getScan();
  scan->setAdvertisedDeviceCallbacks(new ScanCallbacks(this), true /* 重複も通知 */);
  scan->setActiveScan(false);
  scan->setInterval(100);
  scan->setWindow(50);  // デューティ 50%（消費電流と検出の速さの折り合い）
  scan->setMaxResults(0);  // 結果を溜めない（メモリ節約）
  setEnabled(true);
}

void BlePresence::setRules(const BeaconRule* rules, int n) {
  portENTER_CRITICAL(&mux_);
  ruleCount_ = n > MAX_BEACONS ? MAX_BEACONS : n;
  for (int i = 0; i < ruleCount_; ++i) rules_[i] = rules[i];
  pending_ = false;
  portEXIT_CRITICAL(&mux_);
}

void BlePresence::setEnabled(bool on) {
  if (on == enabled_) return;
  enabled_ = on;
  NimBLEScan* scan = NimBLEDevice::getScan();
  if (on) {
    scan->start(0, nullptr, false);
  } else {
    scan->stop();
  }
}

void BlePresence::loop() {
  // 何らかの理由でスキャンが止まっていたら再開する
  if (enabled_ && !NimBLEDevice::getScan()->isScanning()) {
    NimBLEDevice::getScan()->start(0, nullptr, false);
  }
}

bool BlePresence::takeMatch(int& rssi) {
  portENTER_CRITICAL(&mux_);
  bool had = pending_;
  rssi = pendingRssi_;
  pending_ = false;
  pendingRssi_ = -127;
  portEXIT_CRITICAL(&mux_);
  return had;
}

void BlePresence::onAdvert(const uint8_t mac[6], const char* name, int rssi, const uint8_t* mfg,
                           size_t mfgLen) {
  IBeacon ib;
  bool isIb = parseIBeacon(mfg, mfgLen, ib);
  uint32_t now = millis();

  portENTER_CRITICAL(&mux_);
  for (int i = 0; i < ruleCount_; ++i) {
    if (beaconMatches(rules_[i], mac, isIb ? &ib : nullptr)) {
      if (!pending_ || rssi > pendingRssi_) pendingRssi_ = rssi;
      pending_ = true;
      break;
    }
  }

  // 一覧の更新：同じ MAC を上書き、なければ一番古い枠を使う
  int slot = 0;
  for (int i = 0; i < NEARBY_MAX; ++i) {
    if (memcmp(nearby_[i].mac, mac, 6) == 0) {
      slot = i;
      break;
    }
    if (nearby_[i].seenMs < nearby_[slot].seenMs) slot = i;
  }
  Nearby& n = nearby_[slot];
  if (memcmp(n.mac, mac, 6) != 0) n.name[0] = '\0';
  memcpy(n.mac, mac, 6);
  if (name[0]) strlcpy(n.name, name, sizeof(n.name));
  n.rssi = static_cast<int8_t>(rssi);
  n.seenMs = now;
  n.isIBeacon = isIb;
  if (isIb) n.ib = ib;
  portEXIT_CRITICAL(&mux_);
}

void BlePresence::nearbyToJson(JsonArray arr, uint32_t nowMs) const {
  Nearby copy[NEARBY_MAX];
  portENTER_CRITICAL(&mux_);
  memcpy(copy, nearby_, sizeof(copy));
  portEXIT_CRITICAL(&mux_);

  for (const Nearby& n : copy) {
    if (n.seenMs == 0 || nowMs - n.seenMs > 60000) continue;
    JsonObject o = arr.add<JsonObject>();
    char m[18];
    snprintf(m, sizeof(m), "%02x:%02x:%02x:%02x:%02x:%02x", n.mac[0], n.mac[1], n.mac[2], n.mac[3],
             n.mac[4], n.mac[5]);
    o["mac"] = m;
    o["name"] = n.name;
    o["rssi"] = n.rssi;
    o["agoSec"] = (nowMs - n.seenMs) / 1000;
    if (n.isIBeacon) {
      char u[37];
      formatUuid(n.ib.uuid, u);
      o["uuid"] = u;
      o["major"] = n.ib.major;
      o["minor"] = n.ib.minor;
    }
  }
}
