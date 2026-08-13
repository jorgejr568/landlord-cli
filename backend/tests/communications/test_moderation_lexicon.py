import pytest

from rentivo.communications.moderation import scan
from rentivo.communications.moderation_base import ModerationBackend
from rentivo.communications.moderation_lexicon import LexiconModerationBackend


def test_backend_cannot_be_instantiated_without_scan():
    with pytest.raises(TypeError):
        ModerationBackend()


@pytest.mark.asyncio
async def test_benign_text_passes_through():
    backend = LexiconModerationBackend()
    assert isinstance(backend, ModerationBackend)

    result = await backend.scan("Boa tarde, o boleto de marco vence dia 10.")

    assert result.flagged is False
    assert result == scan("Boa tarde, o boleto de marco vence dia 10.")


@pytest.mark.asyncio
async def test_flagged_text_matches_the_sync_lexicon():
    text = "voce e um babaca e vou te matar"

    result = await LexiconModerationBackend().scan(text)

    assert result == scan(text)
    assert result.blocked is True
    assert result.mild == ("babaca",)
