from __future__ import annotations

import threading
import time
from concurrent.futures import ThreadPoolExecutor

from rentivo.cache.ttl_store import TTLStore


def _store(ttl: int = 60, max_entries: int = 64, **kw) -> TTLStore:
    """Build a store with the cleanup thread disabled by default — tests drive
    expiry through the injected timer instead."""
    kw.setdefault("enable_cleanup_thread", False)
    return TTLStore(ttl_seconds=ttl, max_entries=max_entries, thread_name="TTLStore-test", **kw)


def test_set_get_round_trips_the_same_object(value):
    store = _store()
    assert store.get("k") is None
    store.set("k", value)
    assert store.get("k") is value  # stored as-is, no serialisation


def test_get_many_returns_only_present_keys():
    store = _store()
    store.set_many({"a": "alpha", "b": "beta"})
    assert store.get_many(["a", "c"]) == {"a": "alpha"}


def test_get_many_with_empty_input_returns_empty_dict():
    store = _store()
    store.set("a", "alpha")
    assert store.get_many([]) == {}


def test_set_many_with_empty_input_is_a_no_op():
    store = _store()
    store.set_many({})
    assert store.get_many(["a"]) == {}


def test_clear_empties_the_store(value):
    store = _store()
    store.set("k", value)
    store.clear()
    assert store.get("k") is None


def test_entries_expire_under_a_controllable_timer(value):
    clock = {"t": 1000.0}
    store = _store(ttl=10, timer=lambda: clock["t"])
    store.set("k", value)
    assert store.get("k") is value

    clock["t"] += 5
    assert store.get("k") is value  # still fresh

    clock["t"] += 10  # past the TTL
    assert store.get("k") is None
    assert store.get_many(["k"]) == {}


def test_max_entries_evicts_the_oldest_entry():
    store = _store(max_entries=2)
    store.set_many({"a": "alpha", "b": "beta", "c": "gamma"})
    result = store.get_many(["a", "b", "c"])
    assert "a" not in result  # evicted to make room for "c"
    assert result == {"b": "beta", "c": "gamma"}


def test_thread_safe_under_concurrent_access():
    """Smoke test: many threads reading + writing must not raise."""
    store = _store()

    def worker(i: int) -> None:
        key = f"k{i % 8}"
        store.set_many({key: f"v{i}"})
        store.get_many([key])
        store.set(key, f"v{i}")
        store.get(key)

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(worker, range(200)))


def test_cleanup_thread_starts_as_a_named_daemon_and_close_joins_it():
    store = TTLStore(
        ttl_seconds=60,
        max_entries=10,
        thread_name="TTLStore-test",
        enable_cleanup_thread=True,
        cleanup_interval_seconds=60,  # large; it must not fire during the test
    )
    thread = store._cleanup_thread
    assert thread is not None
    assert thread.is_alive()
    assert thread.daemon is True
    assert thread.name == "TTLStore-test"

    store.close()

    thread.join(timeout=2.0)
    assert not thread.is_alive()
    assert store._cleanup_thread is None
    assert store._stop_event is None


def test_close_without_a_cleanup_thread_is_a_no_op():
    _store().close()  # must not raise


def test_effective_cleanup_interval_is_a_ttl_quarter_floored_at_one_second():
    assert TTLStore._effective_cleanup_interval(60, None) == 15.0
    assert TTLStore._effective_cleanup_interval(2, None) == 1.0  # floor at 1.0
    assert TTLStore._effective_cleanup_interval(60, 5.0) == 5.0


def test_cleanup_thread_expires_entries_without_a_concurrent_read():
    """The daemon must remove entries whose TTL has elapsed even when nobody
    reads the store."""
    now = [1_000.0]
    store = TTLStore(
        ttl_seconds=1,
        max_entries=10,
        thread_name="TTLStore-test",
        timer=lambda: now[0],
        enable_cleanup_thread=True,
        cleanup_interval_seconds=0.05,
    )
    try:
        store.set("a", "alpha")
        now[0] += 10  # past the TTL
        for _ in range(40):  # up to ~2s wall clock
            with store._lock:
                if "a" not in store._cache:
                    break
            time.sleep(0.05)
        with store._lock:
            assert "a" not in store._cache
    finally:
        store.close()


def test_cleanup_loop_body_runs_synchronously():
    """Drive ``_cleanup_loop`` from the main thread so coverage observes the
    loop body. Python 3.14's ``sys.monitoring`` (the default coverage core)
    does not trace background threads, so the daemon-based test above is not
    enough to cover it."""
    now = [1_000.0]
    store = _store(ttl=1, timer=lambda: now[0])
    store.set("a", "alpha")
    now[0] += 10  # past the TTL

    # Manually wire the loop's contract: a stop event plus a tiny interval.
    store._stop_event = threading.Event()
    timer = threading.Timer(0.05, store._stop_event.set)  # stop after one wait cycle
    timer.start()
    try:
        store._cleanup_loop(0.01)
    finally:
        timer.cancel()

    with store._lock:
        assert "a" not in store._cache
