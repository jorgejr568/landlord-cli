"""Shared plumbing for the ``rentivo.scripts`` operator entry points.

Every script in this package has the same shape: read a flag or two off
``sys.argv``, configure CLI logging, migrate to head, open the process-wide
connection, do the work, print a rich summary. This module owns the parts
that were copy-pasted into each ``main()``.

Kept private to the package (leading underscore): these helpers encode the
conventions of the hand-run operator scripts, not a public API.
"""

from __future__ import annotations

import sys
from collections.abc import Callable

from sqlalchemy import Connection

from rentivo.db import get_connection, initialize_db
from rentivo.logging import configure_logging
from rentivo.models.bill import Bill
from rentivo.models.billing import Billing
from rentivo.repositories.base import BillingRepository, BillRepository


def parse_flag(flag: str) -> bool:
    """True when ``flag`` was passed on the command line.

    The scripts take no positional arguments and no option values, so a
    membership test over ``sys.argv`` is the whole parser.
    """
    return flag in sys.argv


def parse_dry_run() -> bool:
    """True when ``--dry-run`` was passed. The script must then write nothing."""
    return parse_flag("--dry-run")


def configure_cli_logging() -> None:
    """Install the human-readable log renderer these scripts are read through."""
    configure_logging(cli=True)


def open_cli_connection() -> Connection:
    """Migrate to head and return the process-wide CLI connection."""
    initialize_db()
    return get_connection()


def boot() -> Connection:
    """Configure CLI logging, migrate to head, and open the CLI connection.

    The two halves are separately available for the one script that prints a
    banner between them.
    """
    configure_cli_logging()
    return open_cli_connection()


def collect_bills(
    billing_repo: BillingRepository,
    bill_repo: BillRepository,
    *,
    keep: Callable[[Bill], bool] | None = None,
) -> tuple[list[Billing], list[tuple[Billing, Bill]]]:
    """Walk every billing and every one of its bills.

    Returns ``(billings, pairs)``. The billings are returned alongside the
    pairs because callers report "no billings at all" differently from "no
    bill matched" — an empty ``pairs`` alone cannot tell those apart.

    ``keep`` filters the bills; ``None`` keeps every bill.
    """
    billings = billing_repo.list_all()
    pairs: list[tuple[Billing, Bill]] = []
    for billing in billings:
        assert billing.id is not None
        for bill in bill_repo.list_by_billing(billing.id):
            if keep is None or keep(bill):
                pairs.append((billing, bill))
    return billings, pairs
