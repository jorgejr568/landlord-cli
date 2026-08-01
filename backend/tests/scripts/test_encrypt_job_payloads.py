"""Tests for the one-shot jobs.payload encryption backfill."""

from __future__ import annotations

import json

from sqlalchemy import text

from rentivo.encryption.base64 import Base64Backend
from rentivo.jobs.sqlalchemy import encode_job_payload
from rentivo.scripts.encrypt_job_payloads import run

LEGACY = {"event": "password_reset", "to_email": "tenant@example.com"}


def _insert(conn, ulid, payload_text, status="succeeded"):
    conn.execute(
        text(
            "INSERT INTO jobs (ulid, job_type, payload, status, attempts, max_attempts, "
            "run_after, created_at, updated_at) "
            "VALUES (:u, 'email.send', :p, :s, 0, 5, '2026-01-01', '2026-01-01', '2026-01-01')"
        ),
        {"u": ulid, "p": payload_text, "s": status},
    )
    conn.commit()


def _payloads(conn):
    return [r[0] for r in conn.execute(text("SELECT payload FROM jobs ORDER BY id")).fetchall()]


def test_rewrites_a_legacy_plaintext_row_as_ciphertext(db_connection):
    _insert(db_connection, "A", json.dumps(LEGACY))

    run(db_connection, Base64Backend(), dry_run=False)

    stored = _payloads(db_connection)[0]
    assert "tenant@example.com" not in stored
    assert json.loads(stored)["__enc"].startswith("b64:v1:")


def test_preserves_the_payload_contents_through_the_rewrite(db_connection):
    from rentivo.jobs.sqlalchemy import decode_job_payload

    _insert(db_connection, "A", json.dumps(LEGACY))

    run(db_connection, Base64Backend(), dry_run=False)

    assert decode_job_payload(Base64Backend(), _payloads(db_connection)[0]) == LEGACY


def test_skips_rows_that_are_already_encrypted(db_connection):
    encrypted = encode_job_payload(Base64Backend(), LEGACY)
    _insert(db_connection, "A", encrypted)

    run(db_connection, Base64Backend(), dry_run=False)

    assert _payloads(db_connection) == [encrypted]


def test_is_idempotent_across_repeated_runs(db_connection):
    _insert(db_connection, "A", json.dumps(LEGACY))

    run(db_connection, Base64Backend(), dry_run=False)
    first = _payloads(db_connection)
    run(db_connection, Base64Backend(), dry_run=False)

    assert _payloads(db_connection) == first


def test_dry_run_writes_nothing(db_connection):
    _insert(db_connection, "A", json.dumps(LEGACY))

    run(db_connection, Base64Backend(), dry_run=True)

    assert _payloads(db_connection) == [json.dumps(LEGACY)]


def test_leaves_an_unparseable_row_untouched(db_connection):
    _insert(db_connection, "A", "not json at all")

    run(db_connection, Base64Backend(), dry_run=False)

    assert _payloads(db_connection) == ["not json at all"]


def test_main_wires_the_db_and_encryption_factories(monkeypatch, db_connection):
    import rentivo.scripts.encrypt_job_payloads as mod

    _insert(db_connection, "A", json.dumps(LEGACY))
    monkeypatch.setattr(mod, "initialize_db", lambda: None)
    monkeypatch.setattr(mod, "get_connection", lambda: db_connection)
    monkeypatch.setattr(mod, "get_encryption", Base64Backend)
    monkeypatch.setattr(mod, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(mod.sys, "argv", ["encrypt_job_payloads"])

    mod.main()

    assert "tenant@example.com" not in _payloads(db_connection)[0]


def test_main_honours_the_dry_run_flag(monkeypatch, db_connection):
    import rentivo.scripts.encrypt_job_payloads as mod

    _insert(db_connection, "A", json.dumps(LEGACY))
    monkeypatch.setattr(mod, "initialize_db", lambda: None)
    monkeypatch.setattr(mod, "get_connection", lambda: db_connection)
    monkeypatch.setattr(mod, "get_encryption", Base64Backend)
    monkeypatch.setattr(mod, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(mod.sys, "argv", ["encrypt_job_payloads", "--dry-run"])

    mod.main()

    assert _payloads(db_connection) == [json.dumps(LEGACY)]
