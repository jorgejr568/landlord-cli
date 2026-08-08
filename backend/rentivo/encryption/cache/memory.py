from __future__ import annotations

from typing import Callable

from rentivo.cache.ttl_store import TTLStore


class MemoryDecryptCache:
    """Process-local TTL cache for decrypted plaintexts, backed by a
    :class:`TTLStore`."""

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
            thread_name="MemoryDecryptCache-cleanup",
            timer=timer,
            enable_cleanup_thread=enable_cleanup_thread,
            cleanup_interval_seconds=cleanup_interval_seconds,
        )

    def get_many(self, keys: list[str]) -> dict[str, str]:
        return self._store.get_many(keys)

    def set_many(self, items: dict[str, str]) -> None:
        self._store.set_many(items)

    def close(self) -> None:
        self._store.close()
