from __future__ import annotations

from datetime import datetime

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.pool import StaticPool

from rentivo.constants import SP_TZ
from rentivo.encryption.base64 import Base64Backend
from rentivo.models.communication import Communication, CommunicationTemplate
from rentivo.repositories.sqlalchemy.communication import (
    SQLAlchemyCommunicationRepository,
    SQLAlchemyCommunicationTemplateRepository,
)
from tests.conftest import SCHEMA_DDL


@pytest.fixture()
def conn():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    with engine.connect() as c:
        for stmt in SCHEMA_DDL.strip().split(";"):
            if stmt.strip():
                c.execute(text(stmt))
        c.commit()
        yield c


def test_template_upsert_inserts_then_updates(conn):
    repo = SQLAlchemyCommunicationTemplateRepository(conn, Base64Backend())
    repo.upsert(
        CommunicationTemplate(
            owner_type="billing", owner_id=1, comm_type="bill_ready", subject="S1", body_markdown="B1"
        )
    )
    got = repo.get("billing", 1, "bill_ready")
    assert got is not None and got.subject == "S1" and got.body_markdown == "B1"

    repo.upsert(
        CommunicationTemplate(
            owner_type="billing", owner_id=1, comm_type="bill_ready", subject="S2", body_markdown="B2"
        )
    )
    got2 = repo.get("billing", 1, "bill_ready")
    assert got2.subject == "S2" and got2.body_markdown == "B2"
    n = conn.execute(text("SELECT COUNT(*) FROM communication_templates")).scalar()
    assert n == 1


def test_template_encrypted_at_rest(conn):
    repo = SQLAlchemyCommunicationTemplateRepository(conn, Base64Backend())
    repo.upsert(
        CommunicationTemplate(owner_type="user", owner_id=7, comm_type="bill_ready", subject="Hi", body_markdown="Body")
    )
    raw = conn.execute(text("SELECT subject, body_markdown FROM communication_templates")).fetchone()
    assert raw[0].startswith("b64:v1:") and raw[1].startswith("b64:v1:")


def test_template_get_missing_returns_none(conn):
    repo = SQLAlchemyCommunicationTemplateRepository(conn, Base64Backend())
    assert repo.get("billing", 999, "bill_ready") is None


def test_communication_list_by_bill_empty(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    assert repo.list_by_bill(404) == []


def test_communication_create_list_and_status_transitions(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    comm = repo.create(
        Communication(
            bill_id=5,
            comm_type="bill_ready",
            recipient_name="João",
            recipient_email="joao@example.com",
            subject="Cobrança",
            body_markdown="Prezado João",
        )
    )
    assert comm.id is not None and comm.status == "queued"

    repo.set_job_ulid(comm.id, "01JOBULID0000000000000000")
    repo.mark_sent(comm.id, datetime(2026, 6, 12, 9, 0, tzinfo=SP_TZ))
    listed = repo.list_by_bill(5)
    assert len(listed) == 1
    assert listed[0].status == "sent"
    assert listed[0].recipient_name == "João"
    assert listed[0].job_ulid == "01JOBULID0000000000000000"
    assert listed[0].sent_at is not None
    assert listed[0].subject == "Cobrança"
    assert listed[0].body_markdown == "Prezado João"


def test_communication_create_batch_and_batch_status_updates(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    created = repo.create_batch(
        [
            Communication(
                bill_id=5,
                comm_type="bill_ready",
                recipient_name=name,
                recipient_email=f"{name.lower()}@x.com",
                subject="s",
                body_markdown="b",
            )
            for name in ("Ana", "Bia")
        ]
    )

    ids = [row.id for row in created]
    repo.set_job_ulid_batch(ids, "01JOBULID0000000000000000")
    assert {row.job_ulid for row in repo.list_by_bill(5)} == {"01JOBULID0000000000000000"}

    repo.mark_failed_batch(ids, "queue down")
    rows = repo.list_by_bill(5)
    assert {row.status for row in rows} == {"failed"}
    assert {row.error for row in rows} == {"queue down"}


def test_empty_communication_batches_are_noops(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    assert repo.create_batch([]) == []
    repo.set_job_ulid_batch([], "unused")
    repo.mark_failed_batch([], "unused")
    assert repo.list_by_bill(5) == []


def test_communication_batch_updates_roll_back_if_one_row_fails(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    created = repo.create_batch(
        [
            Communication(
                bill_id=5,
                comm_type="bill_ready",
                recipient_name=name,
                recipient_email=f"{name.lower()}@x.com",
                subject="s",
                body_markdown="b",
            )
            for name in ("Ana", "Bia")
        ]
    )
    ids = [row.id for row in created]
    conn.execute(
        text(
            "CREATE TRIGGER reject_job_ulid BEFORE UPDATE ON communications "
            f"WHEN NEW.id = {ids[1]} AND NEW.job_ulid = 'reject' "
            "BEGIN SELECT RAISE(ABORT, 'job rejected'); END"
        )
    )
    conn.commit()

    with pytest.raises(IntegrityError, match="job rejected"):
        repo.set_job_ulid_batch(ids, "reject")
    assert {row.job_ulid for row in repo.list_by_bill(5)} == {""}

    conn.execute(text("DROP TRIGGER reject_job_ulid"))
    conn.execute(
        text(
            "CREATE TRIGGER reject_failed_status BEFORE UPDATE ON communications "
            f"WHEN NEW.id = {ids[1]} AND NEW.status = 'failed' "
            "BEGIN SELECT RAISE(ABORT, 'status rejected'); END"
        )
    )
    conn.commit()

    with pytest.raises(IntegrityError, match="status rejected"):
        repo.mark_failed_batch(ids, "queue down")
    assert {row.status for row in repo.list_by_bill(5)} == {"queued"}


def test_communication_create_batch_rolls_back_every_row_when_one_insert_fails(conn):
    class TriggerEncryption(Base64Backend):
        def encrypt(self, plaintext: str) -> str:
            if plaintext == "explode@example.com":
                return "reject-this-row"
            return super().encrypt(plaintext)

    conn.execute(
        text(
            "CREATE TRIGGER reject_communication BEFORE INSERT ON communications "
            "WHEN NEW.recipient_email = 'reject-this-row' "
            "BEGIN SELECT RAISE(ABORT, 'rejected'); END"
        )
    )
    conn.commit()
    repo = SQLAlchemyCommunicationRepository(conn, TriggerEncryption())

    with pytest.raises(IntegrityError, match="rejected"):
        repo.create_batch(
            [
                Communication(
                    bill_id=5,
                    comm_type="bill_ready",
                    recipient_name="Ana",
                    recipient_email="ana@example.com",
                    subject="s",
                    body_markdown="b",
                ),
                Communication(
                    bill_id=5,
                    comm_type="bill_ready",
                    recipient_name="Bia",
                    recipient_email="explode@example.com",
                    subject="s",
                    body_markdown="b",
                ),
            ]
        )

    assert conn.execute(text("SELECT COUNT(*) FROM communications")).scalar_one() == 0


def test_communication_mark_failed(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    comm = repo.create(
        Communication(
            bill_id=5,
            comm_type="bill_ready",
            recipient_name="A",
            recipient_email="a@x.com",
            subject="s",
            body_markdown="b",
        )
    )
    repo.mark_failed(comm.id, "smtp boom")
    got = repo.get_by_id(comm.id)
    assert got.status == "failed" and got.error == "smtp boom"


def test_communication_encrypted_at_rest_and_get_by_uuid(conn):
    repo = SQLAlchemyCommunicationRepository(conn, Base64Backend())
    comm = repo.create(
        Communication(
            bill_id=5,
            comm_type="bill_ready",
            recipient_name="João",
            recipient_email="r@x.com",
            subject="s",
            body_markdown="b",
        )
    )
    raw = conn.execute(
        text("SELECT recipient_name, recipient_email, subject, body_markdown FROM communications")
    ).fetchone()
    assert all(v.startswith("b64:v1:") for v in raw)
    assert repo.get_by_uuid(comm.uuid).recipient_name == "João"
    assert repo.get_by_uuid("missing") is None
