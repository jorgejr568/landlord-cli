from __future__ import annotations

from unittest.mock import patch

import pytest

from rentivo.communications import moderation_openrouter
from rentivo.communications.moderation_factory import get_moderation_backend
from rentivo.communications.moderation_lexicon import LexiconModerationBackend
from rentivo.communications.moderation_openrouter import OpenRouterModerationBackend
from rentivo.settings import settings

OPENROUTER_SETTINGS = {
    "moderation_backend": "openrouter",
    "openrouter_api_key": "or-secret",
    "openrouter_base_url": "https://openrouter.ai/api/v1",
    "openrouter_model": "openai/gpt-5-mini",
    "moderation_timeout_seconds": 8.0,
    "moderation_cache_ttl_seconds": 600,
}


def _apply(monkeypatch: pytest.MonkeyPatch, values: dict) -> None:
    for name, value in values.items():
        monkeypatch.setattr(settings, name, value, raising=False)


def test_lexicon_backend_is_the_default_dispatch(monkeypatch):
    _apply(monkeypatch, {"moderation_backend": "lexicon"})

    assert isinstance(get_moderation_backend(), LexiconModerationBackend)


def test_openrouter_backend_is_built_from_settings(monkeypatch):
    _apply(monkeypatch, OPENROUTER_SETTINGS)

    with patch.object(moderation_openrouter, "get_cache") as get_cache:
        backend = get_moderation_backend()

    get_cache.assert_called_once()
    assert isinstance(backend, OpenRouterModerationBackend)
    assert backend.api_key == "or-secret"
    assert backend.model == "openai/gpt-5-mini"
    assert backend.timeout_seconds == 8.0
    assert backend.cache_ttl_seconds == 600
    assert backend.endpoint == "https://openrouter.ai/api/v1/responses"


def test_unsupported_backend_raises(monkeypatch):
    _apply(monkeypatch, {"moderation_backend": "gpt-o-matic"})

    with pytest.raises(ValueError, match="Unsupported moderation backend"):
        get_moderation_backend()
