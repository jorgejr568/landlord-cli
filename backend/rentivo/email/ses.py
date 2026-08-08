from __future__ import annotations

import structlog

from rentivo.aws import build_client
from rentivo.email.base import EmailBackend, EmailMessage
from rentivo.email.mime import build_mime
from rentivo.observability import traced

logger = structlog.get_logger(__name__)


class SESEmailBackend(EmailBackend):
    def __init__(
        self,
        region: str,
        access_key_id: str,
        secret_access_key: str,
        from_address: str,
        endpoint_url: str = "",
        configuration_set: str = "",
    ) -> None:
        self.from_address = from_address
        self.configuration_set = configuration_set
        self.client = build_client(
            "ses",
            region=region,
            access_key_id=access_key_id,
            secret_access_key=secret_access_key,
            endpoint_url=endpoint_url,
            feature="SES email",
        )

    @traced("ses.send")
    def send(self, message: EmailMessage) -> str:
        if message.attachments:
            raw = build_mime(message).as_bytes()
            raw_kwargs = {
                "Source": message.from_address or self.from_address,
                "Destinations": [message.to],
                "RawMessage": {"Data": raw},
            }
            if self.configuration_set:
                raw_kwargs["ConfigurationSetName"] = self.configuration_set
            response = self.client.send_raw_email(**raw_kwargs)
            message_id = response.get("MessageId", "")
            # `subject` is template-substituted and carries the tenant name and
            # the encrypted billing name. It is registered in
            # pii_redaction._PII_FIELDS, so the structlog processor chain masks
            # it before any renderer or exporter sees the event; the masked form
            # still identifies which billing cycle the message belongs to.
            logger.info("email_ses_sent_raw", to=message.to, subject=message.subject, message_id=message_id)
            return message_id

        kwargs = {
            "Source": message.from_address or self.from_address,
            "Destination": {"ToAddresses": [message.to]},
            "Message": {
                "Subject": {"Data": message.subject, "Charset": "UTF-8"},
                "Body": {
                    "Text": {"Data": message.text_body, "Charset": "UTF-8"},
                    "Html": {"Data": message.html_body, "Charset": "UTF-8"},
                },
            },
        }
        if self.configuration_set:
            kwargs["ConfigurationSetName"] = self.configuration_set
        if message.reply_to:
            kwargs["ReplyToAddresses"] = list(message.reply_to)
        response = self.client.send_email(**kwargs)
        message_id = response.get("MessageId", "")
        logger.info("email_ses_sent", to=message.to, subject=message.subject, message_id=message_id)
        return message_id
