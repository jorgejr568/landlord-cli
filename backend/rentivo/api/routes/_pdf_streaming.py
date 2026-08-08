"""Response builders for the endpoints that serve stored files.

Bill PDFs, bill receipts and billing attachments all reach the client the same
way: local storage streams the file, remote storage redirects to a signed URL,
and neither is ever cached.
"""

from __future__ import annotations

from typing import Literal

from fastapi.responses import FileResponse, RedirectResponse, Response

from rentivo.models.bill import Bill
from rentivo.models.receipt import Receipt
from rentivo.services.container import RequestServices
from rentivo.storage.base import FileRef

BillDocument = Literal["invoice", "recibo"]

_FILENAME_PREFIX: dict[BillDocument, str] = {"invoice": "fatura", "recibo": "recibo"}


def stored_file_response(ref: FileRef, *, content_type: str, filename: str) -> Response:
    response: Response
    if ref.kind == "local":
        response = FileResponse(ref.location, media_type=content_type, filename=filename)
    else:
        response = RedirectResponse(ref.location, status_code=302)
    response.headers["Cache-Control"] = "no-store"
    return response


def bill_pdf_filename(bill: Bill, *, kind: BillDocument) -> str:
    return f"{_FILENAME_PREFIX[kind]}-{bill.uuid}.pdf"


def bill_pdf_ref(bill: Bill, services: RequestServices, *, kind: BillDocument) -> FileRef:
    if kind == "invoice":
        return services.bill.get_invoice_ref(bill)
    return services.bill.get_recibo_ref(bill)


def stream_bill_pdf(bill: Bill, services: RequestServices, *, kind: BillDocument) -> Response:
    return stored_file_response(
        bill_pdf_ref(bill, services, kind=kind),
        content_type="application/pdf",
        filename=bill_pdf_filename(bill, kind=kind),
    )


def rendered_pdf_response(content: bytes, *, filename: str) -> Response:
    """Serve a PDF rendered on the fly; there is no stored object to stream."""
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def stream_receipt(receipt: Receipt, services: RequestServices) -> Response:
    return stored_file_response(
        services.bill.get_receipt_ref(receipt),
        content_type=receipt.content_type,
        filename=receipt.filename,
    )
