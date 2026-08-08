from __future__ import annotations

from typing import Any, Callable

from rentivo.cache.ttl_store import TTLStore


class MemoryCache:
    """Process-local TTL cache, backed by a :class:`TTLStore`.

    Values are stored as-is (no serialisation).
    """

    def __init__(
        self,
        ttl_seconds: int,
        max_entries: int,
        *,
        timer: Callable[[], float] | None = None,
        enable_cleanup_thread: bool = True,
        cleanup_interval_seconds: float | None = None,
    ) -> None:
        self._store = TTLStore(
            ttl_seconds=ttl_seconds,
            max_entries=max_entries,
            thread_name="MemoryCache-cleanup",
            timer=timer,
            enable_cleanup_thread=enable_cleanup_thread,
            cleanup_interval_seconds=cleanup_interval_seconds,
        )

    def get(self, key: str) -> Any | None:
        return self._store.get(key)

    def set(self, key: str, value: Any) -> None:
        self._store.set(key, value)

    def clear(self) -> None:
        self._store.clear()

    def close(self) -> None:
        self._store.close()
