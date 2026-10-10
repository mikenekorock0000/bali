
#include "obd.h"
#include <driver/twai.h>

#include "config.h"
#include "obd_logic.h"

using namespace starter;

namespace {
const uint8_t kPids[] = {PID_RPM, PID_COOLANT, PID_SPEED, PID_RPM, PID_STATUS};
}

void Obd::begin() {
  digitalWrite(PIN_CAN_STBY, HIGH);  // 待機（基板の 10k でも HIGH に引いてある）
  pinMode(PIN_CAN_STBY, OUTPUT);
}

void Obd::setActive(bool on, uint32_t nowMs) {
  if (!OBD_ENABLED || on == active_) return;
  active_ = on;
  if (on) {
    twai_general_config_t g =
        TWAI_GENERAL_CONFIG_DEFAULT((gpio_num_t)PIN_CAN_TX, (gpio_num_t)PIN_CAN_RX, TWAI_MODE_NORMAL);
    g.rx_queue_len = 16;
    twai_timing_config_t t = TWAI_TIMING_CONFIG_500KBITS();
    // 応答 ID 0x7E8〜0x7EF だけを受け取る
    twai_filter_config_t f;
    f.acceptance_code = 0x7E8u << 21;
    f.acceptance_mask = ~(0x7F8u << 21);
    f.single_filter = true;
    driverUp_ = twai_driver_install(&g, &t, &f) == ESP_OK && twai_start() == ESP_OK;
    if (driverUp_) digitalWrite(PIN_CAN_STBY, LOW);
    lastTxMs_ = nowMs;
    rpm = speedKmh = coolantC = NAN;
    statusKnown = false;
  } else {
    digitalWrite(PIN_CAN_STBY, HIGH);
    if (driverUp_) {
      twai_stop();
      twai_driver_uninstall();
    }
    driverUp_ = false;
  }
}

void Obd::loop(uint32_t nowMs) {
  if (!active_ || !driverUp_) return;

  twai_message_t rx;
  while (twai_receive(&rx, 0) == ESP_OK) {
    if (rx.extd || rx.rtr) continue;
    uint8_t pid;
    float v;
    if (!obdParse(rx.identifier, rx.data, rx.data_length_code, pid, v)) continue;
    lastRxMs_ = nowMs;
    switch (pid) {
      case PID_RPM: rpm = v; break;
      case PID_SPEED: speedKmh = v; break;
      case PID_COOLANT: coolantC = v; break;
      case PID_STATUS:
        milOn = obdMilOn(v);
        dtcCount = obdDtcCount(v);
        statusKnown = true;
        break;
    }
  }

  if (nowMs - lastTxMs_ < OBD_POLL_MS) return;
  lastTxMs_ = nowMs;
  twai_message_t tx = {};
  tx.identifier = OBD_REQ_ID;
  tx.data_length_code = 8;
  obdRequest(kPids[next_], tx.data);
  next_ = (next_ + 1) % sizeof(kPids);
  twai_transmit(&tx, 0);  // 送れなければ次の周期に任せる

  // バスオフ（配線ミスなど）になったら車両に迷惑をかけないよう停止する
  twai_status_info_t st;
  if (twai_get_status_info(&st) == ESP_OK && st.state == TWAI_STATE_BUS_OFF) {
    setActive(false, nowMs);
  }
}
