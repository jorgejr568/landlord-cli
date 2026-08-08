from __future__ import annotations

import threading
import time
from typing import Any, Callable

from cachetools import TTLCache


class TTLStore:
    """Thread-safe, process-local TTL store shared by the in-memory caches.

    Wraps ``cachetools.TTLCache`` with an ``RLock``: ``cachetools`` is not
    thread-safe, the web server is multi-threaded and KMS ``decrypt_many`` fans
    out via a thread pool. A daemon cleanup thread actively sweeps expired
    entries so memory does not grow between reads.

    Values are stored as-is; serialisation, if any, belongs to the caller.
    """

    def __init__(
        self,
        ttl_seconds: int,
        max_entries: int,
        *,
        thread_name: str,
        timer: Callable[[], float] | None = None,
        enable_cleanup_thread: bool = True,
        cleanup_interval_seconds: float | None = None,
    ) -> None:
        self._timer = timer or time.time
        self._lock = threading.RLock()
        self._cache: TTLCache[str, Any] = TTLCache(
            maxsize=max_entries,
            ttl=ttl_seconds,
            timer=self._timer,
        )
        self._stop_event: threading.Event | None = None
        self._cleanup_thread: threading.Thread | None = None

        if enable_cleanup_thread:
            interval = self._effective_cleanup_interval(ttl_seconds, cleanup_interval_seconds)
            self._stop_event = threading.Event()
            self._cleanup_thread = threading.Thread(
                target=self._cleanup_loop,
                args=(interval,),
                name=thread_name,
                daemon=True,
            )
            self._cleanup_thread.start()

    @staticmethod
    def _effective_cleanup_interval(ttl_seconds: int, override: float | None) -> float:
        if override is not None:
            return float(override)
        return max(1.0, ttl_seconds / 4.0)

    def _cleanup_loop(self, interval: float) -> None:
        stop = self._stop_event
        assert stop is not None
        while not stop.wait(interval):
            with self._lock:
                # cachetools TTLCache exposes ``expire()`` to drop everything
                # whose TTL has elapsed under the configured timer.
                self._cache.expire()

    def get(self, key: str) -> Any | None:
        with self._lock:
            return self._cache.get(key)

    def set(self, key: str, value: Any) -> None:
        with self._lock:
            self._cache[key] = value

    def get_many(self, keys: list[str]) -> dict[str, Any]:
        with self._lock:
            return {key: self._cache[key] for key in keys if key in self._cache}

    def set_many(self, items: dict[str, Any]) -> None:
        with self._lock:
            for key, value in items.items():
                self._cache[key] = value

    def clear(self) -> None:
        with self._lock:
            self._cache.clear()

    def close(self) -> None:
        if self._stop_event is not None:
            self._stop_event.set()
        if self._cleanup_thread is not None:
            self._cleanup_thread.join(timeout=2.0)
        self._stop_event = None
        self._cleanup_thread = None
