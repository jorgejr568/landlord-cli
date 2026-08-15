from __future__ import annotations

import structlog

from rentivo.models.billing import Billing, BillingItem
from rentivo.models.recipient import Recipient
from rentivo.observability import traced
from rentivo.pix import normalize_pix_triple, validate_pix_key
from rentivo.repositories.base import BillingRepository

logger = structlog.get_logger(__name__)


class BillingService:
    def __init__(self, repo: BillingRepository) -> None:
        self.repo = repo

    @traced("billing.create_billing")
    def create_billing(
        self,
        name: str,
        description: str,
        items: list[BillingItem],
        pix_key: str = "",
        pix_merchant_name: str = "",
        pix_merchant_city: str = "",
        owner_type: str = "user",
        owner_id: int = 0,
        recipients: list[dict[str, str]] | None = None,
        reply_to: list[dict[str, str]] | None = None,
    ) -> Billing:
        pix_key, pix_merchant_name, pix_merchant_city = normalize_pix_triple(
            pix_key,
            pix_merchant_name,
            pix_merchant_city,
        )
        pix_key = validate_pix_key(pix_key) if pix_key else ""
        billing = Billing(
            name=name,
            description=description,
            items=items,
            pix_key=pix_key,
            pix_merchant_name=pix_merchant_name,
            pix_merchant_city=pix_merchant_city,
            owner_type=owner_type,
            owner_id=owner_id,
        )
        if recipients is None and reply_to is None:
            result = self.repo.create(billing)
        else:
            result = self.repo.create_aggregate(
                billing,
                self._contacts(recipients),
                self._contacts(reply_to),
            )
        logger.info("billing_created", billing_id=result.id, name=result.name)
        return result

    @traced("billing.list_billings")
    def list_billings(self) -> list[Billing]:
        result = self.repo.list_all()
        logger.debug("billings_listed_all", count=len(result))
        return result

    @traced("billing.list_billings_for_user")
    def list_billings_for_user(self, user_id: int) -> list[Billing]:
        result = self.repo.list_for_user(user_id)
        logger.debug("billings_listed_for_user", count=len(result), user_id=user_id)
        return result

    @traced("billing.get_billing")
    def get_billing(self, billing_id: int) -> Billing | None:
        result = self.repo.get_by_id(billing_id)
        logger.debug("billing_get", billing_id=billing_id, found=result is not None)
        return result

    @traced("billing.get_billing_by_uuid")
    def get_billing_by_uuid(self, uuid: str) -> Billing | None:
        result = self.repo.get_by_uuid(uuid)
        logger.debug("billing_get_by_uuid", billing_uuid=uuid, found=result is not None)
        return result

    @traced("billing.update_billing")
    def update_billing(
        self,
        billing: Billing,
        *,
        recipients: list[dict[str, str]] | None = None,
        reply_to: list[dict[str, str]] | None = None,
    ) -> Billing:
        billing.pix_key, billing.pix_merchant_name, billing.pix_merchant_city = normalize_pix_triple(
            billing.pix_key,
            billing.pix_merchant_name,
            billing.pix_merchant_city,
        )
        billing.pix_key = validate_pix_key(billing.pix_key) if billing.pix_key else ""
        if recipients is None and reply_to is None:
            result = self.repo.update(billing)
        else:
            result = self.repo.update_aggregate(
                billing,
                self._contacts(recipients, billing.id),
                self._contacts(reply_to, billing.id),
            )
            if result is None:  # pragma: no cover - an ordinary update has no ownership CAS
                raise RuntimeError("Failed to update billing")
        logger.info("billing_updated", billing_id=result.id, name=result.name)
        return result

    def update_and_transfer_personal_to_organization(
        self,
        billing: Billing,
        expected_owner_id: int,
        organization_id: int,
        *,
        recipients: list[dict[str, str]] | None = None,
        reply_to: list[dict[str, str]] | None = None,
    ) -> Billing:
        billing.pix_key, billing.pix_merchant_name, billing.pix_merchant_city = normalize_pix_triple(
            billing.pix_key, billing.pix_merchant_name, billing.pix_merchant_city
        )
        billing.pix_key = validate_pix_key(billing.pix_key) if billing.pix_key else ""
        if recipients is None and reply_to is None:
            updated = self.repo.update_and_transfer_personal_to_organization(
                billing, expected_owner_id, organization_id
            )
        else:
            updated = self.repo.update_aggregate(
                billing,
                self._contacts(recipients, billing.id),
                self._contacts(reply_to, billing.id),
                expected_owner_id=expected_owner_id,
                organization_id=organization_id,
            )
        if updated is None:
            raise ValueError("Billing ownership changed")
        return updated

    @staticmethod
    def _contacts(rows: list[dict[str, str]] | None, billing_id: int | None = None) -> list[Recipient] | None:
        if rows is None:
            return None
        return [
            Recipient(
                billing_id=billing_id or 0,
                name=(row.get("name") or "").strip(),
                email=(row.get("email") or "").strip(),
            )
            for row in rows
            if (row.get("name") or "").strip() and (row.get("email") or "").strip()
        ]

    @traced("billing.delete_billing")
    def delete_billing(self, billing_id: int) -> None:
        self.repo.delete(billing_id)
        logger.info("billing_deleted", billing_id=billing_id)

    @traced("billing.transfer_to_organization")
    def transfer_to_organization(
        self,
        billing_id: int,
        org_id: int,
        *,
        expected_owner_id: int | None = None,
    ) -> None:
        billing = self.repo.get_by_id(billing_id)
        if billing is None:
            logger.warning("billing_transfer_failed", billing_id=billing_id, reason="not_found")
            raise ValueError("Billing not found")
        if billing.owner_type != "user":
            logger.warning(
                "billing_transfer_failed",
                billing_id=billing_id,
                reason="not_user_owned",
                owner_type=billing.owner_type,
            )
            raise ValueError("Only personal billings can be transferred to organizations")
        current_owner_id = billing.owner_id if expected_owner_id is None else expected_owner_id
        if billing.owner_id != current_owner_id:
            raise ValueError("Billing ownership changed")
        transferred = self.repo.transfer_owner_if_current(
            billing_id,
            "user",
            current_owner_id,
            "organization",
            org_id,
        )
        if not transferred:
            raise ValueError("Billing ownership changed")
        logger.info("billing_transferred", billing_id=billing_id, org_id=org_id)
