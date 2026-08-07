"""Regression guards for BE-4: job payloads must never be persisted in plaintext.

The jobs table holds third-party email addresses (invitees, billing recipients),
client IPs, user agents, and a live password-reset URL. It is not reachable
through any API route, but it is readable by anyone holding a MariaDB backup,
a read replica, or low-privilege DB credentials -- which is exactly the reader
that `users.email` encryption and the separate RENTIVO_KMS_* credential pair
are designed to exclude.

Companion evidence: services/audit_serializers.py::serialize_job_payload already
masks to_email and drops every ctx value before a payload reaches audit_logs,
and scripts/redact_audit_logs.py scrubbed the historical audit copies. These
guards keep the original from drifting back to plaintext.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from sqlalchemy import text

from rentivo.encryption.base64 import Base64Backend
from rentivo.jobs.sqlalchemy import SQLAlchemyJobRepository

REPO_ROOT = Path(__file__).resolve().parents[2]

SENSITIVE_PAYLOAD = {
    "event": "password_reset",
    "to_email": "tenant@example.com",
    "ctx": {
        "email": "tenant@example.com",
        "reset_url": "https://app.example/reset-password?token=live-reset-token",
        "source_ip": "203.0.113.7",
        "user_agent": "Mozilla/5.0 (X11; Linux x86_64)",
    },
}

SECRETS = (
    "tenant@example.com",
    "live-reset-token",
    "203.0.113.7",
    "Mozilla/5.0",
    "password_reset",
)


def test_enqueued_payload_is_not_readable_as_plaintext_in_the_database(db_connection):
    repo = SQLAlchemyJobRepository(db_connection, Base64Backend())

    repo.enqueue("email.send", SENSITIVE_PAYLOAD)

    stored = db_connection.execute(text("SELECT payload FROM jobs")).scalar_one()
    for secret in SECRETS:
        assert secret not in stored, f"{secret!r} was persisted in cleartext in jobs.payload"


def test_stored_payload_is_valid_json_so_mariadbs_json_valid_check_accepts_it(db_connection):
    """MariaDB renders `payload JSON` as `longtext ... CHECK (json_valid(payload))`.

    A bare `enc:v1:...` ciphertext fails that constraint with ERROR 4025 while
    passing silently on SQLite, so this guard is what stops a production-only
    outage from shipping green.
    """
    repo = SQLAlchemyJobRepository(db_connection, Base64Backend())

    repo.enqueue("email.send", SENSITIVE_PAYLOAD)

    stored = db_connection.execute(text("SELECT payload FROM jobs")).scalar_one()
    parsed = json.loads(stored)
    assert isinstance(parsed, dict)
    assert set(parsed) == {"__enc"}


def test_enqueue_round_trips_the_payload_back_to_the_caller(db_connection):
    repo = SQLAlchemyJobRepository(db_connection, Base64Backend())

    job = repo.enqueue("email.send", SENSITIVE_PAYLOAD)

    assert job.payload == SENSITIVE_PAYLOAD


_PLAINTEXT_DUMPS_RE = re.compile(r'"payload"\s*:\s*json\.dumps\(')


def test_job_repository_never_binds_a_bare_json_dumps_to_the_payload_column():
    """The payload bind must go through encode_job_payload, not raw json.dumps."""
    source = (REPO_ROOT / "rentivo" / "jobs" / "sqlalchemy.py").read_text(encoding="utf-8")

    assert not _PLAINTEXT_DUMPS_RE.search(source), (
        "jobs.payload must be bound via encode_job_payload() so it is encrypted at rest -- "
        "see backend/tests/security/test_job_payload_encryption.py"
    )
    assert "encode_job_payload(self.encryption, payload)" in source


def test_job_idempotency_is_not_derived_from_the_payload():
    """Dedup identity is the ULID on both drivers.

    KMS ciphertext is non-deterministic, so deriving an idempotency key from the
    stored payload would silently break dedup. Lock the ULID-based contract in.
    """
    database_source = (REPO_ROOT / "rentivo" / "jobs" / "sqlalchemy.py").read_text(encoding="utf-8")
    temporal_source = (REPO_ROOT / "rentivo" / "jobs" / "temporal" / "backend.py").read_text(encoding="utf-8")

    assert "ulid = str(ULID())" in database_source
    assert 'id=f"job-{ulid}"' in temporal_source
