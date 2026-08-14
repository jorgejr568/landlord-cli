"""Readiness rules for the two PDF documents attached to a bill.

A single render job produces both the invoice and the recibo, so a queued render
leaves either document stale until it finishes. These helpers are pure: they
describe the document state and let each endpoint map it onto its own conflict
code, since the same state is a 404, a 409 or an on-the-fly render depending on
the route. Download endpoints consume the ordered *_state machines; capability
flags read the raw predicates because they carry no HTTP-code precedence.
"""

from __future__ import annotations

from typing import Literal

from rentivo.models.bill import Bill, BillStatus

PDF_RENDER_PENDING = "pending"

DocumentState = Literal["ready", "rendering", "missing"]


def is_rendering(bill: Bill) -> bool:
    return bill.pdf_render_status == PDF_RENDER_PENDING


def has_invoice(bill: Bill) -> bool:
    return bool(bill.pdf_path)


def has_recibo(bill: Bill) -> bool:
    return bool(bill.recibo_pdf_path)


def invoice_state(bill: Bill) -> DocumentState:
    """A queued render outranks a missing file: the stored file is about to change."""
    if is_rendering(bill):
        return "rendering"
    return "ready" if has_invoice(bill) else "missing"


def recibo_state(bill: Bill) -> DocumentState:
    """Render state of the recibo file alone, independent of the paid gate."""
    if is_rendering(bill):
        return "rendering"
    return "ready" if has_recibo(bill) else "missing"


def recibo_released(bill: Bill) -> bool:
    """The recibo is only ever offered once the bill is paid."""
    return bill.status == BillStatus.PAID.value


def invoice_downloadable(bill: Bill) -> bool:
    return invoice_state(bill) == "ready"


def recibo_downloadable(bill: Bill) -> bool:
    return recibo_released(bill) and recibo_state(bill) == "ready"


def recibo_download_available(bill: Bill) -> bool:
    """Whether the direct endpoint can return a recibo, including on-demand rendering."""
    return recibo_released(bill) and not is_rendering(bill)
