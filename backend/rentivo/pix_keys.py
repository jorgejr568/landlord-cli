"""PIX key format patterns and type classification.

Deliberately stdlib-only. ``rentivo.pii_redaction`` classifies PIX keys so it
can pick a per-type mask shape, and ``rentivo.logging`` imports
``pii_redaction`` on the earliest startup path. ``rentivo.pix`` imports
``qrcode`` and ``PIL`` for QR rendering, so the patterns cannot live there
without dragging image libraries into every process start.
"""

from __future__ import annotations

import re

PIX_KEY_PATTERNS: dict[str, re.Pattern[str]] = {
    "cpf": re.compile(r"^\d{11}$"),
    "cnpj": re.compile(r"^\d{14}$"),
    "email": re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$"),
    "phone": re.compile(r"^\+55\d{10,11}$"),
    "evp": re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"),
}


def classify_pix_key(key: str) -> str | None:
    """Return the PIX key type ('cpf', 'cnpj', 'email', 'phone', 'evp') or None if invalid."""
    if not key:
        return None
    for kind, pattern in PIX_KEY_PATTERNS.items():
        if pattern.match(key):
            return kind
    return None
