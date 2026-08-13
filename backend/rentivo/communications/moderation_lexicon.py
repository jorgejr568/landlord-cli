"""Default moderation backend: the in-process, deterministic PT-BR lexicon.

No network, no external API — tenant content never leaves the system. This is
the backend selected unless ``RENTIVO_MODERATION_BACKEND`` says otherwise.
"""

from __future__ import annotations

from rentivo.communications.moderation import ModerationResult, scan
from rentivo.communications.moderation_base import ModerationBackend


class LexiconModerationBackend(ModerationBackend):
    async def scan(self, text: str) -> ModerationResult:
        return scan(text)
