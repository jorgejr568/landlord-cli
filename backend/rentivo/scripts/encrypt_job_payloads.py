"""Backfill: encrypt legacy plaintext ``jobs.payload`` rows.

Usage:
    python -m rentivo.scripts.encrypt_job_payloads
    python -m rentivo.scripts.encrypt_job_payloads --dry-run

Behavior:
- Walks every ``jobs`` row.
- Rows already stored as the ``{"__enc": ...}`` envelope are skipped.
- Legacy plaintext rows are re-written as ``{"__enc": "<ciphertext>"}`` through
  the active encryption backend.
- A row whose payload is not parseable JSON is left untouched: rewriting it
  would destroy the only copy of whatever it holds.
- Idempotent. Re-running is safe.
- ``--dry-run`` reports counts without writing.

Operator note: run this once after deploying the encrypting job repository.
New rows written after that deploy are already encrypted; this handles the
backlog. Jobs are never deleted today, so the backlog is every job ever
enqueued -- including third-party recipient addresses and (expired)
password-reset URLs.
"""

from __future__ import annotations

import json
import sys

import structlog
from rich.console import Console
from rich.table import Table
from sqlalchemy import Connection, text

from rentivo.db import get_connection, initialize_db
from rentivo.encryption.base import EncryptionBackend
from rentivo.encryption.factory import get_encryption
from rentivo.jobs.sqlalchemy import _ENVELOPE_KEY, encode_job_payload
from rentivo.logging import configure_logging

logger = structlog.get_logger(__name__)
console = Console()


def run(conn: Connection, encryption: EncryptionBackend, *, dry_run: bool) -> None:
    label = "[yellow]DRY-RUN[/yellow]" if dry_run else "[green]LIVE[/green]"
    console.print(f"\n[bold]Encrypt jobs.payload[/bold] {label}\n")

    rows = conn.execute(text("SELECT id, payload FROM jobs")).mappings().fetchall()
    rewritten = 0
    skipped = 0
    unparseable = 0

    for row in rows:
        raw = row["payload"]
        try:
            decoded = raw if isinstance(raw, dict) else json.loads(raw)
        except TypeError, ValueError:
            # Not parseable JSON. Leave it alone -- rewriting would destroy the
            # only copy of whatever this row holds.
            unparseable += 1
            continue
        if not isinstance(decoded, dict) or _ENVELOPE_KEY in decoded:
            skipped += 1
            continue
        if not dry_run:
            conn.execute(
                text("UPDATE jobs SET payload = :payload WHERE id = :id"),
                {"payload": encode_job_payload(encryption, decoded), "id": row["id"]},
            )
        rewritten += 1

    if not dry_run:
        conn.commit()

    table = Table(title="Job payload encryption summary")
    table.add_column("Outcome", style="bold")
    table.add_column("Rows", justify="right")
    table.add_row("Rewritten", str(rewritten))
    table.add_row("Skipped (already encrypted)", str(skipped))
    table.add_row("Skipped (unparseable)", str(unparseable))
    console.print(table)
    logger.info(
        "encrypt_job_payloads_done",
        rewritten=rewritten,
        skipped=skipped,
        unparseable=unparseable,
        dry_run=dry_run,
    )

    if dry_run:
        console.print("[yellow]Re-run without --dry-run to apply.[/yellow]")


def main() -> None:
    configure_logging(cli=True)
    dry_run = "--dry-run" in sys.argv
    initialize_db()
    conn = get_connection()
    encryption = get_encryption()
    run(conn, encryption, dry_run=dry_run)


if __name__ == "__main__":  # pragma: no cover
    main()
