from __future__ import annotations

from dataclasses import dataclass

import structlog

from rentivo.models.billing import Billing
from rentivo.models.organization import Organization
from rentivo.models.user import User
from rentivo.observability import traced
from rentivo.repositories.base import OrganizationRepository, UserRepository

logger = structlog.get_logger(__name__)


@dataclass(frozen=True)
class PixConfig:
    pix_key: str
    merchant_name: str
    merchant_city: str


def _complete(pix_key: str, merchant_name: str, merchant_city: str) -> PixConfig | None:
    if pix_key and merchant_name and merchant_city:
        return PixConfig(pix_key=pix_key, merchant_name=merchant_name, merchant_city=merchant_city)
    return None


class PixService:
    """Resolves PIX configuration for billings, most-specific-wins.

    Resolution order (mirrors ThemeService pattern, billing override first):
    1. Billing override — if all three billing fields set
    2. Owner (user or organization, based on billing.owner_type) — if all three fields set
    3. None — caller must block invoice generation and prompt the user
    """

    def __init__(self, user_repo: UserRepository, org_repo: OrganizationRepository) -> None:
        self.user_repo = user_repo
        self.org_repo = org_repo
        # Request-scoped memo: a PixService is built per request, and a single
        # billing-list render resolves PIX for N billings that usually share one
        # owner (the logged-in user). Caching by (owner_type, owner_id) collapses
        # those N identical owner fetches into one query.
        self._owner_cache: dict[tuple[str, int], Organization | User | None] = {}

    @traced("pix.resolve_for_billing")
    def resolve_for_billing(self, billing: Billing) -> PixConfig | None:
        owner_cfg = self.get_owner_config(billing.owner_type, billing.owner_id)
        billing_cfg = _complete(billing.pix_key, billing.pix_merchant_name, billing.pix_merchant_city)
        # Billing-level override takes precedence when fully set, matching the
        # theme service pattern (most-specific wins).
        return billing_cfg or owner_cfg

    @traced("pix.get_owner_config")
    def get_owner_config(self, owner_type: str, owner_id: int) -> PixConfig | None:
        owner = self._get_owner(owner_type, owner_id)
        if owner is None:
            return None
        return _complete(owner.pix_key, owner.pix_merchant_name, owner.pix_merchant_city)

    @traced("pix.resolve_owner_display_name")
    def resolve_owner_display_name(self, billing: Billing) -> str | None:
        """Human-readable label for a billing's owner: the organization name for
        org-owned billings, the account email for user-owned ones (personal
        accounts carry no name). None when the owner row is gone or its label is
        empty, leaving the caller to pick its own fallback.
        """
        owner = self._get_owner(billing.owner_type, billing.owner_id)
        if owner is None:
            return None
        display = owner.name if billing.owner_type == "organization" else owner.email
        return display or None

    def _get_owner(self, owner_type: str, owner_id: int) -> Organization | User | None:
        key = (owner_type, owner_id)
        if key not in self._owner_cache:
            self._owner_cache[key] = self._load_owner(owner_type, owner_id)
        return self._owner_cache[key]

    def _load_owner(self, owner_type: str, owner_id: int) -> Organization | User | None:
        if owner_type == "organization":
            return self.org_repo.get_by_id(owner_id)
        return self.user_repo.get_by_id(owner_id)

    @traced("pix.owner_needs_setup")
    def owner_needs_setup(self, owner_type: str, owner_id: int) -> bool:
        return self.get_owner_config(owner_type, owner_id) is None

    @traced("pix.billing_needs_setup")
    def billing_needs_setup(self, billing: Billing) -> bool:
        return self.resolve_for_billing(billing) is None
