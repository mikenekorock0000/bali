"""各データ源を一定間隔で取得し、最後に成功した値を保持する。

取得に失敗しても前回の値で描画を続け、失敗中の項目は画面下部に表示する。
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable

log = logging.getLogger(__name__)

RETRY_AFTER_FAILURE = 60  # 秒


@dataclass
class Source:
    label: str
    fetch: Callable[[], Any]
    ttl: float
    value: Any = None
    ok: bool = False
    error: str = ""
    updated_at: float = 0.0
    next_at: float = 0.0


@dataclass
class DeviceStatus:
    battery: int | None = None
    charging: bool = False
    seen_at: float = 0.0


class DataStore:
    def __init__(self, clock: Callable[[], float] = time.time):
        self.sources: dict[str, Source] = {}
        self.device = DeviceStatus()
        self._clock = clock
        self._lock = threading.Lock()

    def add(self, name: str, label: str, fetch: Callable[[], Any], ttl: float) -> None:
        self.sources[name] = Source(label, fetch, ttl)

    def refresh_due(self) -> None:
        """期限の来たデータ源を取得し直す。"""
        for name, src in self.sources.items():
            now = self._clock()
            if now < src.next_at:
                continue
            try:
                value = src.fetch()
            except Exception as e:  # noqa: BLE001 - どの失敗でも前回値で描画を続ける
                log.warning("%s の取得に失敗: %s", src.label, e)
                with self._lock:
                    src.ok, src.error = False, str(e)
                    src.next_at = now + min(src.ttl, RETRY_AFTER_FAILURE)
                continue
            with self._lock:
                src.value, src.ok, src.error = value, True, ""
                src.updated_at = now
                src.next_at = now + src.ttl

    def get(self, name: str) -> Any:
        with self._lock:
            return self.sources[name].value

    def failing_labels(self) -> list[str]:
        with self._lock:
            return [s.label for s in self.sources.values() if s.next_at and not s.ok]

    def set_device(self, battery: int | None, charging: bool) -> None:
        with self._lock:
            self.device = DeviceStatus(battery, charging, self._clock())

    def status(self) -> dict:
        with self._lock:
            return {
                "sources": {
                    name: {"ok": s.ok, "error": s.error, "updated_at": s.updated_at}
                    for name, s in self.sources.items()
                },
                "device": {"battery": self.device.battery, "charging": self.device.charging,
                           "seen_at": self.device.seen_at},
            }

    def run_forever(self, interval: float = 5) -> threading.Thread:
        def loop():
            while True:
                self.refresh_due()
                time.sleep(interval)

        thread = threading.Thread(target=loop, name="data-refresh", daemon=True)
        thread.start()
        return thread
