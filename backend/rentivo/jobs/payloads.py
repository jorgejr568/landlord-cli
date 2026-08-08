"""Typed job payloads — one frozen model per job type.

These models describe the *consumer* side of the queue contract. Producers keep
enqueuing plain dicts and the on-disk wire format is unchanged; the registry
decodes the stored dict into the model for this job type before calling the
handler, and turns any validation failure into a ``PermanentJobError`` so a
structurally broken payload dead-letters instead of burning every retry.

Two rules keep the decode faithful to the hand-rolled ``isinstance`` checks it
replaces:

* Validation is strict, so ``{"bill_id": "42"}`` is rejected rather than
  coerced — a string bill id is a producer bug, not a value to guess at.
* Unknown keys are ignored, because live payloads also carry transport keys
  (the ``_otel`` trace carrier, and ``_job_ulid`` on jobs queued before job
  identity moved into ``JobContext``).

Fields that are optional today stay optional: payloads queued by an older
release must still validate.
"""

from __future__ import annotations

import re
from datetime import datetime
from typing import Annotated

from pydantic import AwareDatetime, BaseModel, BeforeValidator, ConfigDict, Field, model_validator


class JobPayload(BaseModel):
    """Base for every job payload: immutable, strict, tolerant of extra keys."""

    model_config = ConfigDict(frozen=True, strict=True, extra="ignore")


_NUMERIC_TEXT = re.compile(r"-?\d+(\.\d+)?")


def _reject_numeric_timestamp(value: object) -> object:
    """Keep the timestamp field to RFC 3339 text (or an actual datetime).

    Without this, lax parsing would read a bare number as a Unix timestamp; the
    queue contract is a string, and a number means a broken producer. Numeric
    *text* (``"1700000000"``) is rejected for the same reason — lax parsing
    treats it as an epoch too, so letting it through would silently invent a
    timestamp out of a producer bug.
    """
    if isinstance(value, datetime):
        return value
    if isinstance(value, str) and not _NUMERIC_TEXT.fullmatch(value):
        return value
    raise ValueError("must be an RFC 3339 UTC timestamp")


# Parsed leniently (the wire value is text) but still required to carry an
# offset: a naive timestamp would silently shift a cutoff by the local offset.
Rfc3339Timestamp = Annotated[AwareDatetime, BeforeValidator(_reject_numeric_timestamp), Field(strict=False)]


class EmailSendPayload(JobPayload):
    event: str
    to_email: str
    ctx: dict = Field(default_factory=dict)


class CommunicationSendPayload(JobPayload):
    communication_id: int


class ReceiptCleanup(JobPayload):
    """A superseded receipt whose stored object the render job must remove."""

    uuid: str
    storage_key: str


class PdfRenderPayload(JobPayload):
    bill_id: int
    render_operation_id: str | None = None
    receipt_cleanup: ReceiptCleanup | None = None

    @model_validator(mode="after")
    def _cleanup_requires_render_operation(self) -> PdfRenderPayload:
        """The cleanup is guarded against the bill's current render operation,
        so it is meaningless without one to compare against."""
        if self.receipt_cleanup is not None and self.render_operation_id is None:
            raise ValueError("receipt_cleanup requires render_operation_id")
        return self


class ReciboRenderPayload(JobPayload):
    bill_id: int
    render_operation_id: str | None = None


class S3DeletePayload(JobPayload):
    key: str = ""


class ExportGeneratePayload(JobPayload):
    billing_id: int
    requested_by_user_id: int
    format: str = "csv"


class ExportSendPayload(JobPayload):
    billing_id: int
    requested_by_user_id: int
    storage_key: str
    content_type: str
    format: str = "csv"
    bill_count: int = 0


class AuthCleanupPayload(JobPayload):
    now: Rfc3339Timestamp | None = None
