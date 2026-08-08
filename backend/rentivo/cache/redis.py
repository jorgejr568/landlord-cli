from __future__ import annotations

from typing import Any

from rentivo.cache.redis_store import JSONCodec, RedisStore, redis_client_from_url

_KEY_PREFIX = "rentivo:cache:v1:"


class RedisCache:
    """Shared TTL cache backed by Redis. Values are stored as JSON.

    Failure-mode is inherited from :class:`RedisStore`: backend errors are
    swallowed and logged at WARNING, so reads degrade to "cache miss" and
    writes are silently dropped.

    Constructor takes an injected client so tests can supply ``fakeredis``.
    Production callers should use ``RedisCache.from_url(...)``.
    """

    def __init__(self, client: Any, ttl_seconds: int) -> None:
        self._store = RedisStore(
            client=client,
            ttl_seconds=ttl_seconds,
            key_prefix=_KEY_PREFIX,
            codec=JSONCodec(),
            log_namespace="cache",
        )

    @classmethod
    def from_url(cls, url: str, ttl_seconds: int) -> "RedisCache":
        client = redis_client_from_url(url, required_by="RedisCache")
        return cls(client=client, ttl_seconds=ttl_seconds)

    def get(self, key: str) -> Any | None:
        return self._store.get_many([key]).get(key)

    def set(self, key: str, value: Any) -> None:
        self._store.set_many({key: value})

    def clear(self) -> None:
        self._store.clear()

    def close(self) -> None:
        self._store.close()
