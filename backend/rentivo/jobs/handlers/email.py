from __future__ import annotations

from email.utils import formataddr

from jinja2 import TemplateError, TemplateNotFound

from rentivo.email.factory import get_email_backend
from rentivo.jobs.base import JobContext, PermanentJobError
from rentivo.jobs.payloads import EmailSendPayload
from rentivo.jobs.registry import register
from rentivo.services.email_service import EmailService
from rentivo.settings import settings


@register("email.send", model=EmailSendPayload)
def handle_email_send(payload: EmailSendPayload, context: JobContext) -> None:
    backend = get_email_backend()
    service = EmailService(
        backend,
        from_address=formataddr((settings.ses_from_name, settings.ses_from_email or "noreply@localhost")),
    )
    try:
        service.send(payload.to_email, payload.event, payload.ctx)
    except KeyError as exc:
        raise PermanentJobError(f"unknown email event: {exc}") from exc
    except (TemplateNotFound, TemplateError) as exc:
        raise PermanentJobError(f"template error: {exc}") from exc
