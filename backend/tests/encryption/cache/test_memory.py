from __future__ import annotations

from rentivo.encryption.cache.memory import MemoryDecryptCache


def _mk(ttl: int = 60, max_entries: int = 100, *, timer=None) -> MemoryDecryptCache:
    """Build a cache with the cleanup thread disabled — tests drive expiry
    via the injected timer."""
    return MemoryDecryptCache(
        ttl_seconds=ttl,
        max_entries=max_entries,
        timer=timer,
        enable_cleanup_thread=False,
    )


def test_get_many_returns_only_present_keys():
    cache = _mk()
    cache.set_many({"a": "alpha", "b": "beta"})
    assert cache.get_many(["a", "c"]) == {"a": "alpha"}


def test_close_is_a_no_op_without_cleanup_thread():
    cache = _mk()
    cache.close()  # must not raise


def test_entries_expire_after_ttl():
    """The ttl and timer arguments must reach the underlying store."""
    now = [1_000.0]

    def fake_timer() -> float:
        return now[0]

    cache = _mk(ttl=10, timer=fake_timer)
    cache.set_many({"a": "alpha"})
    assert cache.get_many(["a"]) == {"a": "alpha"}

    now[0] += 15
    assert cache.get_many(["a"]) == {}  # expired


def test_max_entries_bounds_residency():
    cache = _mk(max_entries=2)
    cache.set_many({"a": "alpha", "b": "beta", "c": "gamma"})
    # The oldest insert ("a") must have been evicted to make room for "c".
    assert cache.get_many(["a", "b", "c"]) == {"b": "beta", "c": "gamma"}


def test_cleanup_thread_starts_and_stops_under_its_own_name():
    cache = MemoryDecryptCache(
        ttl_seconds=60,
        max_entries=10,
        enable_cleanup_thread=True,
        cleanup_interval_seconds=60,  # large; we don't want it to fire during the test
    )
    thread = cache._store._cleanup_thread
    assert thread is not None
    assert thread.is_alive()
    assert thread.name == "MemoryDecryptCache-cleanup"
    cache.close()
    assert cache._store._cleanup_thread is None
