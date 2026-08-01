"""Tests for the stdlib-only PIX key pattern module.

``rentivo.pii_redaction`` classifies PIX keys, and ``rentivo.logging`` imports
``pii_redaction`` on the earliest startup path. ``rentivo.pix`` imports
``qrcode``/``PIL`` for QR rendering, so the patterns live in their own module
to keep image libraries out of the logging import chain.
"""

from __future__ import annotations

import ast
from pathlib import Path

import pytest

from rentivo.pix_keys import PIX_KEY_PATTERNS, classify_pix_key

MODULE_PATH = Path(__file__).resolve().parents[1] / "rentivo" / "pix_keys.py"


@pytest.mark.parametrize(
    ("key", "kind"),
    [
        ("12345678901", "cpf"),
        ("12345678000190", "cnpj"),
        ("user@example.com", "email"),
        ("+5511987654321", "phone"),
        ("+551198765432", "phone"),
        ("123e4567-e89b-12d3-a456-426614174000", "evp"),
    ],
)
def test_classify_recognizes_every_key_type(key: str, kind: str) -> None:
    assert classify_pix_key(key) == kind


@pytest.mark.parametrize("key", ["", "not-a-key", "1234", "user@", "@example.com", "abcd-1234"])
def test_classify_rejects_non_keys(key: str) -> None:
    assert classify_pix_key(key) is None


def test_pattern_registry_has_exactly_the_five_key_types() -> None:
    assert set(PIX_KEY_PATTERNS) == {"cpf", "cnpj", "email", "phone", "evp"}


def test_module_imports_only_the_standard_library() -> None:
    """rentivo.logging -> pii_redaction -> pix_keys runs before anything else
    is configured. A third-party import here (qrcode, PIL, boto3, ...) would be
    paid on every process start, including the CLI and Alembic."""
    tree = ast.parse(MODULE_PATH.read_text(encoding="utf-8"))
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    assert imported <= {"re", "__future__"}, f"pix_keys must stay stdlib-only, found: {sorted(imported)}"
