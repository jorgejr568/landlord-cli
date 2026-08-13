"""Swappable moderation backend contract.

Callers depend on this ABC (resolved through
:func:`rentivo.communications.moderation_factory.get_moderation_backend`) so the
deterministic in-process lexicon and the opt-in remote reviewer are
interchangeable. Every backend returns the same
:class:`~rentivo.communications.moderation.ModerationResult`, and no backend may
return *less* than the lexicon would: remote backends union their verdict with
the local scan so the deterministic floor always holds.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from rentivo.communications.moderation import ModerationResult


class ModerationBackend(ABC):
    @abstractmethod
    async def scan(self, text: str) -> ModerationResult:
        """Scan ``text`` (caller passes subject + body joined) for flagged content."""
        ...
