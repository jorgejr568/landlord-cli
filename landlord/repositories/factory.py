from landlord.repositories.base import BillingRepository, BillRepository


def get_billing_repository() -> BillingRepository:
    from landlord.db import get_connection
    from landlord.repositories.sqlalchemy import SQLAlchemyBillingRepository

    return SQLAlchemyBillingRepository(get_connection())


def get_bill_repository() -> BillRepository:
    from landlord.db import get_connection
    from landlord.repositories.sqlalchemy import SQLAlchemyBillRepository

    return SQLAlchemyBillRepository(get_connection())
