"""Partial-mask redaction for PII values in audit logs and similar contexts.

NOT encryption. The mask is a one-way, key-less, partial disclosure: it keeps
enough of the value for an operator to recognize "the mail went to a gmail
address" or "the CPF starts with 123 and ends with 89" without revealing the
full identifier.

Three shapes, selected by :class:`PIIKind`:

* ``EMAIL`` — first + ``****`` + last char of the local part, domain kept whole.
* ``TEXT``  — first 4 + ``****`` + last 4 characters.
* ``PIX``   — classify the key type (CPF / CNPJ / email / phone / EVP) and mask
  per type, falling back to ``TEXT`` for anything unrecognized.

Two invariants the tests pin down:

1. **Asterisk runs never encode length.** Every run over a variable-length input
   is exactly four characters. CPF, CNPJ and EVP masks keep their canonical
   punctuation instead, because those formats have a constant length and so
   disclose nothing by being format-preserving.
2. **Every shape is a one-step fixed point** — ``mask(mask(x)) == mask(x)``.
   ``services/audit_serializers.py`` masks a value and then ``AuditService.log``
   masks the same dict again, so double-masking genuinely happens in production;
   a shape that grew on each pass would produce unbounded asterisk runs.

Known trade-off: keeping the full email domain is deliberate. On a small
corporate domain, first char + last char + domain can narrow the candidate set
considerably. The mask stays non-reversible and is strictly better than the
plaintext it replaces, but it is partial disclosure, not anonymization.
"""

from __future__ import annotations

import re
from enum import Enum
from typing import Any, overload

from rentivo.pix_keys import classify_pix_key

_MASK = "****"
# Every mask shape emits at least one run of three asterisks, so a PIX value
# containing one is already one of our own masks. See _mask_pix.
_MASK_RUN = "***"
# Local parts of two characters or fewer mask entirely: first+last would
# reproduce the whole local part.
_EMAIL_LOCAL_MIN_VISIBLE = 2
_TEXT_PREFIX = 4
_TEXT_SUFFIX = 4
# Below this, first-4 + last-4 would reveal all but a character or two. Twelve
# keeps at least four characters hidden and is exactly the length of a masked
# value, which is what makes _mask_text a one-step fixed point.
_TEXT_MIN_LEN = _TEXT_PREFIX + _TEXT_SUFFIX + 4


class PIIKind(str, Enum):
    """Discriminator that selects the partial-mask shape for ``redact()``."""

    PIX = "pix"
    EMAIL = "email"
    TEXT = "text"


_CREDENTIAL_FIELDS = frozenset(
    {
        "accesstoken",
        "apikey",
        "apikeyhash",
        "apikeysecret",
        "assertion",
        "attestationobject",
        "authenticationtoken",
        "accesscredential",
        "authenticatordata",
        "authorization",
        "authorizationcode",
        "bearertoken",
        "challenge",
        "challengehash",
        "challengetoken",
        "clientsecret",
        "clientdatajson",
        "cookie",
        "credential",
        "credentialhash",
        "credentialsecret",
        "csrf",
        "csrftoken",
        "currentpassword",
        "codeverifier",
        "logintoken",
        "mfacode",
        "newpassword",
        "nonce",
        "noncehash",
        "idtoken",
        "oauthcode",
        "oauthtoken",
        "oldpassword",
        "password",
        "passwordconfirm",
        "passwordconfirmation",
        "passwordhash",
        "passwordresettoken",
        "rawid",
        "recoverycode",
        "recoverycodes",
        "refreshtoken",
        "resettoken",
        "secret",
        "secrethash",
        "secretkey",
        "sessiontoken",
        "setcookie",
        "signature",
        "totp",
        "totpcode",
        "totpsecret",
        "userhandle",
        "verificationtoken",
        "awssecretaccesskey",
    }
)

# Keys whose values are PII rather than credentials: they must be partially
# masked, not blanked, so logs stay useful. Keys are ``_normalize_field``
# normalized, so ``to_email`` / ``toEmail`` / ``To-Email`` all match.
#
# Why these must never appear in cleartext outside the process: ``users.email``
# and ``billings.name`` are KMS-encrypted at rest (repositories/sqlalchemy/
# user.py, billing.py) and production rejects the base64 encryption backend
# (settings.py). stdout and the CloudWatch log group are governed by different
# IAM than the KMS key policy, and audit_logs.new_state is a plain JSON column
# with no EncryptedType wrapper — so a plaintext value in any of those places
# defeats the encryption boundary entirely.
_PII_FIELDS: dict[str, PIIKind] = {
    "actorusername": PIIKind.EMAIL,
    "billingname": PIIKind.TEXT,
    "email": PIIKind.EMAIL,
    "invitedbyemail": PIIKind.EMAIL,
    "invitedemail": PIIKind.EMAIL,
    "pixkey": PIIKind.PIX,
    "pixmerchantcity": PIIKind.TEXT,
    "pixmerchantname": PIIKind.TEXT,
    "recipientemail": PIIKind.EMAIL,
    "subject": PIIKind.TEXT,
    "to": PIIKind.EMAIL,
    "toemail": PIIKind.EMAIL,
}
_REDACTED = "[REDACTED]"
_API_KEY_PATTERN = re.compile(r"rntv-v1-[A-Za-z0-9_-]{12,}")
_BEARER_PATTERN = re.compile(r"(?i)(\bbearer\s+)(?P<value>\[REDACTED\]|[^\s,;\"')\]}]+)")
_COOKIE_HEADER_PATTERN = re.compile(r"(?i)(\b(?:set-cookie|cookie)\s*:\s*)[^\r\n]+")
_CREDENTIAL_ASSIGNMENT_PATTERN = re.compile(
    r"(?P<prefix>\b(?P<field>[A-Za-z][A-Za-z0-9_.-]{1,63})\s*[:=]\s*)"
    r"(?P<value>\[REDACTED\]|\"[^\"]*\"|'[^']*'|[^\s,;\"')\]}]+)"
)
_HEADER_FIELDS = frozenset({"authorization", "cookie", "setcookie"})


@overload
def redact(value: str, kind: PIIKind) -> str: ...


@overload
def redact(value: Any, kind: None = None) -> Any: ...


def redact(value: Any, kind: PIIKind | None = None) -> Any:
    """Return a partially-masked view of ``value`` suitable for audit logs.

    Empty / falsy input returns ``""`` so audit consumers can distinguish
    "value not set" from "value present but masked".
    """
    if kind is None:
        return _redact_credentials(value)
    if not value:
        return ""
    if kind is PIIKind.PIX:
        return _mask_pix(value)
    if kind is PIIKind.EMAIL:
        return _mask_email(value)
    if kind is PIIKind.TEXT:
        return _mask_text(value)
    raise ValueError(f"Unknown PII kind: {kind}")


def redact_pii(value: Any) -> Any:
    """``redact()`` plus partial-masking of every known-PII key.

    Use this at boundaries where an entire event or state dict is serialized
    somewhere outside the KMS encryption boundary — the structlog processor
    chain (stdout + CloudWatch) and ``AuditService.log`` (the unencrypted
    ``audit_logs`` JSON columns). Masking at the boundary rather than at each
    call site means a new ``logger.info(..., email=...)`` cannot reintroduce
    the leak.

    Credential fields still blank to ``[REDACTED]``; PII fields keep a
    partial mask so logs remain operationally useful.
    """
    return _redact_credentials(value, mask_pii=True)


def _redact_credentials(value: Any, *, mask_pii: bool = False) -> Any:
    if isinstance(value, dict):
        return {key: _redact_mapping_item(key, item, mask_pii=mask_pii) for key, item in value.items()}
    if isinstance(value, list):
        return [_redact_credentials(item, mask_pii=mask_pii) for item in value]
    if isinstance(value, tuple):
        return tuple(_redact_credentials(item, mask_pii=mask_pii) for item in value)
    if isinstance(value, str):
        if _API_KEY_PATTERN.search(value):
            return _REDACTED
        return _redact_credential_string(value)
    return value


def _redact_mapping_item(key: Any, value: Any, *, mask_pii: bool) -> Any:
    """Credential fields win over PII fields: blanking is stricter than masking."""
    normalized = _normalize_field(key)
    if normalized in _CREDENTIAL_FIELDS:
        return _REDACTED
    if mask_pii and normalized in _PII_FIELDS:
        return _mask_pii_value(value, _PII_FIELDS[normalized])
    return _redact_credentials(value, mask_pii=mask_pii)


def _mask_pii_value(value: Any, kind: PIIKind) -> Any:
    """Apply the ``kind`` partial mask to every string beneath a PII key.

    Non-string scalars (ids, counts, ``None``, booleans) pass through with
    their type intact so correlation identifiers are not degraded.
    """
    if isinstance(value, str):
        return redact(value, kind)
    if isinstance(value, dict):
        return {key: _mask_pii_value(item, kind) for key, item in value.items()}
    if isinstance(value, list):
        return [_mask_pii_value(item, kind) for item in value]
    if isinstance(value, tuple):
        return tuple(_mask_pii_value(item, kind) for item in value)
    return value


def _redact_credential_string(value: str) -> str:
    value = _COOKIE_HEADER_PATTERN.sub(lambda match: f"{match.group(1)}{_REDACTED}", value)
    value = _BEARER_PATTERN.sub(lambda match: f"{match.group(1)}{_REDACTED}", value)

    def replace_assignment(match: re.Match[str]) -> str:
        field = _normalize_field(match.group("field"))
        assigned_value = match.group("value")
        if field not in _CREDENTIAL_FIELDS or field in _HEADER_FIELDS:
            return f"{match.group('prefix')}{_redact_credential_string(assigned_value)}"
        if assigned_value == _REDACTED:
            return match.group(0)
        return f"{match.group('prefix')}{_REDACTED}"

    return _CREDENTIAL_ASSIGNMENT_PATTERN.sub(replace_assignment, value)


def _normalize_field(field: Any) -> str:
    return "".join(character for character in str(field).casefold() if character.isalnum())


def _is_all_asterisks(value: str) -> bool:
    return value.count("*") == len(value)


def _mask_text(value: str) -> str:
    """First 4 chars + ``****`` + last 4 chars. Short values mask entirely.

    Idempotent by construction, with no already-masked guard: the output is
    either ``****`` (4 chars, below the threshold, so it maps to itself) or
    exactly 12 chars whose first 4 and last 4 are the input's own first 4 and
    last 4. Because this shape needs no guard, an attacker-supplied billing
    name or subject cannot slip through by embedding asterisks.

    Examples::

        Fatura de julho - Apto 101 -> Fatu**** 101
        Apto 101 - Maria Silva     -> Apto****ilva
        Sao Paulo                  -> ****   (9 chars; would hide only one)
    """
    if len(value) < _TEXT_MIN_LEN:
        return _MASK
    return f"{value[:_TEXT_PREFIX]}{_MASK}{value[-_TEXT_SUFFIX:]}"


def _mask_email(value: str) -> str:
    """First + ``****`` + last char of the local part; full domain preserved.

    Keeping the domain is a deliberate trade-off: it preserves the operational
    signal (which mail provider, which corporate tenant) at the cost of
    narrowing the candidate set on small domains. Values with no ``@`` fall
    back to the free-text mask.

    Examples::

        alphakebab@gmail.com -> a****b@gmail.com
        ab@x.co              -> ****@x.co      (local part <= 2 chars)
        not-an-email         -> not-****mail   (free-text fallback)
    """
    if "@" not in value:
        return _mask_text(value)
    local, _, domain = value.partition("@")
    if len(local) <= _EMAIL_LOCAL_MIN_VISIBLE:
        return f"{_MASK}@{domain}"
    masked_local = f"{local[0]}{_MASK}{local[-1]}"
    # An already-masked local part would otherwise grow by two characters on
    # every pass. Collapsing it keeps the mask a one-step fixed point, and an
    # all-asterisk local part carries nothing worth protecting.
    if _is_all_asterisks(masked_local):
        masked_local = _MASK
    return f"{masked_local}@{domain}"


def _mask_pix(value: str) -> str:
    """Classify the PIX key type first, then mask per type.

    CPF, CNPJ and EVP keep their canonical punctuation: those formats have a
    constant length, so a format-preserving mask discloses nothing extra. The
    phone mask uses the fixed-width run instead, because a BR phone key carries
    10 *or* 11 digits and a proportional run would reveal which. The EVP mask
    reveals only the first hex group and the last 4 characters — the first
    group is already effectively unique, so revealing more adds no triage
    value for real identifiability cost — while keeping the canonical 36-char
    UUID silhouette.

    The email sub-case is checked before the already-masked guard: ``_mask_email``
    is its own fixed point, and checking it first stops an email-shaped key that
    happens to contain asterisks from sliding past the guard in the clear.

    Examples::

        12345678901                          -> 123.***.***-01
        12345678000190                       -> 12.3**.***/****-90
        +5511987655432                       -> +55****5432
        abcd1234-e89b-12d3-a456-abcd89abcdef -> abcd1234-****-****-****-********cdef
        alice@pix.com                        -> a****e@pix.com
        legacy-garbage                       -> lega****bage   (free-text fallback)
    """
    kind = classify_pix_key(value)
    if kind == "email":
        return _mask_email(value)
    if _MASK_RUN in value:
        # Already one of the numeric / UUID masks below: no valid CPF, CNPJ,
        # phone or EVP key can contain an asterisk, so this cannot swallow a
        # real key. An unclassifiable value carrying '***' is, in practice, a
        # legacy mask of ours; leaving it untouched is the safe outcome.
        return value
    if kind == "cpf":
        return f"{value[:3]}.***.***-{value[9:]}"
    if kind == "cnpj":
        return f"{value[:2]}.{value[2]}**.***/****-{value[12:]}"
    if kind == "phone":
        return f"+55{_MASK}{value[-4:]}"
    if kind == "evp":
        return f"{value[:8]}-{_MASK}-{_MASK}-{_MASK}-{_MASK}{_MASK}{value[-4:]}"
    return _mask_text(value)
