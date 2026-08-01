"""Tests for the encrypting job repository and its at-rest payload envelope.

``backend/rentivo/jobs/sqlalchemy.py`` is in the coverage ``omit`` list because
``claim_batch`` uses MariaDB-only SQL (``NOW()``, ``INTERVAL ... SECOND``,
``FOR UPDATE SKIP LOCKED``) that cannot execute on the SQLite test suite. These
tests still cover the parts that matter: the codec is pure, and ``enqueue``
uses a portable INSERT that runs on SQLite.
"""

from __future__ import annotations

import json

import pytest
from sqlalchemy import text

from rentivo.encryption.base import EncryptionBackend
from rentivo.encryption.base64 import Base64Backend
from rentivo.jobs.sqlalchemy import (
    SQLAlchemyJobRepository,
    decode_job_payload,
    encode_job_payload,
)

PAYLOAD = {
    "event": "password_reset",
    "to_email": "tenant@example.com",
    "ctx": {"email": "tenant@example.com", "reset_url": "https://app.example/reset-password?token=SECRET"},
}


class _BrokenBackend(EncryptionBackend):
    """Decrypt always raises — stands in for a KMS outage or a destroyed key."""

    def encrypt(self, plaintext: str) -> str:
        return "enc:v1:" + plaintext

    def decrypt(self, value: str) -> str:
        raise RuntimeError("kms unavailable")

    def is_encrypted(self, value: str) -> bool:
        return value.startswith("enc:v1:")


def test_encode_produces_valid_json_object_wrapping_the_ciphertext():
    encoded = encode_job_payload(Base64Backend(), PAYLOAD)

    outer = json.loads(encoded)
    assert isinstance(outer, dict), "MariaDB's implicit json_valid CHECK requires valid JSON"
    assert set(outer) == {"__enc"}
    assert outer["__enc"].startswith("b64:v1:")


def test_encode_does_not_leak_plaintext_into_the_stored_string():
    encoded = encode_job_payload(Base64Backend(), PAYLOAD)

    assert "tenant@example.com" not in encoded
    assert "SECRET" not in encoded
    assert "password_reset" not in encoded


def test_encode_decode_round_trips():
    encryption = Base64Backend()

    assert decode_job_payload(encryption, encode_job_payload(encryption, PAYLOAD)) == PAYLOAD


def test_decode_passes_through_legacy_plaintext_json():
    assert decode_job_payload(Base64Backend(), json.dumps(PAYLOAD)) == PAYLOAD


def test_decode_accepts_a_dict_already_parsed_by_the_driver():
    assert decode_job_payload(Base64Backend(), dict(PAYLOAD)) == PAYLOAD


def test_decode_decrypts_an_envelope_dict_already_parsed_by_the_driver():
    encryption = Base64Backend()
    envelope = json.loads(encode_job_payload(encryption, PAYLOAD))

    assert decode_job_payload(encryption, envelope) == PAYLOAD


def test_enqueue_writes_ciphertext_not_plaintext(db_connection):
    repo = SQLAlchemyJobRepository(db_connection, Base64Backend())

    job = repo.enqueue("email.send", PAYLOAD)

    stored = db_connection.execute(text("SELECT payload FROM jobs WHERE ulid = :u"), {"u": job.ulid}).scalar_one()
    assert "tenant@example.com" not in stored
    assert "SECRET" not in stored
    assert json.loads(stored)["__enc"].startswith("b64:v1:")
    assert job.payload == PAYLOAD, "the returned Job carries the plaintext payload"


def test_decode_rows_returns_decoded_payloads_for_decodable_rows():
    encryption = Base64Backend()
    repo = SQLAlchemyJobRepository(None, encryption)
    rows = [{"id": 1, "ulid": "A", "payload": encode_job_payload(encryption, PAYLOAD)}]

    assert repo._decode_rows(rows) == [(rows[0], PAYLOAD)]


def test_decode_rows_skips_undecodable_rows_and_keeps_the_rest():
    repo = SQLAlchemyJobRepository(None, _BrokenBackend())
    good = {"id": 1, "ulid": "A", "payload": json.dumps(PAYLOAD)}
    bad = {"id": 2, "ulid": "B", "payload": json.dumps({"__enc": "enc:v1:whatever"})}

    assert repo._decode_rows([good, bad]) == [(good, PAYLOAD)]


def test_decode_rows_returns_empty_when_nothing_can_be_decoded():
    repo = SQLAlchemyJobRepository(None, _BrokenBackend())
    bad = {"id": 2, "ulid": "B", "payload": json.dumps({"__enc": "enc:v1:whatever"})}

    assert repo._decode_rows([bad]) == []


def test_repository_requires_an_encryption_backend():
    with pytest.raises(TypeError):
        SQLAlchemyJobRepository(None)
