from __future__ import annotations

import hashlib
from unittest.mock import patch

import fakeredis
import pytest

from rentivo.cache import redis_store as redis_store_module
from rentivo.cache.redis_store import JSONCodec, RedisStore, StringCodec, redis_client_from_url

_PREFIX = "test:store:v1:"


def _client() -> fakeredis.FakeStrictRedis:
    # Mirror production: ``redis_client_from_url`` decodes responses.
    return fakeredis.FakeStrictRedis(decode_responses=True)


def _store(client=None, *, ttl_seconds: int = 60, codec=None) -> RedisStore:
    return RedisStore(
        client=client if client is not None else _client(),
        ttl_seconds=ttl_seconds,
        key_prefix=_PREFIX,
        codec=codec if codec is not None else StringCodec(),
        log_namespace="test_cache",
    )


class _Boom:
    """Client whose every operation fails."""

    def __getattr__(self, _name):
        def _raise(*_a, **_kw):
            raise ConnectionError("redis down")

        return _raise


def test_redis_key_is_the_prefix_plus_a_sha256_digest():
    key = "enc:v1:AAAA"
    assert _store().redis_key(key) == _PREFIX + hashlib.sha256(key.encode("utf-8")).hexdigest()


def test_set_many_then_get_many_round_trips():
    store = _store()
    store.set_many({"a": "alpha", "b": "beta"})
    assert store.get_many(["a", "b"]) == {"a": "alpha", "b": "beta"}


def test_get_many_skips_misses():
    store = _store()
    store.set_many({"a": "alpha"})
    assert store.get_many(["a", "z"]) == {"a": "alpha"}


def test_get_many_with_empty_input_never_touches_redis():
    assert _store(_Boom()).get_many([]) == {}


def test_get_many_is_fail_open_on_client_error():
    assert _store(_Boom()).get_many(["a"]) == {}


def test_get_many_skips_values_the_codec_cannot_decode():
    client = _client()
    store = _store(client, codec=JSONCodec())
    store.set_many({"good": {"n": 1}})
    client.set(store.redis_key("bad"), "{not-json")
    assert store.get_many(["good", "bad"]) == {"good": {"n": 1}}


def test_set_many_applies_the_ttl_to_every_key():
    client = _client()
    store = _store(client, ttl_seconds=42)
    store.set_many({"a": "alpha", "b": "beta"})
    assert client.ttl(store.redis_key("a")) == 42
    assert client.ttl(store.redis_key("b")) == 42


def test_set_many_with_empty_input_never_touches_redis():
    _store(_Boom()).set_many({})  # must not raise


def test_set_many_drops_values_the_codec_cannot_encode():
    store = _store(codec=JSONCodec())
    store.set_many({"bad": object(), "good": 1})
    assert store.get_many(["bad", "good"]) == {"good": 1}


def test_set_many_with_nothing_encodable_never_touches_redis():
    _store(_Boom(), codec=JSONCodec()).set_many({"bad": object()})  # must not raise


def test_set_many_is_fail_open_on_client_error():
    _store(_Boom()).set_many({"a": "alpha"})  # must not raise


def test_clear_removes_only_namespaced_keys():
    client = _client()
    client.set("unrelated", "keep-me")
    store = _store(client)
    store.set_many({"a": "alpha", "b": "beta"})

    store.clear()

    assert store.get_many(["a", "b"]) == {}
    assert client.get("unrelated") == "keep-me"


def test_clear_is_fail_open_on_client_error():
    _store(_Boom()).clear()  # must not raise


def test_close_closes_the_client():
    client = _client()
    with patch.object(client, "close") as mock_close:
        _store(client).close()
        mock_close.assert_called_once_with()


def test_close_is_fail_open_on_client_error():
    _store(_Boom()).close()  # must not raise


def test_client_from_url_builds_a_decoding_client():
    with patch("redis.from_url") as mock_from_url:
        mock_from_url.return_value = _client()
        client = redis_client_from_url("redis://localhost:6379/0", required_by="RedisCache")
    mock_from_url.assert_called_once_with("redis://localhost:6379/0", decode_responses=True)
    assert client is mock_from_url.return_value


def test_client_from_url_raises_when_redis_is_not_installed():
    with patch.object(redis_store_module, "redis", None):
        with pytest.raises(ImportError, match="redis is required for RedisCache"):
            redis_client_from_url("redis://localhost:6379/0", required_by="RedisCache")
