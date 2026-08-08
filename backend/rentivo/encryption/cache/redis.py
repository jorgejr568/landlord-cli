from __future__ import annotations

from typing import Any

from rentivo.cache.redis_store import RedisStore, StringCodec, redis_client_from_url

_KEY_PREFIX = "rentivo:enc:dec:v1:"


class RedisDecryptCache:
    """Shared TTL cache for decrypted plaintexts, backed by Redis.

    Failure-mode is inherited from :class:`RedisStore`: backend errors are
    swallowed and logged at WARNING, so reads degrade to "cache miss" and
    writes are silently dropped. The decoration layer then falls back to the
    inner encryption backend and requests still succeed — just without the
    cache speedup.

    Constructor takes an injected client so tests can supply ``fakeredis``.
    Production callers should use ``RedisDecryptCache.from_url(...)``.
    """

    def __init__(self, client: Any, ttl_seconds: int) -> None:
        self._store = RedisStore(
            client=client,
            ttl_seconds=ttl_seconds,
            key_prefix=_KEY_PREFIX,
            codec=StringCodec(),
            log_namespace="decrypt_cache",
        )

    @classmethod
    def from_url(cls, url: str, ttl_seconds: int) -> "RedisDecryptCache":
        client = redis_client_from_url(url, required_by="RedisDecryptCache")
        return cls(client=client, ttl_seconds=ttl_seconds)

    def get_many(self, keys: list[str]) -> dict[str, str]:
        return self._store.get_many(keys)

    def set_many(self, items: dict[str, str]) -> None:
        self._store.set_many(items)

    def close(self) -> None:
        self._store.close()
