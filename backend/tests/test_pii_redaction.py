"""Tests for ``rentivo.pii_redaction``."""

from __future__ import annotations

import pytest

from rentivo.pii_redaction import PIIKind, redact, redact_pii


class TestRedactPIX:
    def test_long_value_uses_3_prefix_2_suffix(self):
        assert redact("12345678901", PIIKind.PIX) == "123...01"

    def test_email_shaped_pix_key_uses_pix_mask(self):
        # PIX keys can be emails, but the user requested all PIX-stuff use
        # the same first-3 / last-2 mask regardless of underlying shape.
        assert redact("alice@pix.com", PIIKind.PIX) == "ali...om"

    def test_short_value_collapses_to_stars(self):
        assert redact("Alice", PIIKind.PIX) == "***"
        assert redact("ab", PIIKind.PIX) == "***"
        assert redact("a", PIIKind.PIX) == "***"

    def test_min_length_threshold_is_six(self):
        # 5 chars: prefix(3) + suffix(2) = 5 — would expose the whole value.
        assert redact("abcde", PIIKind.PIX) == "***"
        # 6 chars: hides exactly 1 char — minimum useful mask.
        assert redact("abcdef", PIIKind.PIX) == "abc...ef"

    def test_empty_input_returns_empty(self):
        assert redact("", PIIKind.PIX) == ""

    def test_idempotent_on_typical_input(self):
        # The mask of a long value is itself >=6 chars and matches the
        # first-3 / last-2 pattern — re-applying redact is a no-op.
        once = redact("12345678901", PIIKind.PIX)
        twice = redact(once, PIIKind.PIX)
        assert once == twice == "123...01"


class TestRedactEmail:
    def test_long_local_part(self):
        assert redact("joe@gmail.com", PIIKind.EMAIL) == "jo...@gmail.com"
        assert redact("alice@example.com", PIIKind.EMAIL) == "al...@example.com"

    def test_short_local_part_collapses_to_stars_at(self):
        assert redact("ab@x.co", PIIKind.EMAIL) == "***@x.co"
        assert redact("a@x.co", PIIKind.EMAIL) == "***@x.co"

    def test_three_char_local_uses_2_prefix(self):
        # "abc" → "ab...@x.co". 3 chars hides 1 char — minimum useful mask.
        assert redact("abc@x.co", PIIKind.EMAIL) == "ab...@x.co"

    def test_no_at_sign_falls_back_to_pix_mask(self):
        # Defensive: if a "to_email" field somehow doesn't contain @, treat
        # it as PIX-shaped rather than crashing.
        assert redact("not-an-email", PIIKind.EMAIL) == "not...il"

    def test_empty_input_returns_empty(self):
        assert redact("", PIIKind.EMAIL) == ""

    def test_idempotent_on_typical_input(self):
        once = redact("alice@example.com", PIIKind.EMAIL)
        twice = redact(once, PIIKind.EMAIL)
        assert once == twice == "al...@example.com"


class TestRedactDispatch:
    def test_unknown_kind_raises(self):
        with pytest.raises(ValueError, match="Unknown PII kind"):
            redact("anything", "not-a-kind")  # type: ignore[arg-type]

    def test_kind_is_str_enum(self):
        assert PIIKind.PIX.value == "pix"
        assert PIIKind.EMAIL.value == "email"


class TestRedactPII:
    """``redact_pii`` = credential redaction + partial-masking of PII keys.

    Used at the two boundaries where a whole dict leaves the encryption
    boundary: the structlog processor chain and ``AuditService.log``.
    """

    @pytest.mark.parametrize(
        ("field", "value", "expected"),
        [
            ("email", "alice@example.com", "al...@example.com"),
            ("Email", "alice@example.com", "al...@example.com"),
            ("to", "alice@example.com", "al...@example.com"),
            ("to_email", "alice@example.com", "al...@example.com"),
            ("toEmail", "alice@example.com", "al...@example.com"),
            ("recipient_email", "alice@example.com", "al...@example.com"),
            ("invited_email", "bob@example.com", "bo...@example.com"),
            ("invited_by_email", "alice@example.com", "al...@example.com"),
            ("actor_username", "alice@example.com", "al...@example.com"),
            ("subject", "Fatura de julho - Apto 101", "Fat...01"),
            ("billing_name", "Apto 101 - Maria Silva", "Apt...va"),
            ("pix_key", "alice@pix.com", "ali...om"),
            ("pix_merchant_name", "Maria", "***"),
            ("pix_merchant_city", "Sao Paulo", "Sao...lo"),
        ],
    )
    def test_known_pii_keys_are_masked_case_and_separator_insensitively(self, field, value, expected):
        assert redact_pii({field: value}) == {field: expected}

    def test_pii_masking_recurses_through_nested_containers(self):
        payload = {
            "event": "email_sent",
            "recipients": [
                {"to": "alice@example.com"},
                {"nested": {"billing_name": "Apto 101 - Maria Silva"}},
            ],
            "pair": ({"email": "bob@example.com"},),
        }

        assert redact_pii(payload) == {
            "event": "email_sent",
            "recipients": [
                {"to": "al...@example.com"},
                {"nested": {"billing_name": "Apt...va"}},
            ],
            "pair": ({"email": "bo...@example.com"},),
        }

    def test_pii_containers_under_a_pii_key_are_masked_element_wise(self):
        assert redact_pii({"to": ["alice@example.com", "bob@example.com"]}) == {
            "to": ["al...@example.com", "bo...@example.com"]
        }
        assert redact_pii({"to": ("alice@example.com",)}) == {"to": ("al...@example.com",)}
        assert redact_pii({"email": {"primary": "alice@example.com"}}) == {"email": {"primary": "al...@example.com"}}

    def test_non_string_values_under_a_pii_key_keep_their_type(self):
        """Correlation identifiers must not be degraded into strings or "" —
        masking is for human-readable PII, not for ids, counts or None."""
        assert redact_pii({"email": None, "to": 42, "subject": True}) == {
            "email": None,
            "to": 42,
            "subject": True,
        }

    def test_credential_fields_still_win_over_pii_masking(self):
        assert redact_pii({"password": "plain-password", "email": "alice@example.com"}) == {
            "password": "[REDACTED]",
            "email": "al...@example.com",
        }

    def test_redact_pii_still_redacts_credentials_everywhere_redact_does(self):
        payload = {"details": [{"message": "rntv-v1-aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789_-abc"}]}

        assert redact_pii(payload) == {"details": [{"message": "[REDACTED]"}]}
        assert redact_pii(("safe", "id_token=oidc-secret")) == ("safe", "id_token=[REDACTED]")
        assert redact_pii(7) == 7

    def test_safe_observability_fields_are_preserved(self):
        safe = {"user_id": 7, "request_id": "request-123", "email_hash": "deadbeef", "message_id": "ses-1"}

        assert redact_pii(safe) == safe

    def test_masking_is_stable_for_already_masked_values(self):
        """Serializers mask before AuditService masks again. The common shape
        must survive the second pass unchanged."""
        assert redact_pii({"email": "al...@example.com"}) == {"email": "al...@example.com"}

    def test_plain_redact_is_unchanged_and_does_not_mask_pii(self):
        """``redact()`` keeps its exact current contract — only the two
        boundary call sites opt into PII masking."""
        assert redact({"email": "alice@example.com"}) == {"email": "alice@example.com"}
