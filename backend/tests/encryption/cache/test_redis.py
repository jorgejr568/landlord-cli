from __future__ import annotations

import hashlib
from unittest.mock import patch

import fakeredis
import pytest

from rentivo.encryption.cache.redis import RedisDecryptCache


def _client() -> fakeredis.FakeStrictRedis:
    # Mirror production: ``from_url`` builds the client with ``decode_responses=True``.
    return fakeredis.FakeStrictRedis(decode_responses=True)


def _hashed_key(ciphertext: str) -> str:
    """Re-derive the storage key independently of production code — the
    prefix and digest are a persisted contract."""
    return "rentivo:enc:dec:v1:" + hashlib.sha256(ciphertext.encode("utf-8")).hexdigest()


def test_keys_are_namespaced_and_hashed():
    client = _client()
    cache = RedisDecryptCache(client=client, ttl_seconds=60)
    cache.set_many({"enc:v1:AAAA": "alpha"})
    assert client.get(_hashed_key("enc:v1:AAAA")) == "alpha"  # stored verbatim, no codec


def test_get_many_returns_hits():
    cache = RedisDecryptCache(client=_client(), ttl_seconds=60)
    cache.set_many({"enc:v1:A": "alpha", "enc:v1:B": "beta"})
    assert cache.get_many(["enc:v1:A", "enc:v1:B"]) == {
        "enc:v1:A": "alpha",
        "enc:v1:B": "beta",
    }


def test_get_many_skips_misses():
    cache = RedisDecryptCache(client=_client(), ttl_seconds=60)
    cache.set_many({"enc:v1:A": "alpha"})
    assert cache.get_many(["enc:v1:A", "enc:v1:Z"]) == {"enc:v1:A": "alpha"}


def test_set_many_applies_ttl():
    client = _client()
    cache = RedisDecryptCache(client=client, ttl_seconds=42)
    cache.set_many({"enc:v1:A": "alpha"})
    ttl = client.ttl(_hashed_key("enc:v1:A"))
    assert 0 < ttl <= 42


def test_get_many_returns_empty_on_redis_failure():
    """A backend exception must degrade to a miss, not bubble up."""
    client = _client()
    cache = RedisDecryptCache(client=client, ttl_seconds=60)
    with patch.object(client, "mget", side_effect=ConnectionError("boom")):
        assert cache.get_many(["enc:v1:A"]) == {}


def test_close_calls_client_close():
    client = _client()
    cache = RedisDecryptCache(client=client, ttl_seconds=60)
    with patch.object(client, "close") as mock_close:
        cache.close()
        mock_close.assert_called_once_with()


def test_from_url_constructs_a_real_client():
    """Lazy-import smoke test: from_url must build a redis client without
    requiring a live server (we patch redis.from_url)."""
    with patch("redis.from_url") as mock_from_url:
        mock_from_url.return_value = _client()
        cache = RedisDecryptCache.from_url("redis://localhost:6379/0", ttl_seconds=60)
        mock_from_url.assert_called_once_with(
            "redis://localhost:6379/0",
            decode_responses=True,
        )
        assert isinstance(cache, RedisDecryptCache)


def test_from_url_raises_when_redis_missing():
    from rentivo.cache import redis_store

    with patch.object(redis_store, "redis", None):
        with pytest.raises(ImportError, match="redis is required for RedisDecryptCache"):
            RedisDecryptCache.from_url("redis://localhost:6379/0", ttl_seconds=60)
