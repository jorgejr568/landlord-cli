from __future__ import annotations

from datetime import datetime

from sqlalchemy import Connection, text
from sqlalchemy.engine import RowMapping
from ulid import ULID

from rentivo.encryption.base import EncryptionBackend
from rentivo.models.communication import Communication, CommunicationTemplate
from rentivo.observability import traced
from rentivo.repositories.base import CommunicationRepository, CommunicationTemplateRepository
from rentivo.repositories.sqlalchemy._common import _now, decrypt_columns


class SQLAlchemyCommunicationTemplateRepository(CommunicationTemplateRepository):
    def __init__(self, conn: Connection, encryption: EncryptionBackend) -> None:
        self.conn = conn
        self.encryption = encryption

    def _build(self, row: RowMapping) -> CommunicationTemplate:
        subject, body = self.encryption.decrypt_many([row["subject"] or "", row["body_markdown"] or ""])
        return CommunicationTemplate(
            id=row["id"],
            uuid=row["uuid"],
            owner_type=row["owner_type"],
            owner_id=row["owner_id"],
            comm_type=row["comm_type"],
            subject=subject,
            body_markdown=body,
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    @traced("comm_template_repo.get")
    def get(self, owner_type: str, owner_id: int, comm_type: str) -> CommunicationTemplate | None:
        row = (
            self.conn.execute(
                text(
                    "SELECT * FROM communication_templates "
                    "WHERE owner_type = :ot AND owner_id = :oid AND comm_type = :ct"
                ),
                {"ot": owner_type, "oid": owner_id, "ct": comm_type},
            )
            .mappings()
            .fetchone()
        )
        if row is None:
            return None
        return self._build(row)

    @traced("comm_template_repo.upsert")
    def upsert(self, template: CommunicationTemplate) -> CommunicationTemplate:
        now = _now()
        existing = self.get(template.owner_type, template.owner_id, template.comm_type)
        cipher = {
            "subject": self.encryption.encrypt(template.subject),
            "body": self.encryption.encrypt(template.body_markdown),
        }
        if existing is None:
            uuid = str(ULID())
            self.conn.execute(
                text(
                    "INSERT INTO communication_templates "
                    "(uuid, owner_type, owner_id, comm_type, subject, body_markdown, created_at, updated_at) "
                    "VALUES (:uuid, :ot, :oid, :ct, :subject, :body, :created_at, :updated_at)"
                ),
                {
                    "uuid": uuid,
                    "ot": template.owner_type,
                    "oid": template.owner_id,
                    "ct": template.comm_type,
                    **cipher,
                    "created_at": now,
                    "updated_at": now,
                },
            )
            self.conn.commit()
            return template.model_copy(update={"uuid": uuid, "created_at": now, "updated_at": now})
        self.conn.execute(
            text(
                "UPDATE communication_templates "
                "SET subject = :subject, body_markdown = :body, updated_at = :updated_at "
                "WHERE owner_type = :ot AND owner_id = :oid AND comm_type = :ct"
            ),
            {
                **cipher,
                "updated_at": now,
                "ot": template.owner_type,
                "oid": template.owner_id,
                "ct": template.comm_type,
            },
        )
        self.conn.commit()
        return template.model_copy(
            update={"id": existing.id, "uuid": existing.uuid, "created_at": existing.created_at, "updated_at": now}
        )


class SQLAlchemyCommunicationRepository(CommunicationRepository):
    def __init__(self, conn: Connection, encryption: EncryptionBackend) -> None:
        self.conn = conn
        self.encryption = encryption

    def _build(self, rows: list[RowMapping]) -> list[Communication]:
        if not rows:
            return []
        plaintexts = decrypt_columns(
            self.encryption, rows, ("recipient_name", "recipient_email", "subject", "body_markdown")
        )
        return [
            Communication(
                id=row["id"],
                uuid=row["uuid"],
                bill_id=row["bill_id"],
                comm_type=row["comm_type"],
                recipient_name=next(plaintexts),
                recipient_email=next(plaintexts),
                subject=next(plaintexts),
                body_markdown=next(plaintexts),
                status=row["status"],
                error=row["error"] or "",
                job_ulid=row["job_ulid"] or "",
                created_at=row["created_at"],
                sent_at=row["sent_at"],
            )
            for row in rows
        ]

    @traced("communication_repo.create")
    def create(self, communication: Communication) -> Communication:
        return self.create_batch([communication])[0]

    @traced("communication_repo.create_batch")
    def create_batch(self, communications: list[Communication]) -> list[Communication]:
        if not communications:
            return []
        comm_uuids = [str(ULID()) for _ in communications]
        statement = text(
            "INSERT INTO communications "
            "(uuid, bill_id, comm_type, recipient_name, recipient_email, subject, body_markdown, status, "
            "error, job_ulid, created_at) "
            "VALUES (:uuid, :bill_id, :ct, :name, :email, :subject, :body, :status, :error, :job_ulid, :created_at)"
        )
        try:
            for comm_uuid, communication in zip(comm_uuids, communications, strict=True):
                self.conn.execute(
                    statement,
                    {
                        "uuid": comm_uuid,
                        "bill_id": communication.bill_id,
                        "ct": communication.comm_type,
                        "name": self.encryption.encrypt(communication.recipient_name),
                        "email": self.encryption.encrypt(communication.recipient_email),
                        "subject": self.encryption.encrypt(communication.subject),
                        "body": self.encryption.encrypt(communication.body_markdown),
                        "status": communication.status,
                        "error": communication.error,
                        "job_ulid": communication.job_ulid,
                        "created_at": _now(),
                    },
                )
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise
        created = [self.get_by_uuid(comm_uuid) for comm_uuid in comm_uuids]
        if any(item is None for item in created):  # pragma: no cover - sanity guard
            raise RuntimeError("Failed to retrieve communication batch after create")
        return [item for item in created if item is not None]

    @traced("communication_repo.get_by_id")
    def get_by_id(self, communication_id: int) -> Communication | None:
        row = (
            self.conn.execute(text("SELECT * FROM communications WHERE id = :id"), {"id": communication_id})
            .mappings()
            .fetchone()
        )
        return None if row is None else self._build([row])[0]

    @traced("communication_repo.get_by_uuid")
    def get_by_uuid(self, uuid: str) -> Communication | None:
        row = self.conn.execute(text("SELECT * FROM communications WHERE uuid = :u"), {"u": uuid}).mappings().fetchone()
        return None if row is None else self._build([row])[0]

    @traced("communication_repo.list_by_bill")
    def list_by_bill(self, bill_id: int) -> list[Communication]:
        rows = (
            self.conn.execute(
                text("SELECT * FROM communications WHERE bill_id = :bid ORDER BY created_at DESC, id DESC"),
                {"bid": bill_id},
            )
            .mappings()
            .fetchall()
        )
        return self._build(list(rows))

    @traced("communication_repo.set_job_ulid")
    def set_job_ulid(self, communication_id: int, job_ulid: str) -> None:
        self.set_job_ulid_batch([communication_id], job_ulid)

    @traced("communication_repo.set_job_ulid_batch")
    def set_job_ulid_batch(self, communication_ids: list[int], job_ulid: str) -> None:
        if not communication_ids:
            return
        try:
            for communication_id in communication_ids:
                self.conn.execute(
                    text("UPDATE communications SET job_ulid = :j WHERE id = :id"),
                    {"j": job_ulid, "id": communication_id},
                )
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise

    @traced("communication_repo.mark_sent")
    def mark_sent(self, communication_id: int, sent_at: datetime) -> None:
        self.conn.execute(
            text("UPDATE communications SET status = 'sent', sent_at = :ts, error = '' WHERE id = :id"),
            {"ts": sent_at, "id": communication_id},
        )
        self.conn.commit()

    @traced("communication_repo.mark_failed")
    def mark_failed(self, communication_id: int, error: str) -> None:
        self.mark_failed_batch([communication_id], error)

    @traced("communication_repo.mark_failed_batch")
    def mark_failed_batch(self, communication_ids: list[int], error: str) -> None:
        if not communication_ids:
            return
        try:
            for communication_id in communication_ids:
                self.conn.execute(
                    text("UPDATE communications SET status = 'failed', error = :err WHERE id = :id"),
                    {"err": error, "id": communication_id},
                )
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise
