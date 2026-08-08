from __future__ import annotations

from rentivo.cache.memory import MemoryCache


def _cache(ttl=60, max_entries=64, **kw):
    return MemoryCache(ttl_seconds=ttl, max_entries=max_entries, enable_cleanup_thread=False, **kw)


def test_set_get_round_trips_same_object(value):
    cache = _cache()
    try:
        assert cache.get("k") is None
        cache.set("k", value)
        assert cache.get("k") is value  # in-memory stores as-is, no serialisation
    finally:
        cache.close()


def test_clear_empties_cache(value):
    cache = _cache()
    try:
        cache.set("k", value)
        cache.clear()
        assert cache.get("k") is None
    finally:
        cache.close()


def test_entries_expire_under_a_controllable_timer(value):
    """The ttl and timer arguments must reach the underlying store."""
    clock = {"t": 1000.0}
    cache = _cache(ttl=10, timer=lambda: clock["t"])
    try:
        cache.set("k", value)
        assert cache.get("k") is value
        clock["t"] += 11  # advance past the TTL
        assert cache.get("k") is None
    finally:
        cache.close()


def test_max_entries_evicts_oldest(value):
    cache = _cache(max_entries=2)
    try:
        cache.set("a", value)
        cache.set("b", value)
        cache.set("c", value)  # exceeds maxsize → evicts the oldest
        present = [k for k in ("a", "b", "c") if cache.get(k) is not None]
        assert len(present) == 2
    finally:
        cache.close()


def test_cleanup_thread_starts_and_stops_under_its_own_name():
    cache = MemoryCache(ttl_seconds=4, max_entries=8, enable_cleanup_thread=True)
    thread = cache._store._cleanup_thread
    assert thread is not None
    assert thread.is_alive()
    assert thread.name == "MemoryCache-cleanup"
    cache.close()
    assert cache._store._cleanup_thread is None
