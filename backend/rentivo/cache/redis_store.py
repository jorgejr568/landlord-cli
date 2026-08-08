from __future__ import annotations

import hashlib
import json
from typing import Any, Protocol

import structlog

try:
    import redis  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover - exercised via patched import in tests
    redis = None  # type: ignore[assignment]

logger = structlog.get_logger(__name__)


def redis_client_from_url(url: str, *, required_by: str) -> Any:
    """Build a decoding Redis client, or explain which extra is missing."""
    if redis is None:
        raise ImportError(f"redis is required for {required_by}. Install it with: pip install 'rentivo[cache]'")
    return redis.from_url(url, decode_responses=True)


class Codec(Protocol):
    """Translates cached values to and from the strings Redis stores."""

    def encode(self, value: Any) -> str:
        """Return the string to store, or raise if ``value`` is unsupported."""
        ...

    def decode(self, raw: str) -> Any:
        """Return the value for a stored string, or raise if it is corrupt."""
        ...


class JSONCodec:
    """Stores arbitrary JSON-serialisable values as JSON documents."""

    def encode(self, value: Any) -> str:
        return json.dumps(value)

    def decode(self, raw: str) -> Any:
        return json.loads(raw)


class StringCodec:
    """Stores strings verbatim — nothing to serialise."""

    def encode(self, value: Any) -> str:
        return value

    def decode(self, raw: str) -> Any:
        return raw


class RedisStore:
    """Shared TTL store backed by Redis, addressed by hashed, prefixed keys.

    Failure-mode: any exception from the redis client (network, codec) is
    swallowed and logged at WARNING under ``<log_namespace>_redis_*_failed``;
    reads degrade to a cache miss and writes are silently dropped, so callers
    still recompute and succeed — just without the cache speedup.

    Takes an injected client so tests can supply ``fakeredis``. Production
    callers build one with :func:`redis_client_from_url`.
    """

    def __init__(
        self,
        client: Any,
        ttl_seconds: int,
        *,
        key_prefix: str,
        codec: Codec,
        log_namespace: str,
    ) -> None:
        self._client = client
        self._ttl_seconds = ttl_seconds
        self._key_prefix = key_prefix
        self._codec = codec
        self._log_namespace = log_namespace

    def redis_key(self, key: str) -> str:
        """Return the namespaced key a caller key is stored under."""
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        return self._key_prefix + digest

    def _warn(self, operation: str, exc: Exception) -> None:
        logger.warning(f"{self._log_namespace}_redis_{operation}_failed", error=str(exc))

    def get_many(self, keys: list[str]) -> dict[str, Any]:
        if not keys:
            return {}
        try:
            values = self._client.mget([self.redis_key(key) for key in keys])
        except Exception as exc:
            self._warn("get", exc)
            return {}
        out: dict[str, Any] = {}
        for key, raw in zip(keys, values):
            if raw is None:
                continue
            try:
                out[key] = self._codec.decode(raw)
            except Exception as exc:
                self._warn("decode", exc)
        return out

    def set_many(self, items: dict[str, Any]) -> None:
        encoded: dict[str, str] = {}
        for key, value in items.items():
            # Narrow on purpose: a value the codec cannot serialise is a dropped
            # cache write, but anything else raised in-process is a bug that
            # must surface rather than be logged away as a cache miss.
            try:
                encoded[self.redis_key(key)] = self._codec.encode(value)
            except (TypeError, ValueError) as exc:
                self._warn("encode", exc)
        if not encoded:
            return
        try:
            with self._client.pipeline() as pipe:
                for redis_key, payload in encoded.items():
                    pipe.set(redis_key, payload, ex=self._ttl_seconds)
                pipe.execute()
        except Exception as exc:
            self._warn("set", exc)

    def clear(self) -> None:
        try:
            keys = list(self._client.scan_iter(match=self._key_prefix + "*"))
            if keys:
                self._client.delete(*keys)
        except Exception as exc:
            self._warn("clear", exc)

    def close(self) -> None:
        try:
            self._client.close()
        except Exception as exc:
            self._warn("close", exc)
