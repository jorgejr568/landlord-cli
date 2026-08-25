from __future__ import annotations

from io import BytesIO
from typing import TYPE_CHECKING

import structlog

from rentivo.constants import TYPE_LABELS, format_month
from rentivo.models import format_brl
from rentivo.models.bill import Bill
from rentivo.observability import traced
from rentivo.pdf.document import PdfDocument, draw_box, draw_document_header, draw_footer, new_document

if TYPE_CHECKING:
    from rentivo.models.theme import Theme

logger = structlog.get_logger(__name__)

# The invoice footer clears the 20mm bottom margin, so auto page-break can stay
# on: nothing it draws lands below the break threshold.
_FOOTER_OFFSET = -30
_FOOTER_GAP = 5


class InvoicePDF:
    @traced("pdf.generate")
    def generate(
        self,
        bill: Bill,
        billing_name: str,
        pix_qrcode_png: bytes | None = None,
        pix_key: str = "",
        pix_payload: str = "",
        theme: Theme | None = None,
    ) -> bytes:
        doc = new_document(theme)
        pdf = doc.pdf

        self._draw_header(doc, billing_name, bill.reference_month, bill.due_date)
        self._draw_table(doc, bill)
        self._draw_total(doc, bill.total_amount)

        if bill.notes:
            self._draw_notes(doc, bill.notes)

        self._draw_footer(doc)

        if pix_qrcode_png:
            pdf.add_page()
            self._draw_pix_page(doc, pix_qrcode_png, bill.total_amount, pix_key, pix_payload)
            self._draw_footer(doc)

        output = pdf.output()
        logger.debug(
            "pdf_generated",
            billing_name=billing_name,
            line_item_count=len(bill.line_items),
            has_pix=bool(pix_qrcode_png),
            bytes=len(output),
        )
        return output

    def _draw_header(
        self,
        doc: PdfDocument,
        billing_name: str,
        reference_month: str,
        due_date: str | None = None,
    ) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        x = pdf.l_margin
        draw_document_header(doc, title="FATURA", subtitle="Documento de cobran\u00e7a")

        fields = [("COBRAN\u00c7A", billing_name), ("REFER\u00caNCIA", format_month(reference_month))]
        if due_date:
            fields.append(("VENCIMENTO", due_date))

        widths = [page_w * 0.50, page_w * 0.25, page_w * 0.25] if due_date else [page_w * 0.62, page_w * 0.38]
        card_y = pdf.get_y()
        card_h = 28.0
        draw_box(doc, x, card_y, page_w, card_h, fill=c["text_contrast"])

        field_x = x
        for index, ((label, value), field_w) in enumerate(zip(fields, widths, strict=True)):
            if index:
                pdf.set_draw_color(*c["border_color"])
                pdf.set_line_width(0.45)
                pdf.line(field_x, card_y + 4, field_x, card_y + card_h - 4)
            pdf.set_xy(field_x + 7, card_y + 5)
            pdf.set_font(doc.text_font_sb, "", 7)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(field_w - 12, 5, label)
            pdf.set_xy(field_x + 7, card_y + 12)
            pdf.set_font(doc.header_font, "B", 12)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(field_w - 12, 5.5, value, max_line_height=5.5)
            field_x += field_w

        pdf.set_y(card_y + card_h + 15)

    def _draw_table(self, doc: PdfDocument, bill: Bill) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        col_desc = page_w * 0.50
        col_type = page_w * 0.22
        col_amount = page_w * 0.28
        line_h = 11.5

        pdf.set_font(doc.header_font, "B", 12)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(page_w * 0.70, 8, "ITENS DA FATURA")
        pdf.set_font(doc.text_font_sb, "", 7)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(page_w * 0.30, 8, f"{len(bill.line_items)} ITENS", align="R", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(3)

        table_x = pdf.l_margin
        table_y = pdf.get_y()
        table_h = line_h * (len(bill.line_items) + 1)
        draw_box(doc, table_x, table_y, page_w, table_h, fill=c["text_contrast"])

        pdf.set_fill_color(*c["primary_light"])
        pdf.rect(table_x + 0.65, table_y + 0.65, page_w - 1.3, line_h - 0.65, style="F")
        pdf.set_xy(table_x, table_y)
        pdf.set_font(doc.text_font_sb, "", 8)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(col_desc, line_h, "  DESCRI\u00c7\u00c3O")
        pdf.cell(col_type, line_h, "TIPO", align="C")
        pdf.cell(col_amount, line_h, "VALOR  ", align="R", new_x="LMARGIN", new_y="NEXT")

        for item in bill.line_items:
            row_y = pdf.get_y()
            pdf.set_draw_color(*c["border_color"])
            pdf.set_line_width(0.25)
            pdf.line(table_x + 4, row_y, table_x + page_w - 4, row_y)

            pdf.set_font(doc.text_font, "", 9.5)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(col_desc, line_h, f"  {item.description}")
            pdf.set_font(doc.text_font, "", 8.5)
            pdf.cell(col_type, line_h, TYPE_LABELS.get(item.item_type, item.item_type), align="C")
            pdf.set_font(doc.text_font_sb, "", 9.5)
            pdf.cell(
                col_amount,
                line_h,
                f"{format_brl(item.amount)}  ",
                align="R",
                new_x="LMARGIN",
                new_y="NEXT",
            )

        pdf.set_y(table_y + table_h + 5)

    def _draw_total(self, doc: PdfDocument, total_amount: int) -> None:
        pdf = doc.pdf
        c = doc.colors
        total_w = doc.page_w * 0.54
        total_h = 18.0
        x = pdf.l_margin + doc.page_w - total_w
        y = pdf.get_y()

        draw_box(doc, x, y, total_w, total_h, fill=c["primary"], radius=3.0)
        pdf.set_xy(x + 7, y + 4)
        pdf.set_font(doc.text_font_sb, "", 8)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(total_w * 0.36, 10, "TOTAL")
        pdf.set_font(doc.header_font, "B", 15.5)
        pdf.cell(total_w * 0.54, 10, format_brl(total_amount), align="R")
        pdf.set_y(y + total_h + 2)

    def _draw_notes(self, doc: PdfDocument, notes: str) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        pdf.ln(12)

        pdf.set_font(doc.header_font, "B", 11)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(0, 7, "OBSERVA\u00c7ÕES", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(3)

        x = pdf.l_margin
        y = pdf.get_y()

        pdf.set_font(doc.text_font, "", 9.5)
        lines = pdf.multi_cell(page_w - 16, 5.5, notes, dry_run=True, output="LINES")
        notes_h = max(20.0, len(lines) * 5.5 + 10)
        draw_box(doc, x, y, page_w, notes_h, fill=c["primary_light"], shadow=False)
        pdf.set_xy(x + 8, y + 5)
        pdf.set_text_color(*c["text_color"])
        pdf.set_font(doc.text_font, "", 9.5)
        pdf.multi_cell(page_w - 16, 5.5, notes)
        pdf.set_y(y + notes_h)

    def _draw_pix_page(
        self,
        doc: PdfDocument,
        qrcode_png: bytes,
        total_amount: int,
        pix_key: str,
        pix_payload: str,
    ) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        x = pdf.l_margin
        draw_document_header(doc, title="PAGUE COM PIX", subtitle="Pagamento seguro pelo aplicativo do seu banco")

        qr_panel = 72.0
        qr_y = pdf.get_y()
        draw_box(doc, x, qr_y, qr_panel, qr_panel, fill=c["text_contrast"], radius=4.0)
        qr_size = 56.0
        qr_x = x + (qr_panel - qr_size) / 2
        buf = BytesIO(qrcode_png)
        pdf.image(buf, x=qr_x, y=qr_y + (qr_panel - qr_size) / 2, w=qr_size, h=qr_size)

        aside_x = x + qr_panel + 10
        aside_w = page_w - qr_panel - 10
        amount_h = 28.0
        draw_box(doc, aside_x, qr_y, aside_w, amount_h, fill=c["primary"], radius=3.0)
        pdf.set_xy(aside_x + 7, qr_y + 5)
        pdf.set_font(doc.text_font_sb, "", 7.5)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(aside_w - 14, 5, "VALOR A PAGAR")
        pdf.set_xy(aside_x + 7, qr_y + 12)
        pdf.set_font(doc.header_font, "B", 17)
        pdf.cell(aside_w - 14, 10, format_brl(total_amount))

        pdf.set_xy(aside_x + 2, qr_y + amount_h + 9)
        pdf.set_font(doc.header_font, "B", 10.5)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(aside_w - 2, 6, "COMO PAGAR")
        pdf.set_xy(aside_x + 2, qr_y + amount_h + 18)
        pdf.set_font(doc.text_font, "", 8.5)
        pdf.set_text_color(*c["muted_text"])
        pdf.multi_cell(
            aside_w - 2,
            5.5,
            "1. Abra o aplicativo do seu banco.\n2. Escolha pagar com PIX.\n3. Escaneie o QR Code ao lado.",
        )

        pdf.set_y(qr_y + qr_panel + 15)

        # PIX key info card
        if pix_key:
            pdf.set_font(doc.header_font, "B", 10.5)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(0, 6, "CHAVE PIX", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(3)

            key_y = pdf.get_y()
            key_h = 16
            draw_box(doc, x, key_y, page_w, key_h, fill=c["primary_light"], shadow=False)
            pdf.set_xy(x + 7, key_y + 3.5)
            pdf.set_font(doc.text_font, "B", 11)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(0, 8, pix_key)

            pdf.set_y(key_y + key_h + 10)

        # Pix Copia e Cola
        if pix_payload:
            pdf.set_font(doc.header_font, "B", 10.5)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(0, 6, "PIX COPIA E COLA", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(3)

            payload_y = pdf.get_y()
            payload_cell_w = page_w - 14

            pdf.set_font(doc.text_font, "", 7)
            result = pdf.multi_cell(
                payload_cell_w,
                4,
                pix_payload,
                align="L",
                wrapmode="CHAR",
                dry_run=True,
                output="LINES",
            )
            text_h = len(result) * 4
            payload_h = text_h + 10
            draw_box(doc, x, payload_y, page_w, payload_h, fill=c["primary_light"], shadow=False)

            pdf.set_xy(x + 7, payload_y + 5)
            pdf.set_font(doc.text_font, "", 7)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(payload_cell_w, 4, pix_payload, align="L", wrapmode="CHAR")

            pdf.set_y(payload_y + payload_h + 4)

    def _draw_footer(self, doc: PdfDocument) -> None:
        draw_footer(doc, offset=_FOOTER_OFFSET, gap=_FOOTER_GAP)
