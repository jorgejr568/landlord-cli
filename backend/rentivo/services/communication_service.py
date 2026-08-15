from __future__ import annotations

import structlog

from rentivo.communications.defaults import system_default_template
from rentivo.communications.render import month_long, substitute
from rentivo.models import format_brl
from rentivo.models.bill import Bill
from rentivo.models.billing import Billing
from rentivo.models.communication import CommType, Communication, CommunicationTemplate
from rentivo.models.recipient import Recipient
from rentivo.observability import traced
from rentivo.repositories.base import CommunicationRepository, CommunicationTemplateRepository
from rentivo.services.job_service import JobService

logger = structlog.get_logger(__name__)


class CommunicationService:
    def __init__(
        self,
        communication_repo: CommunicationRepository,
        template_repo: CommunicationTemplateRepository,
        job_service: JobService,
    ) -> None:
        self.communication_repo = communication_repo
        self.template_repo = template_repo
        self.job_service = job_service

    # ---- templates ----

    @traced("communication.resolve_template")
    def resolve_template(self, billing: Billing, comm_type: str) -> CommunicationTemplate:
        """Most-specific-wins: billing -> billing owner (user/org) -> system default."""
        billing_tmpl = self.template_repo.get("billing", billing.id, comm_type)
        if billing_tmpl is not None:
            return billing_tmpl
        owner_tmpl = self.template_repo.get(billing.owner_type, billing.owner_id, comm_type)
        if owner_tmpl is not None:
            return owner_tmpl
        return system_default_template(comm_type)

    @traced("communication.save_template")
    def save_template(
        self, owner_type: str, owner_id: int, comm_type: str, subject: str, body_markdown: str
    ) -> CommunicationTemplate:
        return self.template_repo.upsert(
            CommunicationTemplate(
                owner_type=owner_type,
                owner_id=owner_id,
                comm_type=comm_type,
                subject=subject,
                body_markdown=body_markdown,
            )
        )

    # ---- sending ----

    @staticmethod
    def _context(bill: Bill, billing: Billing, recipient: Recipient) -> dict[str, str]:
        return {
            "nome_inquilino": recipient.name,
            "unidade": billing.name,
            "mes": month_long(bill.reference_month),
            "vencimento": bill.due_date or "",
            "total": format_brl(bill.total_amount),
        }

    @traced("communication.send")
    def send(
        self,
        bill: Bill,
        billing: Billing,
        recipients: list[Recipient],
        subject_template: str,
        body_template: str,
        actor=None,
        comm_type: str = CommType.BILL_READY.value,
    ) -> list[Communication]:
        """Create all recipient rows atomically and enqueue one idempotent batch job.

        ``comm_type`` selects which document the send job attaches: ``bill_ready``
        attaches the invoice PDF, ``payment_receipt`` the stored recibo PDF.
        """
        pending: list[Communication] = []
        for recipient in recipients:
            ctx = self._context(bill, billing, recipient)
            pending.append(
                Communication(
                    bill_id=bill.id,
                    comm_type=comm_type,
                    recipient_name=recipient.name,
                    recipient_email=recipient.email,
                    subject=substitute(subject_template, ctx),
                    body_markdown=substitute(body_template, ctx),
                )
            )
        if not pending:
            return []
        results = self.communication_repo.create_batch(pending)
        communication_ids = [comm.id for comm in results]
        try:
            job = self.job_service.enqueue_for(
                actor, "communication.send", {"communication_ids": communication_ids}, max_attempts=3
            )
        except Exception:
            self.communication_repo.mark_failed_batch(communication_ids, "Falha ao enfileirar o envio.")
            logger.exception("communication_batch_enqueue_failed", communication_ids=communication_ids)
            raise
        self.communication_repo.set_job_ulid_batch(communication_ids, job.ulid)
        for comm in results:
            comm.job_ulid = job.ulid
        logger.info("communications_enqueued", bill_id=bill.id, count=len(results))
        return results

    @traced("communication.list_for_bill")
    def list_for_bill(self, bill_id: int) -> list[Communication]:
        return self.communication_repo.list_by_bill(bill_id)
