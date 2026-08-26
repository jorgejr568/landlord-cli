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

    def test_pix_page_keeps_the_invoice_identity_in_its_running_header(self):
        """The payment page must read as page two of the same invoice."""
        bill = self._make_bill()
        pix_png = generate_pix_qrcode_png(
            pix_key="test@pix.com",
            merchant_name="Test",
            merchant_city="City",
            amount_centavos=295000,
        )

        result = InvoicePDF().generate(
            bill,
            "Apartamento Aurora",
            pix_qrcode_png=pix_png,
            pix_key="test@pix.com",
            pix_payload="00020126...",
        )

        payment_page = pypdf.PdfReader(io.BytesIO(result)).pages[1].extract_text()
        assert "FATURA" in payment_page
        assert "Apartamento Aurora" in payment_page
        assert "Março/2025" in payment_page
        assert "PAGUE COM PIX" in payment_page

    def test_total_is_visually_connected_to_the_final_invoice_item(self):
        """The total belongs to the item ledger instead of floating as another card."""
        result = InvoicePDF().generate(self._make_bill(), "Apartamento Aurora")
        fragments: list[tuple[str, float]] = []
        pypdf.PdfReader(io.BytesIO(result)).pages[0].extract_text(
            visitor_text=lambda text, _cm, tm, _font, _size: (
                fragments.append((text.strip(), tm[5])) if text.strip() else None
            )
        )

        final_item_y = next(y for text, y in fragments if text == "Água")
        total_y = next(y for text, y in fragments if text == "TOTAL A PAGAR")
        assert final_item_y - total_y <= 48

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

    def test_continuation_pages_repeat_the_invoice_identity(self):
        """Every generated invoice page must remain identifiable on its own."""
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
            ),
            "Apartamento Aurora",
        )

        page_text = [page.extract_text() for page in pypdf.PdfReader(io.BytesIO(result)).pages]
        assert len(page_text) == 2
        assert all("Apartamento Aurora" in text for text in page_text)
        assert all("Março/2025" in text for text in page_text)

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

    def test_long_billing_name_expands_header_before_items_heading(self):
        """Regression: a fixed-height metadata card let long names overlap the table heading."""
        billing_name = " ".join(
            [
                "Condomínio Residencial Jardim das Palmeiras - Torre Ipê - Unidade 1204 - "
                "Administração Patrimonial Ribeiro e Filhos"
            ]
            * 3
        )
        result = InvoicePDF().generate(self._make_bill(), billing_name)

        fragments: list[tuple[str, float]] = []
        page = pypdf.PdfReader(io.BytesIO(result)).pages[0]
        page.extract_text(
            visitor_text=lambda text, _cm, tm, _font, _size: (
                fragments.append((text.strip(), tm[5])) if text.strip() else None
            )
        )
        billing_label = next(index for index, (text, _) in enumerate(fragments) if text == "COBRANÇA")
        reference_label = next(index for index, (text, _) in enumerate(fragments) if text == "REFERÊNCIA")
        items_heading_y = next(y for text, y in fragments if text == "ITENS DA FATURA")
        billing_line_y = [y for _, y in fragments[billing_label + 1 : reference_label]]
        billing_fragments = [text for text, _ in fragments[billing_label + 1 : reference_label]]

        assert billing_line_y
        assert min(billing_line_y) >= items_heading_y + 18
        assert all("  " not in fragment for fragment in billing_fragments)

    def test_expanded_header_keeps_the_item_ledger_below_its_metadata(self):
        """A tall billing identity must not overlap the connected item ledger."""
        billing_name = " ".join(
            [
                "Condomínio Residencial Jardim das Palmeiras - Torre Ipê - Unidade 1204 - "
                "Administração Patrimonial Ribeiro e Filhos"
            ]
            * 8
        )
        line_item = BillLineItem(
            description="Aluguel residencial",
            amount=385000,
            item_type=ItemType.FIXED,
            sort_order=0,
        )
        result = InvoicePDF().generate(
            self._make_bill(line_items=[line_item], total_amount=line_item.amount),
            billing_name,
        )

        page_text = [page.extract_text() for page in pypdf.PdfReader(io.BytesIO(result)).pages]

        assert len(page_text) == 2
        assert "ITENS DA FATURA" not in page_text[0]
        assert "ITENS DA FATURA" in page_text[-1]
        assert "Aluguel residencial" in page_text[-1]
        assert "TOTAL A PAGAR" in page_text[-1]
        assert "Condomínio Residencial" in page_text[-1]
        assert all("Documento gerado automaticamente" in text for text in page_text)

    def test_extraordinarily_tall_item_is_split_across_branded_table_pages(self):
        """Regression: FPDF auto-break split one row's description, type, and amount into bare pages."""
        phrase = (
            "Consumo de água e esgoto conforme leitura individual da concessionária, incluindo rateio "
            "das áreas comuns, ajustes retroativos, encargos operacionais e memória detalhada de cálculo "
            "do período."
        )
        result = InvoicePDF().generate(
            self._make_bill(
                line_items=[
                    BillLineItem(
                        description=" ".join([phrase] * 8),
                        amount=16892,
                        item_type=ItemType.VARIABLE,
                        sort_order=0,
                    )
                ],
                total_amount=16892,
            ),
            "Apartamento Aurora",
        )

        page_text = [page.extract_text() for page in pypdf.PdfReader(io.BytesIO(result)).pages]
        type_pages = [index for index, text in enumerate(page_text) if "Variável" in text]

        assert len(page_text) >= 2
        assert all("rentivo" in text and "FATURA" in text and "ITENS DA FATURA" in text for text in page_text)
        assert type_pages == [len(page_text) - 1]
        assert "R$ 168,92" in page_text[type_pages[0]]
        assert "TOTAL" in page_text[-1]

    def test_final_tall_fragment_keeps_type_and_value_for_its_last_page(self):
        """A row that fits alone still splits when the invoice summary needs the remaining room."""
        item = BillLineItem(
            description="Descrição extensa",
            amount=16892,
            item_type=ItemType.VARIABLE,
            sort_order=0,
        )
        pending_rows = [(item, [f"Linha {index}" for index in range(5)], True)]

        page_rows = InvoicePDF()._take_table_page(pending_rows, available_h=30)

        assert page_rows == [(item, ["Linha 0", "Linha 1", "Linha 2", "Linha 3"], False)]
        assert pending_rows == [(item, ["Linha 4"], True)]

    def test_ordinary_final_row_moves_whole_when_the_summary_needs_the_page(self):
        """A normal row never splits just to squeeze the summary onto its page."""
        first = BillLineItem(
            description="Primeiro item",
            amount=10000,
            item_type=ItemType.FIXED,
            sort_order=0,
        )
        final = BillLineItem(
            description="Último item",
            amount=20000,
            item_type=ItemType.VARIABLE,
            sort_order=1,
        )
        pending_rows = [(first, [first.description], True), (final, [final.description], True)]

        page_rows = InvoicePDF()._take_table_page(pending_rows, available_h=23)

        assert page_rows == [(first, [first.description], True)]
        assert pending_rows == [(final, [final.description], True)]

    def test_long_notes_repeat_observations_container_on_branded_pages(self):
        """Regression: automatic note overflow created a page without invoice furniture."""
        phrase = (
            "Cobrança em atraso. O valor exibido não inclui encargos posteriores à emissão deste documento. "
            "Entre em contato para confirmar o saldo atualizado."
        )
        result = InvoicePDF().generate(
            self._make_bill(notes=" ".join([phrase] * 14)),
            "Apartamento Aurora",
        )

        page_text = [page.extract_text() for page in pypdf.PdfReader(io.BytesIO(result)).pages]

        assert len(page_text) >= 2
        assert all("rentivo" in text and "FATURA" in text and "OBSERVAÇÕES" in text for text in page_text)
        assert all("Documento gerado automaticamente" in text for text in page_text)
        assert sum(text.count("Cobrança") for text in page_text) == 14
