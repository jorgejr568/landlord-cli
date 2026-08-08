from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi.responses import FileResponse, RedirectResponse, Response

from rentivo.api.analytics import set_analytics
from rentivo.api.bill_documents import (
    DocumentState,
    invoice_downloadable,
    invoice_state,
    recibo_downloadable,
    recibo_released,
    recibo_state,
)
from rentivo.api.routes._pdf_streaming import (
    bill_pdf_filename,
    bill_pdf_ref,
    rendered_pdf_response,
    stored_file_response,
    stream_bill_pdf,
    stream_receipt,
)
from rentivo.models.bill import Bill, BillStatus
from rentivo.models.receipt import Receipt
from rentivo.storage.base import FileRef


def _bill(
    *,
    status: str = BillStatus.SENT.value,
    pdf_path: str | None = "invoice.pdf",
    recibo_pdf_path: str | None = "recibo.pdf",
    render_status: str | None = None,
) -> Bill:
    return Bill(
        id=13,
        uuid="bill-uuid",
        billing_id=9,
        reference_month="2026-07",
        status=status,
        pdf_path=pdf_path,
        recibo_pdf_path=recibo_pdf_path,
        pdf_render_status=render_status,
    )


@pytest.mark.parametrize(
    ("pdf_path", "render_status", "expected"),
    [
        ("invoice.pdf", None, "ready"),
        ("invoice.pdf", "pending", "rendering"),
        (None, None, "missing"),
        # A queued render outranks the missing file: the stored file is about to change.
        (None, "pending", "rendering"),
    ],
)
def test_invoice_state_reports_the_render_before_the_stored_file(
    pdf_path: str | None,
    render_status: str | None,
    expected: DocumentState,
) -> None:
    bill = _bill(pdf_path=pdf_path, render_status=render_status)

    assert invoice_state(bill) == expected
    assert invoice_downloadable(bill) is (expected == "ready")


@pytest.mark.parametrize(
    ("recibo_pdf_path", "render_status", "expected"),
    [
        ("recibo.pdf", None, "ready"),
        ("recibo.pdf", "pending", "rendering"),
        (None, None, "missing"),
        (None, "pending", "rendering"),
    ],
)
def test_recibo_state_ignores_the_paid_gate(
    recibo_pdf_path: str | None,
    render_status: str | None,
    expected: DocumentState,
) -> None:
    bill = _bill(recibo_pdf_path=recibo_pdf_path, render_status=render_status)

    assert recibo_state(bill) == expected


@pytest.mark.parametrize(
    ("status", "recibo_pdf_path", "render_status", "expected"),
    [
        (BillStatus.PAID.value, "recibo.pdf", None, True),
        (BillStatus.PAID.value, "recibo.pdf", "pending", False),
        (BillStatus.PAID.value, None, None, False),
        (BillStatus.SENT.value, "recibo.pdf", None, False),
    ],
)
def test_recibo_downloadable_requires_a_paid_bill_and_a_rendered_file(
    status: str,
    recibo_pdf_path: str | None,
    render_status: str | None,
    expected: bool,
) -> None:
    bill = _bill(status=status, recibo_pdf_path=recibo_pdf_path, render_status=render_status)

    assert recibo_released(bill) is (status == BillStatus.PAID.value)
    assert recibo_downloadable(bill) is expected


def test_local_refs_stream_the_file_and_remote_refs_redirect_without_caching(tmp_path) -> None:
    stored = tmp_path / "recibo.pdf"
    stored.write_bytes(b"%PDF-1.4")

    local = stored_file_response(
        FileRef(kind="local", location=str(stored)),
        content_type="application/pdf",
        filename="recibo.pdf",
    )
    remote = stored_file_response(
        FileRef(kind="url", location="https://storage.example/recibo.pdf"),
        content_type="application/pdf",
        filename="recibo.pdf",
    )

    assert isinstance(local, FileResponse)
    assert local.media_type == "application/pdf"
    assert isinstance(remote, RedirectResponse)
    assert remote.status_code == 302
    assert remote.headers["location"] == "https://storage.example/recibo.pdf"
    assert local.headers["Cache-Control"] == remote.headers["Cache-Control"] == "no-store"


def test_bill_pdf_helpers_dispatch_on_the_document_kind() -> None:
    bill = _bill()
    services = SimpleNamespace(bill=MagicMock())
    services.bill.get_invoice_ref.return_value = FileRef(kind="url", location="https://storage.example/fatura.pdf")
    services.bill.get_recibo_ref.return_value = FileRef(kind="url", location="https://storage.example/recibo.pdf")

    assert bill_pdf_filename(bill, kind="invoice") == "fatura-bill-uuid.pdf"
    assert bill_pdf_filename(bill, kind="recibo") == "recibo-bill-uuid.pdf"
    assert bill_pdf_ref(bill, services, kind="invoice").location.endswith("fatura.pdf")
    assert bill_pdf_ref(bill, services, kind="recibo").location.endswith("recibo.pdf")
    assert stream_bill_pdf(bill, services, kind="invoice").headers["location"].endswith("fatura.pdf")


def test_rendered_pdf_response_attaches_the_bytes_it_was_given() -> None:
    response = rendered_pdf_response(b"%PDF-1.4", filename="recibo-bill-uuid.pdf")

    assert isinstance(response, Response)
    assert response.body == b"%PDF-1.4"
    assert response.media_type == "application/pdf"
    assert response.headers["Content-Disposition"] == 'attachment; filename="recibo-bill-uuid.pdf"'


def test_receipts_stream_with_their_own_content_type_and_filename() -> None:
    receipt = Receipt(
        id=3,
        uuid="receipt-uuid",
        bill_id=13,
        filename="comprovante.png",
        storage_key="receipts/comprovante.png",
        content_type="image/png",
        file_size=12,
    )
    services = SimpleNamespace(bill=MagicMock())
    services.bill.get_receipt_ref.return_value = FileRef(kind="url", location="https://storage.example/comprovante.png")

    response = stream_receipt(receipt, services)

    services.bill.get_receipt_ref.assert_called_once_with(receipt)
    assert response.status_code == 302
    assert response.headers["Cache-Control"] == "no-store"


def test_analytics_headers_title_case_every_metadata_name() -> None:
    response = Response(status_code=204)

    set_analytics(response, "rentivo_bill_generated", bill_uuid_hash="abc123", receipt_count=2)

    assert response.headers["X-Rentivo-Analytics-Event"] == "rentivo_bill_generated"
    assert response.headers["X-Rentivo-Analytics-Bill-Uuid-Hash"] == "abc123"
    assert response.headers["X-Rentivo-Analytics-Receipt-Count"] == "2"
