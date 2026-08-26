import io

import pypdf

from rentivo.models.bill import Bill, BillLineItem
from rentivo.models.billing import ItemType
from rentivo.pdf.invoice import InvoicePDF
from rentivo.pix import generate_pix_qrcode_png


class TestInvoicePDF:
    def _make_bill(self, **overrides):
        defaults = dict(
            id=1,
            uuid="test-uuid",
            billing_id=1,
            reference_month="2025-03",
            total_amount=295000,
            line_items=[
                BillLineItem(
                    description="Aluguel",
                    amount=285000,
                    item_type=ItemType.FIXED,
                    sort_order=0,
                ),
                BillLineItem(
                    description="Água",
                    amount=10000,
                    item_type=ItemType.VARIABLE,
                    sort_order=1,
                ),
            ],
            notes="",
            due_date="10/04/2025",
        )
        defaults.update(overrides)
        return Bill(**defaults)

    def test_generate_returns_pdf_bytes(self):
        pdf_gen = InvoicePDF()
        bill = self._make_bill()
        result = pdf_gen.generate(bill, "Apt 101")

        assert isinstance(result, (bytes, bytearray))
        assert result[:5] == b"%PDF-"

    def test_generate_with_notes(self):
        pdf_gen = InvoicePDF()
        bill = self._make_bill(notes="Test notes here")
        result = pdf_gen.generate(bill, "Apt 101")
        assert result[:5] == b"%PDF-"

    def test_generate_without_due_date(self):
        pdf_gen = InvoicePDF()
        bill = self._make_bill(due_date=None)
        result = pdf_gen.generate(bill, "Apt 101")
        assert result[:5] == b"%PDF-"

    def test_generate_with_pix_page(self):
        pdf_gen = InvoicePDF()
        bill = self._make_bill()
        pix_png = generate_pix_qrcode_png(
            pix_key="test@pix.com",
            merchant_name="Test",
            merchant_city="City",
            amount_centavos=295000,
        )
        result = pdf_gen.generate(
            bill,
            "Apt 101",
            pix_qrcode_png=pix_png,
            pix_key="test@pix.com",
            pix_payload="00020126...",
        )
        assert result[:5] == b"%PDF-"
        # With PIX page the PDF should be larger
        assert len(result) > 1000

    def test_generate_without_pix(self):
        pdf_gen = InvoicePDF()
        bill = self._make_bill()
        result = pdf_gen.generate(bill, "Apt 101")
        assert result[:5] == b"%PDF-"

    def test_generate_with_custom_theme(self):
        from rentivo.models.theme import Theme

        theme = Theme(
            header_font="Roboto",
            text_font="Open Sans",
            primary="#FF5733",
            primary_light="#FFD1C1",
            secondary="#33FF57",
            secondary_dark="#1E8C35",
            text_color="#111111",
            text_contrast="#FEFEFE",
        )
        pdf_gen = InvoicePDF()
        bill = self._make_bill()
        result = pdf_gen.generate(bill, "Apt 101", theme=theme)
        assert result[:5] == b"%PDF-"

    def test_generate_with_default_theme(self):
        from rentivo.models.theme import DEFAULT_THEME

        pdf_gen = InvoicePDF()
        bill = self._make_bill()
        result = pdf_gen.generate(bill, "Apt 101", theme=DEFAULT_THEME)
        assert result[:5] == b"%PDF-"

    def test_default_invoice_carries_the_rentivo_wordmark(self):
        result = InvoicePDF().generate(self._make_bill(), "Apt 101")

        text = "\n".join(page.extract_text() for page in pypdf.PdfReader(io.BytesIO(result)).pages)
        assert "rentivo" in text

    def test_generate_pix_no_key_no_payload(self):
        """Cover branches 362->383 and 383->exit: pix page without key or payload."""
        pdf_gen = InvoicePDF()
        bill = self._make_bill()
        pix_png = generate_pix_qrcode_png(
            pix_key="test@pix.com",
            merchant_name="Test",
            merchant_city="City",
            amount_centavos=295000,
        )
        result = pdf_gen.generate(
            bill,
            "Apt 101",
            pix_qrcode_png=pix_png,
            pix_key="",
            pix_payload="",
        )
        assert result[:5] == b"%PDF-"

    def test_many_items_continue_in_a_labeled_table_instead_of_a_total_only_page(self):
        """Regression: a tall monolithic table pushed TOTAL onto an otherwise blank page."""
        line_items = [
            BillLineItem(
                description=f"Item de cobrança {index:02d}",
                amount=10000 + index,
                item_type=ItemType.VARIABLE,
                sort_order=index,
            )
            for index in range(13)
        ]
        result = InvoicePDF().generate(
            self._make_bill(
                line_items=line_items,
                total_amount=sum(item.amount for item in line_items),
                notes="",
            ),
            "Apartamento Aurora",
        )

        pages = pypdf.PdfReader(io.BytesIO(result)).pages
        page_text = [page.extract_text() for page in pages]

        assert len(pages) == 2
        assert "ITENS DA FATURA" in page_text[1]
        assert "TOTAL" in page_text[1]
        assert all("rentivo" in text for text in page_text)

    def test_long_item_description_is_split_into_multiple_pdf_text_fragments(self):
        """Regression: a single-line description painted through the type and amount columns."""
        description = "Consumo de água da unidade conforme leitura individual homologada pela administradora"
        result = InvoicePDF().generate(
            self._make_bill(
                line_items=[
                    BillLineItem(
                        description=description,
                        amount=16892,
                        item_type=ItemType.VARIABLE,
                        sort_order=0,
                    )
                ],
                total_amount=16892,
            ),
            "Apartamento Aurora",
        )

        fragments: list[str] = []
        pypdf.PdfReader(io.BytesIO(result)).pages[0].extract_text(
            visitor_text=lambda text, *_args: fragments.append(text.strip()) if text.strip() else None
        )
        description_fragments = [
            fragment
            for fragment in fragments
            if "Consumo de água" in " ".join(fragment.split()) or "homologada" in fragment
        ]
        normalized = " ".join(" ".join(fragment.split()) for fragment in fragments)

        assert description not in fragments
        assert all("  " not in fragment for fragment in description_fragments)
        assert "Consumo de água da unidade conforme" in normalized
        assert "homologada pela administradora" in normalized

    def test_wrapped_notes_remain_left_aligned(self):
        """Regression: FPDF's default justification created distracting word gaps in notes."""
        notes = (
            "Cobrança em atraso. O valor exibido não inclui encargos posteriores à emissão deste documento. "
            "Entre em contato com o atendimento para confirmar o saldo atualizado antes do pagamento."
        )
        result = InvoicePDF().generate(self._make_bill(notes=notes), "Apartamento Aurora")

        fragments: list[str] = []
        pypdf.PdfReader(io.BytesIO(result)).pages[0].extract_text(
            visitor_text=lambda text, *_args: fragments.append(text.strip()) if text.strip() else None
        )
        notes_fragments = [
            fragment
            for fragment in fragments
            if "Cobrança em atraso" in " ".join(fragment.split()) or "saldo atualizado" in fragment
        ]

        assert notes_fragments
        assert all("  " not in fragment for fragment in notes_fragments)
