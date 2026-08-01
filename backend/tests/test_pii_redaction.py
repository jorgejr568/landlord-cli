"""Tests for ``rentivo.pii_redaction``."""

from __future__ import annotations

import pytest

from rentivo.pii_redaction import PIIKind, redact, redact_pii


def _thrice(value: str, kind: PIIKind) -> tuple[str, str, str]:
    """Apply the mask three times. Serializers mask, then AuditService masks
    again, then the structlog processor can mask a third time on the way to a
    sink — every shape has to be a one-step fixed point."""
    once = redact(value, kind)
    twice = redact(once, kind)
    thrice = redact(twice, kind)
    return once, twice, thrice


class TestRedactText:
    def test_long_value_reveals_first_four_and_last_four(self):
        assert redact("Fatura de julho - Apto 101", PIIKind.TEXT) == "Fatu**** 101"
        assert redact("Apto 101 - Maria Silva", PIIKind.TEXT) == "Apto****ilva"

    def test_asterisk_run_is_fixed_width_regardless_of_hidden_length(self):
        """A proportional run would leak the original length."""
        short = redact("Apto 101 - Maria Silva", PIIKind.TEXT)
        long = redact("Apto 101 - Maria Silva de Almeida Pereira", PIIKind.TEXT)
        assert short.count("*") == long.count("*") == 4
        assert len(short) == len(long) == 12

    def test_short_value_masks_entirely(self):
        # Under 12 chars, first-4 + last-4 would reveal all but a character or
        # two: 'Sao Paulo' is 9 chars and would render as 'Sao ****aulo'.
        assert redact("Sao Paulo", PIIKind.TEXT) == "****"
        assert redact("Alice", PIIKind.TEXT) == "****"
        assert redact("a", PIIKind.TEXT) == "****"
        assert redact("Apto 101 - ", PIIKind.TEXT) == "****"

    def test_threshold_is_twelve(self):
        assert redact("abcdefghijk", PIIKind.TEXT) == "****"  # 11 chars
        assert redact("abcdefghijkl", PIIKind.TEXT) == "abcd****ijkl"  # 12 chars

    def test_empty_input_returns_empty(self):
        assert redact("", PIIKind.TEXT) == ""

    @pytest.mark.parametrize("value", ["Fatura de julho - Apto 101", "Sao Paulo", "abcdefghijkl", "a"])
    def test_is_a_one_step_fixed_point(self, value):
        once, twice, thrice = _thrice(value, PIIKind.TEXT)
        assert once == twice == thrice


class TestRedactEmail:
    def test_reveals_first_and_last_of_local_part_and_keeps_the_domain(self):
        assert redact("alphakebab@gmail.com", PIIKind.EMAIL) == "a****b@gmail.com"
        assert redact("joe@gmail.com", PIIKind.EMAIL) == "j****e@gmail.com"
        assert redact("alice@example.com", PIIKind.EMAIL) == "a****e@example.com"

    def test_asterisk_run_is_fixed_width_regardless_of_local_part_length(self):
        assert redact("ab" + "c" * 40 + "d@x.co", PIIKind.EMAIL) == "a****d@x.co"

    def test_short_local_part_masks_entirely(self):
        # Two characters: first+last would reproduce the whole local part.
        assert redact("ab@x.co", PIIKind.EMAIL) == "****@x.co"
        assert redact("a@x.co", PIIKind.EMAIL) == "****@x.co"
        assert redact("@x.co", PIIKind.EMAIL) == "****@x.co"

    def test_three_char_local_part_is_the_minimum_useful_mask(self):
        assert redact("abc@x.co", PIIKind.EMAIL) == "a****c@x.co"

    def test_an_already_masked_local_part_collapses_instead_of_growing(self):
        """Without the collapse, '*ab*' would mask to '******' and then grow by
        two asterisks on every further pass."""
        assert redact("*ab*@x.co", PIIKind.EMAIL) == "****@x.co"
        assert redact("****@x.co", PIIKind.EMAIL) == "****@x.co"

    def test_no_at_sign_falls_back_to_the_text_mask(self):
        assert redact("not-an-email", PIIKind.EMAIL) == "not-****mail"
        assert redact("cli", PIIKind.EMAIL) == "****"

    def test_empty_input_returns_empty(self):
        assert redact("", PIIKind.EMAIL) == ""

    @pytest.mark.parametrize(
        "value",
        ["alice@example.com", "ab@x.co", "a@x.co", "*ab*@x.co", "****@x.co", "not-an-email", "cli", "@x.co"],
    )
    def test_is_a_one_step_fixed_point(self, value):
        once, twice, thrice = _thrice(value, PIIKind.EMAIL)
        assert once == twice == thrice


class TestRedactPix:
    def test_cpf_keeps_canonical_punctuation(self):
        assert redact("12345678901", PIIKind.PIX) == "123.***.***-01"

    def test_cnpj_keeps_canonical_punctuation(self):
        assert redact("12345678000190", PIIKind.PIX) == "12.3**.***/****-90"

    def test_phone_keeps_the_country_code_and_the_last_four(self):
        assert redact("+5511987655432", PIIKind.PIX) == "+55****5432"

    def test_phone_mask_does_not_disclose_mobile_versus_landline(self):
        """11-digit mobiles and 10-digit landlines must render identically —
        a proportional asterisk run would give the digit count away."""
        mobile = redact("+5511987655432", PIIKind.PIX)
        landline = redact("+551133334444", PIIKind.PIX)
        assert len(mobile) == len(landline) == 11
        assert mobile.count("*") == landline.count("*") == 4

    def test_evp_keeps_the_first_hex_group_and_the_last_four(self):
        # Stricter reading than the illustrative example: reveal only the
        # first hex group and the last 4 characters, not the last 8. An EVP's
        # first hex group is already effectively unique, so revealing eight
        # more hex characters adds no triage value for real identifiability
        # cost. The canonical 8-4-4-4-12 UUID silhouette is still preserved.
        assert redact("abcd1234-e89b-12d3-a456-abcd89abcdef", PIIKind.PIX) == "abcd1234-****-****-****-********cdef"

    def test_email_shaped_key_uses_the_email_mask(self):
        assert redact("alice@pix.com", PIIKind.PIX) == "a****e@pix.com"
        assert redact("pix@test.com", PIIKind.PIX) == "p****x@test.com"

    def test_email_shaped_key_containing_asterisks_is_still_masked(self):
        """The email sub-case is checked before the already-masked guard, so a
        key like this cannot slide past it in the clear."""
        assert redact("a***b@pix.com", PIIKind.PIX) == "a****b@pix.com"

    def test_unclassifiable_value_falls_back_to_the_text_mask(self):
        assert redact("legacy-garbage", PIIKind.PIX) == "lega****bage"
        assert redact("Eve", PIIKind.PIX) == "****"
        assert redact("abcdef", PIIKind.PIX) == "****"

    def test_a_legacy_mask_is_remasked_rather_than_left_in_place(self):
        # The old first-3/'...'/last-2 shape carries no asterisk run, so it is
        # re-masked once into the new shape and is stable thereafter.
        assert redact("abc...xy", PIIKind.PIX) == "****"

    def test_empty_input_returns_empty(self):
        assert redact("", PIIKind.PIX) == ""

    @pytest.mark.parametrize(
        "value",
        [
            "12345678901",
            "12345678000190",
            "+5511987655432",
            "+551133334444",
            "abcd1234-e89b-12d3-a456-abcd89abcdef",
            "alice@pix.com",
            "a***b@pix.com",
            "legacy-garbage",
            "Eve",
            "abc...xy",
        ],
    )
    def test_is_a_one_step_fixed_point(self, value):
        once, twice, thrice = _thrice(value, PIIKind.PIX)
        assert once == twice == thrice


class TestRedactDispatch:
    def test_unknown_kind_raises(self):
        with pytest.raises(ValueError, match="Unknown PII kind"):
            redact("anything", "not-a-kind")  # type: ignore[arg-type]

    def test_kind_is_str_enum(self):
        assert PIIKind.PIX.value == "pix"
        assert PIIKind.EMAIL.value == "email"
        assert PIIKind.TEXT.value == "text"


class TestRedactPII:
    """``redact_pii`` = credential redaction + partial-masking of PII keys.

    Used at the two boundaries where a whole dict leaves the encryption
    boundary: the structlog processor chain and ``AuditService.log``.
    """

    @pytest.mark.parametrize(
        ("field", "value", "expected"),
        [
            ("email", "alice@example.com", "a****e@example.com"),
            ("Email", "alice@example.com", "a****e@example.com"),
            ("to", "alice@example.com", "a****e@example.com"),
            ("to_email", "alice@example.com", "a****e@example.com"),
            ("toEmail", "alice@example.com", "a****e@example.com"),
            ("recipient_email", "alice@example.com", "a****e@example.com"),
            ("invited_email", "bob@example.com", "b****b@example.com"),
            ("invited_by_email", "alice@example.com", "a****e@example.com"),
            ("actor_username", "alice@example.com", "a****e@example.com"),
            ("subject", "Fatura de julho - Apto 101", "Fatu**** 101"),
            ("billing_name", "Apto 101 - Maria Silva", "Apto****ilva"),
            ("pix_key", "alice@pix.com", "a****e@pix.com"),
            ("pix_key", "12345678901", "123.***.***-01"),
            ("pix_merchant_name", "Maria", "****"),
            ("pix_merchant_name", "Alice da Silva", "Alic****ilva"),
            ("pix_merchant_city", "Sao Paulo", "****"),
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
                {"to": "a****e@example.com"},
                {"nested": {"billing_name": "Apto****ilva"}},
            ],
            "pair": ({"email": "b****b@example.com"},),
        }

    def test_pii_containers_under_a_pii_key_are_masked_element_wise(self):
        assert redact_pii({"to": ["alice@example.com", "bob@example.com"]}) == {
            "to": ["a****e@example.com", "b****b@example.com"]
        }
        assert redact_pii({"to": ("alice@example.com",)}) == {"to": ("a****e@example.com",)}
        assert redact_pii({"email": {"primary": "alice@example.com"}}) == {"email": {"primary": "a****e@example.com"}}

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
            "email": "a****e@example.com",
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
        """Serializers mask before AuditService masks again. Every shape has to
        survive the second pass byte-for-byte."""
        already = {
            "email": "a****e@example.com",
            "subject": "Fatu**** 101",
            "billing_name": "Apto****ilva",
            "pix_key": "123.***.***-01",
            "pix_merchant_city": "****",
        }

        assert redact_pii(already) == already
        assert redact_pii(redact_pii(already)) == already

    def test_plain_redact_is_unchanged_and_does_not_mask_pii(self):
        """``redact()`` keeps its exact current contract — only the two
        boundary call sites opt into PII masking."""
        assert redact({"email": "alice@example.com"}) == {"email": "alice@example.com"}
