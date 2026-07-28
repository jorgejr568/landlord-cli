"""Shared helpers for SQLAlchemy repositories."""

from __future__ import annotations

from collections.abc import Iterable, Iterator, Sequence
from datetime import datetime

from sqlalchemy.engine import RowMapping

from rentivo.constants import SP_TZ
from rentivo.encryption.base import EncryptionBackend
from rentivo.models.recipient import Recipient


def _now() -> datetime:
    return datetime.now(SP_TZ)


def _as_local(value: datetime | str | None) -> datetime | None:
    """Label a naive stored timestamp with the timezone it was written in.

    Timestamps written by `_now()` land in naive ``DATETIME`` columns, so the
    offset is dropped on the way in and MariaDB hands back bare São Paulo wall
    clock. Serializing that as-is produces ``2026-07-28T13:28:55`` — not
    RFC 3339 — which strict clients reject even though the API contract
    declares ``format: date-time``. Re-attaching `SP_TZ` restores the offset
    without shifting the instant, so existing rows keep their meaning.

    SQLite returns these columns as strings that already carry the offset, so
    values that are parsed as aware are passed through untouched.
    """
    if value is None:
        return None
    if isinstance(value, str):
        value = datetime.fromisoformat(value)
    if value.tzinfo is not None:
        return value
    return value.replace(tzinfo=SP_TZ)


def build_recipients(encryption: EncryptionBackend, rows: Sequence[RowMapping]) -> list[Recipient]:
    """Assemble ``Recipient`` models from rows, decrypting ``name``/``email`` in one batch.

    Shared by the recipient and reply-to repositories, which back the same
    model with identically-shaped (but separate) tables.
    """
    if not rows:
        return []
    plaintexts = decrypt_columns(encryption, rows, ("name", "email"))
    return [
        Recipient(
            id=row["id"],
            uuid=row["uuid"],
            billing_id=row["billing_id"],
            name=next(plaintexts),
            email=next(plaintexts),
            sort_order=row["sort_order"],
            created_at=row["created_at"],
        )
        for row in rows
    ]


def decrypt_columns(encryption: EncryptionBackend, rows: Sequence[RowMapping], fields: Sequence[str]) -> Iterator[str]:
    """Decrypt the named columns across all rows in a single batched call.

    Collects ``fields`` from each row in row-major order, runs one
    ``decrypt_many``, and returns an iterator the caller drains with
    ``next()`` while reassembling models — so an N-row × M-column page costs
    one decrypt round-trip instead of N×M. Missing/NULL cells decrypt as ``""``.
    """
    return iter(encryption.decrypt_many([row[f] or "" for row in rows for f in fields]))


def _group_rows_by(rows: Iterable[RowMapping], key: str) -> dict[int, list[RowMapping]]:
    """Bucket child rows by a foreign-key column, preserving fetch order within each bucket."""
    grouped: dict[int, list[RowMapping]] = {}
    for row in rows:
        grouped.setdefault(row[key], []).append(row)
    return grouped
