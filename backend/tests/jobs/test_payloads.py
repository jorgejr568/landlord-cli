"""Payload decoding for every job type.

These go through ``registry.dispatch`` rather than the models directly, because
what matters is not only that a bad payload is rejected but that it is rejected
as a ``PermanentJobError`` — the verdict that dead-letters the job instead of
retrying it five times against the same broken input.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from rentivo.jobs import (
    handlers,  # noqa: F401 — registers every handler
    registry,
)
from rentivo.jobs.base import JobContext, PermanentJobError
from rentivo.jobs.payloads import (
    AuthCleanupPayload,
    CommunicationSendPayload,
    EmailSendPayload,
    ExportGeneratePayload,
    ExportSendPayload,
    PdfRenderPayload,
    ReciboRenderPayload,
    S3DeletePayload,
)
from rentivo.jobs.temporal.registry import JOB_TYPES

CONTEXT = JobContext(ulid="01ARZ3NDEKTSV4RRFFQ69G5FAV", attempts=1)

VALID_EXPORT_SEND = {
    "billing_id": 1,
    "requested_by_user_id": 2,
    "storage_key": "UUID/exports/abc.csv",
    "content_type": "text/csv",
}


def _decode(job_type: str, payload: dict):
    """Run the registry decode for ``job_type`` and return what a handler would
    have been given, without running the real handler's side effects."""
    seen = []

    def stub(decoded, context):
        seen.append(decoded)

    setattr(stub, registry._MODEL_ATTR, _model_of(job_type))
    registry.dispatch(job_type, stub, payload, CONTEXT)
    return seen[0]


def _model_of(job_type: str):
    handler = registry.get(job_type)
    assert handler is not None, job_type
    return registry.payload_model(handler)


def _reject(job_type: str, payload: dict):
    handler = registry.get(job_type)
    assert handler is not None
    with pytest.raises(PermanentJobError, match=f"invalid {job_type} payload") as exc:
        registry.dispatch(job_type, handler, payload, CONTEXT)
    return exc


def test_every_job_type_has_a_payload_model():
    for job_type in JOB_TYPES:
        handler = registry.get(job_type)
        assert handler is not None, job_type
        assert registry.payload_model(handler) is not None, job_type


def test_transport_keys_are_ignored():
    """Live payloads carry the trace carrier, and jobs queued before job identity
    moved into JobContext still carry ``_job_ulid``. Neither is a payload field."""
    decoded = _decode("pdf.render", {"bill_id": 42, "_otel": {"traceparent": "x"}, "_job_ulid": "01OLD"})
    assert decoded == PdfRenderPayload(bill_id=42)


@pytest.mark.parametrize(
    ("job_type", "payload", "expected"),
    [
        (
            "email.send",
            {"event": "welcome", "to_email": "a@example.com", "ctx": {"email": "a@example.com"}},
            EmailSendPayload(event="welcome", to_email="a@example.com", ctx={"email": "a@example.com"}),
        ),
        (
            "email.send",
            {"event": "welcome", "to_email": "a@example.com"},
            EmailSendPayload(event="welcome", to_email="a@example.com", ctx={}),
        ),
        ("communication.send", {"communication_id": 5}, CommunicationSendPayload(communication_id=5)),
        (
            "communication.send",
            {"communication_ids": [5, 6]},
            CommunicationSendPayload(communication_ids=[5, 6]),
        ),
        ("pdf.render", {"bill_id": 42}, PdfRenderPayload(bill_id=42)),
        (
            "pdf.render",
            {"bill_id": 42, "render_operation_id": "01OP", "receipt_cleanup": {"uuid": "u", "storage_key": "k"}},
            PdfRenderPayload.model_validate(
                {"bill_id": 42, "render_operation_id": "01OP", "receipt_cleanup": {"uuid": "u", "storage_key": "k"}}
            ),
        ),
        ("recibo.render", {"bill_id": 42}, ReciboRenderPayload(bill_id=42)),
        ("s3.delete", {"key": "k"}, S3DeletePayload(key="k")),
        ("s3.delete", {}, S3DeletePayload(key="")),
        (
            "export.generate",
            {"billing_id": 1, "requested_by_user_id": 2, "format": "xlsx"},
            ExportGeneratePayload(billing_id=1, requested_by_user_id=2, format="xlsx"),
        ),
        (
            "export.generate",
            {"billing_id": 1, "requested_by_user_id": 2},
            ExportGeneratePayload(billing_id=1, requested_by_user_id=2, format="csv"),
        ),
        (
            "export.send",
            VALID_EXPORT_SEND,
            ExportSendPayload(
                billing_id=1,
                requested_by_user_id=2,
                storage_key="UUID/exports/abc.csv",
                content_type="text/csv",
                format="csv",
                bill_count=0,
            ),
        ),
        ("auth.cleanup", {}, AuthCleanupPayload(now=None)),
        (
            "auth.cleanup",
            {"now": "2026-07-17T12:00:00Z"},
            AuthCleanupPayload(now=datetime(2026, 7, 17, 12, 0, tzinfo=UTC)),
        ),
    ],
)
def test_valid_payloads_decode(job_type, payload, expected):
    assert _decode(job_type, payload) == expected


@pytest.mark.parametrize(
    ("job_type", "payload"),
    [
        # email.send
        ("email.send", {"to_email": "a@example.com"}),
        ("email.send", {"event": "welcome"}),
        ("email.send", {"event": 1, "to_email": "a@example.com"}),
        ("email.send", {"event": "welcome", "to_email": "a@example.com", "ctx": "nope"}),
        # communication.send
        ("communication.send", {}),
        ("communication.send", {"communication_id": "x"}),
        ("communication.send", {"communication_ids": []}),
        ("communication.send", {"communication_ids": [5, "6"]}),
        ("communication.send", {"communication_ids": [5, 5]}),
        ("communication.send", {"communication_id": 5, "communication_ids": [6]}),
        # pdf.render
        ("pdf.render", {}),
        ("pdf.render", {"bill_id": "42"}),
        ("pdf.render", {"bill_id": 42, "render_operation_id": 7}),
        ("pdf.render", {"bill_id": 42, "render_operation_id": "01OP", "receipt_cleanup": "receipt"}),
        ("pdf.render", {"bill_id": 42, "render_operation_id": "01OP", "receipt_cleanup": {}}),
        (
            "pdf.render",
            {"bill_id": 42, "render_operation_id": "01OP", "receipt_cleanup": {"uuid": 7, "storage_key": "k"}},
        ),
        (
            "pdf.render",
            {"bill_id": 42, "render_operation_id": "01OP", "receipt_cleanup": {"uuid": "u", "storage_key": 7}},
        ),
        # recibo.render
        ("recibo.render", {}),
        ("recibo.render", {"bill_id": "42"}),
        ("recibo.render", {"bill_id": 42, "render_operation_id": 7}),
        # s3.delete
        ("s3.delete", {"key": 7}),
        # export.generate
        ("export.generate", {"requested_by_user_id": 2}),
        ("export.generate", {"billing_id": "x", "requested_by_user_id": 2}),
        ("export.generate", {"billing_id": 1, "requested_by_user_id": "bad"}),
        # export.send
        ("export.send", {**VALID_EXPORT_SEND, "storage_key": None}),
        ("export.send", {k: v for k, v in VALID_EXPORT_SEND.items() if k != "storage_key"}),
        ("export.send", {k: v for k, v in VALID_EXPORT_SEND.items() if k != "content_type"}),
        ("export.send", {**VALID_EXPORT_SEND, "bill_count": "3"}),
        # auth.cleanup
        ("auth.cleanup", {"now": 123}),
        ("auth.cleanup", {"now": "not-a-timestamp"}),
        ("auth.cleanup", {"now": "2026-07-17T12:00:00"}),
        ("auth.cleanup", {"now": "1700000000"}),
        ("auth.cleanup", {"now": "1700000000.5"}),
        ("auth.cleanup", {"now": "-1700000000"}),
    ],
)
def test_invalid_payloads_dead_letter(job_type, payload):
    _reject(job_type, payload)


def test_receipt_cleanup_requires_a_render_operation():
    """The cleanup is guarded against the bill's current render operation, so a
    payload without one could never make the guard decision."""
    exc = _reject(
        "pdf.render",
        {"bill_id": 42, "receipt_cleanup": {"uuid": "receipt-uuid", "storage_key": "receipts/file.pdf"}},
    )
    # The model validator rejects the payload as a whole, so the failure is
    # reported against the payload rather than a single field.
    assert str(exc.value) == "invalid pdf.render payload: <payload>: value_error"


def test_timestamps_must_be_rfc_3339_text():
    """A bare number would otherwise be read as a Unix timestamp."""
    exc = _reject("auth.cleanup", {"now": 1_000_000})
    assert str(exc.value) == "invalid auth.cleanup payload: now: value_error"


def test_numeric_text_is_not_accepted_as_a_timestamp():
    """Lax parsing reads ``"1700000000"`` as a Unix epoch just as it reads the
    bare number, inventing a cutoff from what is really a producer bug."""
    _reject("auth.cleanup", {"now": "1700000000"})
    _reject("auth.cleanup", {"now": "1700000000.5"})

    # Real RFC 3339 text is unaffected.
    assert _decode("auth.cleanup", {"now": "2026-07-17T12:00:00Z"}) == AuthCleanupPayload(
        now=datetime(2026, 7, 17, 12, 0, tzinfo=UTC)
    )


def test_a_decode_failure_never_echoes_the_payload():
    """Job failure messages reach the job row, the audit trail and the logs
    unredacted, so no payload value may appear in them."""
    sentinel = "SECRET-TOKEN@example.com"
    exc = _reject("email.send", {"to_email": sentinel})

    assert sentinel not in str(exc.value)
    assert str(exc.value) == "invalid email.send payload: event: missing"


def test_payloads_are_frozen():
    payload = PdfRenderPayload(bill_id=42)
    with pytest.raises(ValueError):
        payload.bill_id = 7
