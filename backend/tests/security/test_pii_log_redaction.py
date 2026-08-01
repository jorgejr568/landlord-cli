"""Regression guards for PII escaping the KMS encryption boundary.

``users.email`` (repositories/sqlalchemy/user.py) and ``billings.name``
(repositories/sqlalchemy/billing.py) are KMS-encrypted at rest, and
``settings.py`` rejects the base64 encryption backend in production. Two sinks
sit outside that boundary and must never receive a plaintext value:

* the structlog pipeline — stdout, plus a CloudWatch log group governed by
  CloudWatch IAM and a separate AWS credential pair (``logging.py``);
* ``audit_logs.previous_state`` / ``new_state`` / ``metadata`` — plain JSON
  columns with no ``EncryptedType`` wrapper (repositories/sqlalchemy/audit_log.py).

A failure here means the boundary masking was weakened. Fix the code, or — if
an exception is genuinely necessary — document it in ``docs/security/`` and
update this guard.
"""

from __future__ import annotations

import re
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from rentivo.logging import _redact_event_dict
from rentivo.pii_redaction import _PII_FIELDS, redact_pii
from rentivo.services.audit_service import AuditService

REPO_ROOT = Path(__file__).resolve().parents[2]

PLAINTEXT_EMAIL = "alice@example.com"
MASKED_EMAIL = "al...@example.com"

# The minimum set every future change must keep. Adding keys is fine; removing
# one is the regression this guard exists to catch.
REQUIRED_PII_KEYS = frozenset(
    {
        "email",
        "to",
        "toemail",
        "recipientemail",
        "invitedemail",
        "invitedbyemail",
        "subject",
        "billingname",
    }
)


def test_required_pii_keys_stay_registered() -> None:
    missing = REQUIRED_PII_KEYS - set(_PII_FIELDS)
    assert not missing, "These keys carry KMS-protected PII and must stay in _PII_FIELDS: " + ", ".join(sorted(missing))


@pytest.mark.parametrize("field", sorted(REQUIRED_PII_KEYS))
def test_logging_processor_masks_every_known_pii_key(field: str) -> None:
    """The processor is the single chokepoint for stdout and CloudWatch alike."""
    event_dict = _redact_event_dict(None, "info", {"event": "probe", field: PLAINTEXT_EMAIL})

    assert event_dict[field] != PLAINTEXT_EMAIL
    assert PLAINTEXT_EMAIL not in repr(event_dict)
    assert event_dict["event"] == "probe"


def test_logging_processor_masks_pii_nested_in_containers() -> None:
    event_dict = _redact_event_dict(
        None,
        "info",
        {"payload": {"recipients": [{"email": PLAINTEXT_EMAIL}]}, "pair": ({"to": PLAINTEXT_EMAIL},)},
    )

    assert PLAINTEXT_EMAIL not in repr(event_dict)
    assert event_dict["payload"] == {"recipients": [{"email": MASKED_EMAIL}]}
    assert event_dict["pair"] == ({"to": MASKED_EMAIL},)


def test_logging_processor_preserves_correlation_identifiers() -> None:
    """Masking must not degrade observability — non-PII keys pass through."""
    safe = {
        "event": "email_ses_sent",
        "request_id": "request-123",
        "user_id": 7,
        "message_id": "ses-message-1",
        "api_key_uuid": "01SAFEKEYUUID",
        "bill_id": 42,
        "org_id": 3,
        "reason": "invalid_password",
    }

    assert _redact_event_dict(None, "info", dict(safe)) == safe


@pytest.mark.parametrize("state_field", ["previous_state", "new_state", "metadata"])
def test_audit_state_columns_never_persist_a_plaintext_email(state_field: str) -> None:
    repo = MagicMock()
    repo.create.side_effect = lambda log: log
    service = AuditService(repo)

    result = service.log("user.login", **{state_field: {"email": PLAINTEXT_EMAIL}})

    assert getattr(result, state_field) == {"email": MASKED_EMAIL}
    assert PLAINTEXT_EMAIL not in repr(repo.create.call_args)


def test_redact_pii_masks_the_encrypted_billing_name() -> None:
    """billings.name is an encrypted column; it reaches logs as billing_name
    (services/bill_service.py) and templates substitute it into subjects."""
    masked = redact_pii({"billing_name": "Apto 101 - Maria Silva", "subject": "Fatura de julho - Apto 101"})

    assert masked == {"billing_name": "Apt...va", "subject": "Fat...01"}


_BIND_EMAIL_RE = re.compile(r"bind_contextvars\((?:[^()]|\([^()]*\))*?\bemail\s*=", re.DOTALL)


def test_no_plaintext_email_bound_into_request_contextvars() -> None:
    """structlog contextvars are cleared only at request start/end (api/app.py),
    so anything bound there rides on every log line of the whole request.
    user_id is bound alongside and identifies the user without the address."""
    offenders: list[str] = []
    for path in (REPO_ROOT / "rentivo").rglob("*.py"):
        if "__pycache__" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        for match in _BIND_EMAIL_RE.finditer(text):
            lineno = text.count("\n", 0, match.start()) + 1
            offenders.append(f"{path.relative_to(REPO_ROOT)}:{lineno}")
    assert not offenders, (
        "email=<plaintext> must not be bound into structlog contextvars — bind user_id instead\n" + "\n".join(offenders)
    )
