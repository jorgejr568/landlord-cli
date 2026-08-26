from rentivo.models.bill import Bill, BillLineItem
from rentivo.models.billing import ItemType
from rentivo.models.theme import Theme
from rentivo.pdf.recibo import ReciboPDF


class TestReciboPDF:
    def _make_bill(self, **overrides):
        defaults = dict(
            id=1,
            uuid="test-uuid",
            billing_id=1,
            reference_month="2025-03",
            total_amount=295000,
            line_items=[
                BillLineItem(description="Aluguel", amount=285000, item_type=ItemType.FIXED, sort_order=0),
                BillLineItem(description="Água", amount=10000, item_type=ItemType.VARIABLE, sort_order=1),
            ],
            notes="",
            due_date="10/04/2025",
        )
        defaults.update(overrides)
        return Bill(**defaults)

    def test_generate_returns_pdf_bytes(self):
        result = ReciboPDF().generate(
            self._make_bill(),
            billing_name="Apt 101",
            issuer_name="Maria Recebedora",
            payment_date="14/06/2026",
        )
        assert isinstance(result, (bytes, bytearray))
        assert result[:5] == b"%PDF-"

    def test_generate_without_issuer_and_payment_date(self):
        result = ReciboPDF().generate(
            self._make_bill(),
            billing_name="Apt 101",
            issuer_name="",
            payment_date="",
        )
        assert result[:5] == b"%PDF-"

    def test_generate_with_distinct_header_and_text_fonts(self):
        theme = Theme(header_font="Roboto", text_font="Open Sans")
        result = ReciboPDF().generate(
            self._make_bill(),
            billing_name="Apt 101",
            issuer_name="Maria Recebedora",
            payment_date="14/06/2026",
            theme=theme,
        )
        assert result[:5] == b"%PDF-"

    def test_recibo_is_a_single_page(self):
        """Regression: the footer sits below the bottom margin and used to spill
        the recibo onto a blank second page (only the footer line on page 2)."""
        import io

        import pypdf

        for kwargs in (
            dict(issuer_name="Maria Recebedora", payment_date="14/06/2026"),
            dict(issuer_name="", payment_date=""),
        ):
            result = ReciboPDF().generate(self._make_bill(), billing_name="Apt 101", **kwargs)
            assert len(pypdf.PdfReader(io.BytesIO(result)).pages) == 1

    def test_default_receipt_carries_the_rentivo_wordmark(self):
        import io

        import pypdf

        result = ReciboPDF().generate(
            self._make_bill(),
            billing_name="Apt 101",
            issuer_name="Maria Recebedora",
            payment_date="14/06/2026",
        )

        text = pypdf.PdfReader(io.BytesIO(result)).pages[0].extract_text()
        assert "rentivo" in text

    def test_received_amount_is_connected_to_the_payment_details(self):
        """The receipt reads as one ledger instead of a stack of detached cards."""
        import io

        import pypdf

        result = ReciboPDF().generate(
            self._make_bill(),
            billing_name="Apt 101",
            issuer_name="Maria Recebedora",
            payment_date="14/06/2026",
        )
        fragments: list[tuple[str, float]] = []
        pypdf.PdfReader(io.BytesIO(result)).pages[0].extract_text(
            visitor_text=lambda text, _cm, tm, _font, _size: (
                fragments.append((text.strip(), tm[5])) if text.strip() else None
            )
        )

        payment_date_label_y = next(y for text, y in fragments if text == "DATA DO PAGAMENTO")
        amount_label_y = next(y for text, y in fragments if text == "VALOR RECEBIDO")
        assert payment_date_label_y - amount_label_y <= 65
