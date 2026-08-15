from __future__ import annotations

import pytest
from pydantic import ValidationError

from rentivo.api.schemas import billings as billing_schemas
from rentivo.api.schemas.billings import ContactInput
from rentivo.api.schemas.organizations import OrganizationCreateRequest


def test_contact_defensively_rejects_malformed_email_if_shared_normalizer_weakens(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(billing_schemas, "normalize_email", lambda value: value)

    with pytest.raises(ValidationError) as caught:
        ContactInput(name="Ana", email="invalid-email")

    assert caught.value.errors()[0]["loc"] == ("email",)


def test_organization_create_reports_every_missing_pix_companion() -> None:
    with pytest.raises(ValidationError) as caught:
        OrganizationCreateRequest(name="Acme", pix_key="admin@example.com")

    assert {error["loc"] for error in caught.value.errors()} == {
        ("pix_merchant_name",),
        ("pix_merchant_city",),
    }
