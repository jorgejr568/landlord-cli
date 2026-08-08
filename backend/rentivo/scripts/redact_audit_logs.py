"""Backfill: redact plaintext PIX from existing ``audit_logs`` rows.

Usage:
    python -m rentivo.scripts.redact_audit_logs
    python -m rentivo.scripts.redact_audit_logs --dry-run

Behavior:
- Walks every ``audit_logs`` row.
- For each row, parses ``previous_state`` and ``new_state`` JSON (each may be NULL).
- Every key the live redactor treats as PII — :data:`rentivo.pii_redaction.PII_FIELDS`,
  the same table ``AuditService.log`` and the structlog processor chain mask
  through — is replaced in place with its partial-mask redaction. Reading the
  table rather than restating it is what keeps the backfill from lagging the
  redactor when a field is added there.
- The redaction is deterministic and key-less, so already-redacted rows are
  byte-for-byte unchanged on re-run.
- Writes back the rewritten JSON only if the dict actually changed.
- Idempotent. Re-running on already-redacted rows is a no-op.
- Rows carrying the earlier ``abc...xy`` / ``al...@example.com`` mask shape are
  re-masked once into the current shape and are byte-for-byte stable from then
  on. No plaintext is exposed by that pass.

Operator note: run this once after deploying the redacted serializers
(``rentivo/services/audit_serializers.py``). New audit rows written after that
deploy already have the redacted shape; this script handles the legacy backlog.
"""

from __future__ import annotations

import json

import structlog
from rich.console import Console
from rich.table import Table
from sqlalchemy import Connection, text

from rentivo.pii_redaction import PII_FIELDS, normalize_field, redact
from rentivo.scripts._cli import boot, parse_dry_run

logger = structlog.get_logger(__name__)
console = Console()


_DROP_KEYS = ("organization_name",)


def _redact_state(state_json: str | None) -> tuple[str | None, bool]:
    """Return (rewritten_json, changed). ``changed`` is True iff any PII key
    was rewritten. ``state_json`` of None / empty is passed through unchanged
    with changed=False."""
    if state_json is None or state_json == "":
        return state_json, False
    try:
        data = json.loads(state_json)
    except TypeError, ValueError:
        # Not a valid JSON object — leave as-is. Audit logs are append-only;
        # corrupting one row by parsing it as something it isn't would be worse
        # than leaving the leak in place.
        return state_json, False
    if not isinstance(data, dict):
        return state_json, False

    changed = False
    # Legacy rows carry PII under whatever key the serializer of the day used:
    # email.send payloads stored a plaintext to_email, invite rows stored
    # invited_email / invited_by_email, login rows a bare email. Rather than
    # restate that list, look every key up in the live redactor's table so a
    # field added there is backfilled here on the next run. Top-level keys
    # only — audit state dicts are flat.
    for key in list(data):
        kind = PII_FIELDS.get(normalize_field(key))
        if kind is None:
            continue
        value = data[key]
        if not isinstance(value, str):
            # Legacy rows are hand-written history: a PII key may hold a number,
            # a null or a nested object. The redactor only masks text, and one
            # such row must not abort the whole backfill.
            continue
        redacted = redact(value or "", kind)
        if redacted != value:
            data[key] = redacted
            changed = True

    # Drop legacy keys that the current serializers no longer write.
    # organization_name was being logged in plaintext on invite audit rows;
    # serialize_invite now omits it (the org id and org's own audit events
    # capture the name on the rare occasion it matters).
    for key in _DROP_KEYS:
        if key in data:
            del data[key]
            changed = True

    if not changed:
        return state_json, False
    return json.dumps(data), True


def run(conn: Connection, *, dry_run: bool) -> None:
    label = "[yellow]DRY-RUN[/yellow]" if dry_run else "[green]LIVE[/green]"
    console.print(f"\n[bold]Redact audit_logs[/bold] {label}\n")

    rows = conn.execute(text("SELECT id, previous_state, new_state FROM audit_logs")).mappings().fetchall()
    rewritten = 0
    skipped = 0
    for row in rows:
        prev_new, prev_changed = _redact_state(row["previous_state"])
        new_new, new_changed = _redact_state(row["new_state"])
        if not (prev_changed or new_changed):
            skipped += 1
            continue
        if not dry_run:
            conn.execute(
                text("UPDATE audit_logs SET previous_state = :prev, new_state = :new WHERE id = :id"),
                {"prev": prev_new, "new": new_new, "id": row["id"]},
            )
        rewritten += 1

    if not dry_run:
        conn.commit()

    table = Table(title="Redaction summary")
    table.add_column("Outcome", style="bold")
    table.add_column("Rows", justify="right")
    table.add_row("Rewritten", str(rewritten))
    table.add_row("Skipped (no PII)", str(skipped))
    console.print(table)
    logger.info(
        "redact_audit_logs_done",
        rewritten=rewritten,
        skipped=skipped,
        dry_run=dry_run,
    )

    if dry_run:
        console.print("[yellow]Re-run without --dry-run to apply.[/yellow]")


def main() -> None:
    conn = boot()
    dry_run = parse_dry_run()
    run(conn, dry_run=dry_run)


if __name__ == "__main__":  # pragma: no cover
    main()
