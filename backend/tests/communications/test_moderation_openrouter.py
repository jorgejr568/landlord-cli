from __future__ import annotations

import json
import time
from typing import Any
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from rentivo.communications import moderation_openrouter as mod
from rentivo.communications.moderation_openrouter import (
    CACHE_KEY_PREFIX,
    MAX_ENTRIES,
    MAX_ENTRY_LENGTH,
    OpenRouterModerationBackend,
)

BENIGN = "Boa tarde, o boleto de marco vence dia 10."
# "babaca" is a mild lexicon hit — used to prove the deterministic floor holds.
MILD_TEXT = "voce e um babaca, pague logo"
MODEL = "openai/gpt-5-mini"


class FakeCache:
    """Minimal ``Cache`` double with switchable failure modes."""

    def __init__(self, *, fail_get: bool = False, fail_set: bool = False) -> None:
        self.values: dict[str, Any] = {}
        self.fail_get = fail_get
        self.fail_set = fail_set

    def get(self, key: str) -> Any | None:
        if self.fail_get:
            raise RuntimeError("cache down")
        return self.values.get(key)

    def set(self, key: str, value: Any) -> None:
        if self.fail_set:
            raise RuntimeError("cache down")
        self.values[key] = value

    def clear(self) -> None:  # pragma: no cover - not exercised by the backend
        self.values.clear()

    def close(self) -> None:  # pragma: no cover - not exercised by the backend
        return None


def _verdict_payload(severe: list[str], mild: list[str]) -> dict[str, Any]:
    """A Responses API payload carrying the model's JSON verdict."""
    return {
        "output": [
            {"type": "reasoning", "summary": []},
            {
                "type": "message",
                "content": [
                    {"type": "refusal", "refusal": "ignored"},
                    {"type": "output_text", "text": json.dumps({"severe": severe, "mild": mild})},
                ],
            },
        ]
    }


def _text_payload(text: str) -> dict[str, Any]:
    return {"output": [{"type": "message", "content": [{"type": "output_text", "text": text}]}]}


def _response(payload: Any) -> AsyncMock:
    response = AsyncMock()
    response.json = lambda: payload
    response.raise_for_status = lambda: None
    return response


def _client(payload: Any) -> AsyncMock:
    client = AsyncMock()
    client.post = AsyncMock(return_value=_response(payload))
    return client


def _backend(client: Any = None, cache: FakeCache | None = None, **overrides: Any) -> OpenRouterModerationBackend:
    kwargs: dict[str, Any] = {
        "api_key": "or-secret",
        "base_url": "https://openrouter.invalid/api/v1",
        "model": MODEL,
        "timeout_seconds": 8.0,
        "cache_ttl_seconds": 600,
    }
    kwargs.update(overrides)
    return OpenRouterModerationBackend(
        **kwargs,
        http_client_factory=lambda: client if client is not None else AsyncMock(),
        cache=cache if cache is not None else FakeCache(),
    )


@pytest.mark.asyncio
async def test_benign_text_sends_the_expected_responses_request():
    client = _client(_verdict_payload([], []))
    backend = _backend(client)

    result = await backend.scan(BENIGN)

    assert result.flagged is False
    client.post.assert_awaited_once()
    args, kwargs = client.post.call_args
    assert args[0] == "https://openrouter.invalid/api/v1/responses"
    assert kwargs["headers"]["Authorization"] == "Bearer or-secret"
    assert kwargs["timeout"] == 8.0
    body = kwargs["json"]
    assert body["model"] == MODEL
    assert body["input"] == BENIGN
    # The default model reasons before answering, and the budget covers both:
    # low effort plus enough headroom for reasoning and the verdict.
    assert body["reasoning"] == {"effort": "low"}
    assert body["max_output_tokens"] == 1024
    assert body["provider"] == {"data_collection": "deny", "require_parameters": True}
    assert "content-safety reviewer" in body["instructions"]
    assert "Do not quote or restate the message content in the reason." in body["instructions"]
    fmt = body["text"]["format"]
    assert fmt["type"] == "json_schema"
    assert fmt["name"] == "moderation_verdict"
    assert fmt["strict"] is True
    assert fmt["schema"]["required"] == ["severe", "mild"]
    assert fmt["schema"]["additionalProperties"] is False


@pytest.mark.asyncio
async def test_policy_codes_are_mapped_to_fixed_local_reasons():
    client = _client(_verdict_payload(["threat"], ["aggressive_tone"]))

    result = await _backend(client).scan(BENIGN)

    assert result.severe == ("Ameaça", "Tom agressivo ou hostil")
    assert result.mild == ()


@pytest.mark.asyncio
async def test_unknown_policy_code_falls_back_without_caching_model_text():
    cache = FakeCache()
    client = _client(_verdict_payload(["Mensagem sobre João da Silva"], []))

    result = await _backend(client, cache).scan(BENIGN)

    assert result.flagged is False
    assert cache.values == {}


@pytest.mark.asyncio
async def test_ai_verdict_is_unioned_with_the_lexicon_result():
    client = _client(_verdict_payload(["threat"], ["aggressive_tone"]))

    result = await _backend(client).scan(MILD_TEXT)

    assert result.severe == ("babaca", "Ameaça", "Tom agressivo ou hostil")
    assert result.mild == ()
    assert result.blocked is True


@pytest.mark.asyncio
async def test_duplicate_reasons_are_deduped_order_preserving():
    client = _client(_verdict_payload(["threat", "threat"], ["aggressive_tone", "aggressive_tone"]))

    result = await _backend(client).scan(MILD_TEXT)

    assert result.severe == ("babaca", "Ameaça", "Tom agressivo ou hostil")
    assert result.mild == ()


@pytest.mark.asyncio
async def test_blank_entries_are_rejected():
    cache = FakeCache()
    client = _client(_verdict_payload([], ["   ", "aggressive_tone"]))

    result = await _backend(client, cache).scan(BENIGN)

    assert result.flagged is False
    assert cache.values == {}


@pytest.mark.asyncio
async def test_output_text_convenience_field_is_accepted():
    payload = {"output_text": json.dumps({"severe": [], "mild": ["pressure_tactics"]}), "output": []}
    client = _client(payload)

    result = await _backend(client).scan(BENIGN)

    assert result.severe == ("Pressão indevida",)
    assert result.mild == ()


@pytest.mark.asyncio
async def test_successful_verdict_is_cached_and_reused():
    cache = FakeCache()
    client = _client(_verdict_payload([], ["aggressive_tone"]))
    backend = _backend(client, cache)

    first = await backend.scan(BENIGN)
    stored_key, stored = next(iter(cache.values.items()))
    assert stored_key.startswith(f"{CACHE_KEY_PREFIX}:{MODEL}:")
    assert stored["mild"] == ["aggressive_tone"]
    assert stored["expires_at"] > time.time()

    second = await backend.scan(BENIGN)

    # Second scan is served from the cache: still exactly one HTTP call.
    client.post.assert_awaited_once()
    assert second == first


@pytest.mark.asyncio
async def test_cache_hit_skips_the_http_call_and_still_merges_the_lexicon():
    cache = FakeCache()
    backend = _backend(cache=cache)
    cache.values[backend._cache_key(MILD_TEXT)] = {
        "severe": ["threat"],
        "mild": ["aggressive_tone"],
        "expires_at": time.time() + 60,
    }
    client = _client(_verdict_payload([], []))
    backend._factory = lambda: client

    result = await backend.scan(MILD_TEXT)

    client.post.assert_not_called()
    assert result.severe == ("babaca", "Ameaça", "Tom agressivo ou hostil")
    assert result.mild == ()


@pytest.mark.asyncio
async def test_expired_cache_entry_is_treated_as_a_miss():
    cache = FakeCache()
    client = _client(_verdict_payload([], []))
    backend = _backend(client, cache)
    cache.values[backend._cache_key(BENIGN)] = {"severe": [], "mild": [], "expires_at": time.time() - 1}

    await backend.scan(BENIGN)

    client.post.assert_awaited_once()


@pytest.mark.parametrize(
    "entry",
    [
        # No `expires_at` at all: the freshness check raises before the verdict
        # is ever coerced.
        pytest.param({"severe": "not-a-list"}, id="missing-expires-at"),
        # Structurally valid, still-fresh envelope carrying a malformed verdict:
        # only these cases reach `_coerce_verdict`.
        pytest.param({"severe": "not-a-list", "mild": [], "fresh": True}, id="severe-not-a-list"),
        pytest.param({"severe": [], "mild": [7], "fresh": True}, id="mild-entry-not-a-string"),
    ],
)
@pytest.mark.asyncio
async def test_corrupt_cache_entry_is_treated_as_a_miss(entry: dict[str, Any]):
    cache = FakeCache()
    client = _client(_verdict_payload([], []))
    backend = _backend(client, cache)
    stored = {k: v for k, v in entry.items() if k != "fresh"}
    if entry.get("fresh"):
        stored["expires_at"] = time.time() + 600
    cache.values[backend._cache_key(BENIGN)] = stored

    await backend.scan(BENIGN)

    client.post.assert_awaited_once()


@pytest.mark.asyncio
async def test_non_dict_cache_entry_is_treated_as_a_miss():
    cache = FakeCache()
    client = _client(_verdict_payload([], []))
    backend = _backend(client, cache)
    cache.values[backend._cache_key(BENIGN)] = "garbage"

    await backend.scan(BENIGN)

    client.post.assert_awaited_once()


@pytest.mark.asyncio
async def test_cache_read_failure_falls_back_to_the_remote_call():
    client = _client(_verdict_payload([], ["aggressive_tone"]))

    result = await _backend(client, FakeCache(fail_get=True)).scan(BENIGN)

    client.post.assert_awaited_once()
    assert result.severe == ("Tom agressivo ou hostil",)
    assert result.mild == ()


@pytest.mark.asyncio
async def test_cache_write_failure_does_not_break_the_scan():
    client = _client(_verdict_payload([], ["aggressive_tone"]))

    result = await _backend(client, FakeCache(fail_set=True)).scan(BENIGN)

    assert result.severe == ("Tom agressivo ou hostil",)
    assert result.mild == ()


@pytest.mark.asyncio
async def test_transport_error_falls_back_to_the_lexicon_result():
    client = AsyncMock()
    client.post = AsyncMock(side_effect=httpx.ConnectError("boom"))

    result = await _backend(client).scan(MILD_TEXT)

    assert result.severe == ("babaca",)
    assert result.mild == ()
    client.aclose.assert_awaited_once()


@pytest.mark.asyncio
async def test_http_status_error_falls_back_to_the_lexicon_result():
    response = AsyncMock()
    response.json = lambda: {}
    error = httpx.HTTPStatusError("429", request=httpx.Request("POST", "https://x"), response=httpx.Response(429))

    def _raise() -> None:
        raise error

    response.raise_for_status = _raise
    client = AsyncMock()
    client.post = AsyncMock(return_value=response)

    result = await _backend(client).scan(MILD_TEXT)

    assert result.severe == ("babaca",)
    assert result.mild == ()


@pytest.mark.asyncio
async def test_client_without_aclose_is_supported():
    class BareClient:
        def __init__(self) -> None:
            self.calls = 0

        async def post(self, url: str, **kwargs: Any) -> Any:
            self.calls += 1
            return _response(_verdict_payload([], []))

    client = BareClient()

    result = await _backend(client).scan(BENIGN)

    assert client.calls == 1
    assert result.flagged is False


@pytest.mark.asyncio
async def test_sync_aclose_is_supported():
    class SyncCloseClient:
        def __init__(self) -> None:
            self.closed = False

        async def post(self, url: str, **kwargs: Any) -> Any:
            return _response(_verdict_payload([], []))

        def aclose(self) -> None:
            self.closed = True

    client = SyncCloseClient()

    await _backend(client).scan(BENIGN)

    assert client.closed is True


@pytest.mark.parametrize(
    "payload",
    [
        pytest.param(_text_payload("not json at all"), id="not-json"),
        pytest.param(_text_payload("[]"), id="json-but-not-an-object"),
        pytest.param(_text_payload(json.dumps({"severe": [], "mild": "nope"})), id="entries-not-a-list"),
        pytest.param(_text_payload(json.dumps({"severe": [1], "mild": []})), id="entry-not-a-string"),
        pytest.param(
            _text_payload(json.dumps({"severe": ["x" * (MAX_ENTRY_LENGTH + 1)], "mild": []})),
            id="entry-too-long",
        ),
        pytest.param(
            _text_payload(json.dumps({"severe": [], "mild": ["a"] * (MAX_ENTRIES + 1)})),
            id="too-many-entries",
        ),
        pytest.param({"output": []}, id="no-message-items"),
        pytest.param({"output": [{"type": "message", "content": [{"type": "refusal"}]}]}, id="no-output-text-part"),
        pytest.param({"output": [{"type": "message", "content": [{"type": "output_text", "text": 7}]}]}, id="non-str"),
        pytest.param({"output": ["not-a-dict"]}, id="item-not-a-dict"),
        pytest.param({"output_text": "   ", "output": []}, id="blank-convenience-field"),
        pytest.param(["not", "an", "object"], id="payload-not-an-object"),
    ],
)
@pytest.mark.asyncio
async def test_malformed_model_output_falls_back_to_the_lexicon_result(payload: Any):
    cache = FakeCache()
    client = _client(payload)

    result = await _backend(client, cache).scan(MILD_TEXT)

    assert result.severe == ("babaca",)
    assert result.mild == ()
    # A rejected verdict is never cached.
    assert cache.values == {}


@pytest.mark.parametrize(
    "payload, expected_reason",
    [
        pytest.param(
            {"status": "incomplete", "incomplete_details": {"reason": "max_output_tokens"}, "output": []},
            "max_output_tokens",
            id="with-incomplete-details",
        ),
        pytest.param({"status": "failed", "output": []}, None, id="without-incomplete-details"),
    ],
)
@pytest.mark.asyncio
async def test_incomplete_response_falls_back_to_the_lexicon_result(
    payload: Any,
    expected_reason: str | None,
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.setattr(mod.settings, "cache_ttl_seconds", 600)
    cache = FakeCache()
    client = _client(payload)

    with patch.object(mod, "logger") as logger:
        result = await _backend(client, cache).scan(MILD_TEXT)

    assert result.severe == ("babaca",)
    assert result.mild == ()
    assert cache.values == {}
    # Distinguishable from the transport and parse failure events.
    logger.warning.assert_called_once_with(
        "moderation_openrouter_incomplete",
        status=payload["status"],
        reason=expected_reason,
    )


@pytest.mark.asyncio
async def test_completed_and_status_less_responses_are_parsed_normally():
    completed = {"status": "completed", **_verdict_payload([], ["aggressive_tone"])}

    result = await _backend(_client(completed)).scan(BENIGN)

    assert result.severe == ("Tom agressivo ou hostil",)
    assert result.mild == ()


class TestCacheTtlCapWarning:
    """The shared cache evicts on its own TTL, so a larger moderation TTL is capped."""

    def test_warns_once_when_the_moderation_ttl_exceeds_the_shared_cache_ttl(self, monkeypatch):
        monkeypatch.setattr(mod, "_ttl_cap_warned", False)
        monkeypatch.setattr(mod.settings, "cache_ttl_seconds", 60)

        with patch.object(mod, "logger") as logger:
            _backend(cache_ttl_seconds=600)
            _backend(cache_ttl_seconds=600)

        logger.warning.assert_called_once_with(
            "moderation_cache_ttl_capped",
            moderation_cache_ttl_seconds=600,
            cache_ttl_seconds=60,
        )

    def test_does_not_warn_when_the_shared_cache_ttl_is_large_enough(self, monkeypatch):
        monkeypatch.setattr(mod, "_ttl_cap_warned", False)
        monkeypatch.setattr(mod.settings, "cache_ttl_seconds", 600)

        with patch.object(mod, "logger") as logger:
            _backend(cache_ttl_seconds=600)

        logger.warning.assert_not_called()


@pytest.mark.asyncio
async def test_cache_key_is_content_addressed_per_model():
    backend = _backend()
    other_model = _backend(model="openai/gpt-4o-mini")

    assert backend._cache_key(BENIGN) != backend._cache_key(MILD_TEXT)
    assert backend._cache_key(BENIGN) != other_model._cache_key(BENIGN)
    # The raw text never appears in the key.
    assert BENIGN not in backend._cache_key(BENIGN)


def test_endpoint_normalises_a_trailing_slash():
    assert _backend(base_url="https://openrouter.invalid/api/v1/").endpoint == (
        "https://openrouter.invalid/api/v1/responses"
    )


def test_default_factory_returns_an_async_httpx_client():
    client = mod._default_factory()
    assert isinstance(client, httpx.AsyncClient)


def test_cache_defaults_to_the_shared_process_cache():
    shared = FakeCache()
    with patch.object(mod, "get_cache", return_value=shared) as get_cache:
        backend = OpenRouterModerationBackend(
            api_key="k",
            base_url="https://openrouter.invalid/api/v1",
            model=MODEL,
            timeout_seconds=1.0,
            cache_ttl_seconds=60,
        )
    get_cache.assert_called_once()
    assert backend._cache is shared


@pytest.mark.asyncio
async def test_scan_emits_a_span(span_exporter):
    await _backend(_client(_verdict_payload([], []))).scan(BENIGN)

    assert "moderation.openrouter" in [s.name for s in span_exporter.get_finished_spans()]


@pytest.mark.asyncio
async def test_span_records_a_fresh_remote_verdict(span_exporter):
    await _backend(_client(_verdict_payload([], []))).scan(BENIGN)

    assert span_exporter.get_finished_spans()[0].attributes["outcome"] == "remote"


@pytest.mark.asyncio
async def test_span_records_a_cache_hit(span_exporter):
    cache = FakeCache()
    backend = _backend(_client(_verdict_payload([], [])), cache)
    cache.values[backend._cache_key(BENIGN)] = {"severe": [], "mild": [], "expires_at": time.time() + 600}

    await backend.scan(BENIGN)

    assert span_exporter.get_finished_spans()[0].attributes["outcome"] == "cache"


@pytest.mark.asyncio
async def test_span_records_a_fail_open(span_exporter):
    client = AsyncMock()
    client.post = AsyncMock(side_effect=httpx.ConnectError("boom"))

    await _backend(client).scan(MILD_TEXT)

    assert span_exporter.get_finished_spans()[0].attributes["outcome"] == "failed_open"
