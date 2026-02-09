from __future__ import annotations

import logging

from landlord.models.billing import Billing, BillingItem
from landlord.repositories.base import BillingRepository

logger = logging.getLogger(__name__)


class BillingService:
    def __init__(self, repo: BillingRepository) -> None:
        self.repo = repo

    def create_billing(
        self, name: str, description: str, items: list[BillingItem], pix_key: str = ""
    ) -> Billing:
        billing = Billing(name=name, description=description, items=items, pix_key=pix_key)
        result = self.repo.create(billing)
        logger.info("Billing created: id=%s, name=%s", result.id, result.name)
        return result

    def list_billings(self) -> list[Billing]:
        return self.repo.list_all()

    def get_billing(self, billing_id: int) -> Billing | None:
        return self.repo.get_by_id(billing_id)

    def get_billing_by_uuid(self, uuid: str) -> Billing | None:
        return self.repo.get_by_uuid(uuid)

    def update_billing(self, billing: Billing) -> Billing:
        result = self.repo.update(billing)
        logger.info("Billing updated: id=%s, name=%s", result.id, result.name)
        return result

    def delete_billing(self, billing_id: int) -> None:
        self.repo.delete(billing_id)
        logger.info("Billing %s soft-deleted", billing_id)
