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

BRAZIL_AREA_CODES = frozenset(
    {
        "11",
        "12",
        "13",
        "14",
        "15",
        "16",
        "17",
        "18",
        "19",
        "21",
        "22",
        "24",
        "27",
        "28",
        "31",
        "32",
        "33",
        "34",
        "35",
        "37",
        "38",
        "41",
        "42",
        "43",
        "44",
        "45",
        "46",
        "47",
        "48",
        "49",
        "51",
        "53",
        "54",
        "55",
        "61",
        "62",
        "63",
        "64",
        "65",
        "66",
        "67",
        "68",
        "69",
        "71",
        "73",
        "74",
        "75",
        "77",
        "79",
        "81",
        "82",
        "83",
        "84",
        "85",
        "86",
        "87",
        "88",
        "89",
        "91",
        "92",
        "93",
        "94",
        "95",
        "96",
        "97",
        "98",
        "99",
    }
)


def is_valid_cpf(value: str) -> bool:
    """Return whether an unformatted CPF has valid check digits."""
    if len(value) != 11 or not value.isascii() or not value.isdigit() or len(set(value)) == 1:
        return False
    digits = [int(character) for character in value]
    first = (sum(digit * weight for digit, weight in zip(digits[:9], range(10, 1, -1), strict=True)) * 10) % 11
    if first == 10:
        first = 0
    second = (sum(digit * weight for digit, weight in zip(digits[:10], range(11, 1, -1), strict=True)) * 10) % 11
    if second == 10:
        second = 0
    return digits[-2:] == [first, second]


def is_valid_brazilian_phone(value: str) -> bool:
    """Return whether a normalized +55 phone has a valid Brazilian area code."""
    return bool(PIX_KEY_PATTERNS["phone"].fullmatch(value)) and value[3:5] in BRAZIL_AREA_CODES


def classify_pix_key(key: str) -> str | None:
    """Return the PIX key type ('cpf', 'cnpj', 'email', 'phone', 'evp') or None if invalid."""
    if not key:
        return None
    for kind, pattern in PIX_KEY_PATTERNS.items():
        if pattern.match(key):
            return kind
    return None
