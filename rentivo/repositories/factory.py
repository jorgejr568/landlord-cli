from rentivo.repositories.base import (
    AuditLogRepository,
    BillingRepository,
    BillRepository,
    InviteRepository,
    OrganizationRepository,
    ReceiptRepository,
    UserRepository,
)


def get_billing_repository() -> BillingRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyBillingRepository

    return SQLAlchemyBillingRepository(get_connection())


def get_bill_repository() -> BillRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyBillRepository

    return SQLAlchemyBillRepository(get_connection())


def get_user_repository() -> UserRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyUserRepository

    return SQLAlchemyUserRepository(get_connection())


def get_organization_repository() -> OrganizationRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyOrganizationRepository

    return SQLAlchemyOrganizationRepository(get_connection())


def get_invite_repository() -> InviteRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyInviteRepository

    return SQLAlchemyInviteRepository(get_connection())


def get_receipt_repository() -> ReceiptRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyReceiptRepository

    return SQLAlchemyReceiptRepository(get_connection())


def get_audit_log_repository() -> AuditLogRepository:
    from rentivo.db import get_connection
    from rentivo.repositories.sqlalchemy import SQLAlchemyAuditLogRepository

    return SQLAlchemyAuditLogRepository(get_connection())
