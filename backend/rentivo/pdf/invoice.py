from __future__ import annotations

from io import BytesIO
from typing import TYPE_CHECKING

import structlog

from rentivo.constants import TYPE_LABELS, format_month
from rentivo.models import format_brl
from rentivo.models.bill import Bill
from rentivo.observability import traced
from rentivo.pdf.document import PdfDocument, draw_footer, new_document

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

    def _draw_info_card(
        self,
        doc: PdfDocument,
        x: float,
        y: float,
        w: float,
        h: float,
        label: str,
        value: str,
    ) -> None:
        """Draw a single info card with accent bar, label, and value."""
        pdf = doc.pdf
        c = doc.colors
        pdf.set_fill_color(*c["primary_light"])
        pdf.rect(x, y, w, h, "F")
        pdf.set_fill_color(*c["secondary_dark"])
        pdf.rect(x, y, 3, h, "F")

        pdf.set_xy(x + 10, y + 3)
        pdf.set_font(doc.text_font_sb, "", 7)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(w - 14, 5, label, new_x="LEFT", new_y="NEXT")
        pdf.set_x(x + 10)
        pdf.set_font(doc.text_font, "B", 13)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(w - 14, 9, value)

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
        y = pdf.get_y()

        # Header banner
        pdf.set_fill_color(*c["primary"])
        pdf.rect(x, y, page_w, 40, "F")

        # Title
        pdf.set_y(y + 10)
        pdf.set_text_color(*c["text_contrast"])
        pdf.set_font(doc.header_font, "B", 28)
        pdf.cell(0, 14, "FATURA", align="C", new_x="LMARGIN", new_y="NEXT")

        pdf.set_font(doc.text_font, "", 9)
        pdf.set_text_color(210, 195, 215)
        pdf.cell(
            0,
            8,
            "Documento de cobran\u00e7a",
            align="C",
            new_x="LMARGIN",
            new_y="NEXT",
        )

        pdf.ln(10)

        # Info cards
        pdf.set_text_color(*c["text_color"])
        card_h = 24
        card_y = pdf.get_y()

        if due_date:
            self._draw_info_card(doc, x, card_y, page_w, card_h, "COBRAN\u00c7A", billing_name)

            row2_y = card_y + card_h + 6
            card_w = page_w / 2 - 3
            self._draw_info_card(
                doc,
                x,
                row2_y,
                card_w,
                card_h,
                "REFER\u00caNCIA",
                format_month(reference_month),
            )
            self._draw_info_card(doc, x + card_w + 6, row2_y, card_w, card_h, "VENCIMENTO", due_date)
            card_y = row2_y
        else:
            card_w = page_w / 2 - 3
            self._draw_info_card(doc, x, card_y, card_w, card_h, "COBRAN\u00c7A", billing_name)
            self._draw_info_card(
                doc,
                x + card_w + 6,
                card_y,
                card_w,
                card_h,
                "REFER\u00caNCIA",
                format_month(reference_month),
            )

        pdf.set_y(card_y + card_h + 14)

    def _draw_table(self, doc: PdfDocument, bill: Bill) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        col_desc = page_w * 0.50
        col_type = page_w * 0.22
        col_amount = page_w * 0.28
        line_h = 11

        # Section label
        pdf.set_font(doc.header_font, "B", 11)
        pdf.set_text_color(*c["primary"])
        pdf.cell(0, 8, "ITENS DA FATURA", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        # Accent underline
        pdf.set_draw_color(*c["secondary"])
        pdf.set_line_width(0.8)
        y = pdf.get_y()
        pdf.line(pdf.l_margin, y, pdf.l_margin + 30, y)
        pdf.ln(6)

        # Table header
        pdf.set_fill_color(*c["primary"])
        pdf.set_text_color(*c["text_contrast"])
        pdf.set_font(doc.text_font_sb, "", 9)

        pdf.cell(col_desc, line_h, "  Descri\u00e7\u00e3o", border=0, fill=True)
        pdf.cell(col_type, line_h, "Tipo", border=0, fill=True, align="C")
        pdf.cell(
            col_amount,
            line_h,
            "Valor  ",
            border=0,
            fill=True,
            align="R",
            new_x="LMARGIN",
            new_y="NEXT",
        )

        # Table rows
        pdf.set_text_color(*c["text_color"])
        pdf.set_font(doc.text_font, "", 10)

        for i, item in enumerate(bill.line_items):
            if i % 2 == 0:
                pdf.set_fill_color(*c["row_alt"])
            else:
                pdf.set_fill_color(*c["text_contrast"])

            pdf.cell(col_desc, line_h, f"  {item.description}", border=0, fill=True)

            type_label = TYPE_LABELS.get(item.item_type, item.item_type)
            pdf.set_font(doc.text_font, "", 9)
            pdf.cell(col_type, line_h, type_label, border=0, fill=True, align="C")
            pdf.set_font(doc.text_font_sb, "", 10)
            pdf.cell(
                col_amount,
                line_h,
                f"{format_brl(item.amount)}  ",
                border=0,
                fill=True,
                align="R",
                new_x="LMARGIN",
                new_y="NEXT",
            )
            pdf.set_font(doc.text_font, "", 10)

        # Bottom border
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.3)
        y = pdf.get_y()
        pdf.line(pdf.l_margin, y, pdf.l_margin + page_w, y)

    def _draw_total(self, doc: PdfDocument, total_amount: int) -> None:
        pdf = doc.pdf
        c = doc.colors
        pdf.ln(4)

        col_label = doc.page_w * 0.72
        col_amount = doc.page_w * 0.28
        total_h = 14

        pdf.set_fill_color(*c["secondary_dark"])
        pdf.set_text_color(*c["text_contrast"])
        pdf.set_font(doc.text_font_sb, "", 12)
        pdf.cell(col_label, total_h, "TOTAL  ", border=0, fill=True, align="R")
        pdf.set_font(doc.header_font, "B", 14)
        pdf.cell(
            col_amount,
            total_h,
            f"{format_brl(total_amount)}  ",
            border=0,
            fill=True,
            align="R",
            new_x="LMARGIN",
            new_y="NEXT",
        )

    def _draw_notes(self, doc: PdfDocument, notes: str) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        pdf.ln(14)

        pdf.set_font(doc.text_font_sb, "", 8)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(0, 6, "OBSERVA\u00c7ÕES", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)

        x = pdf.l_margin
        y = pdf.get_y()

        pdf.set_fill_color(*c["secondary"])
        pdf.rect(x, y, 3, 20, "F")
        pdf.set_fill_color(*c["primary_light"])
        pdf.rect(x + 3, y, page_w - 3, 20, "F")
        pdf.set_xy(x + 12, y + 6)
        pdf.set_text_color(*c["text_color"])
        pdf.set_font(doc.text_font, "", 10)
        pdf.multi_cell(page_w - 18, 6, notes)

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

        # Header banner
        y = pdf.get_y()
        pdf.set_fill_color(*c["primary"])
        pdf.rect(x, y, page_w, 30, "F")

        pdf.set_y(y + 8)
        pdf.set_text_color(*c["text_contrast"])
        pdf.set_font(doc.header_font, "B", 22)
        pdf.cell(0, 12, "PAGAMENTO VIA PIX", align="C", new_x="LMARGIN", new_y="NEXT")

        pdf.ln(16)

        # QR code
        qr_size = 55
        qr_x = x + (page_w - qr_size) / 2
        qr_y = pdf.get_y()

        buf = BytesIO(qrcode_png)
        pdf.image(buf, x=qr_x, y=qr_y, w=qr_size, h=qr_size)
        pdf.set_y(qr_y + qr_size + 6)

        # Instruction text
        pdf.set_font(doc.text_font, "", 10)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(
            0,
            6,
            "Escaneie o QR Code ou copie o c\u00f3digo abaixo",
            align="C",
            new_x="LMARGIN",
            new_y="NEXT",
        )

        pdf.ln(10)

        # Amount card
        card_h = 22
        card_y = pdf.get_y()
        pdf.set_fill_color(*c["secondary_dark"])
        pdf.rect(x, card_y, page_w, card_h, "F")

        pdf.set_xy(x + 10, card_y + 3)
        pdf.set_font(doc.text_font_sb, "", 8)
        pdf.set_text_color(180, 220, 220)
        pdf.cell(0, 5, "VALOR A PAGAR")
        pdf.set_xy(x + 10, card_y + 10)
        pdf.set_font(doc.header_font, "B", 18)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(0, 10, format_brl(total_amount))

        pdf.set_y(card_y + card_h + 12)

        # PIX key info card
        if pix_key:
            pdf.set_font(doc.text_font_sb, "", 8)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(0, 5, "CHAVE PIX", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(2)

            key_y = pdf.get_y()
            key_h = 14
            pdf.set_fill_color(*c["primary_light"])
            pdf.rect(x, key_y, page_w, key_h, "F")
            pdf.set_fill_color(*c["secondary_dark"])
            pdf.rect(x, key_y, 3, key_h, "F")

            pdf.set_xy(x + 10, key_y + 3)
            pdf.set_font(doc.text_font, "B", 11)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(0, 8, pix_key)

            pdf.set_y(key_y + key_h + 10)

        # Pix Copia e Cola
        if pix_payload:
            pdf.set_font(doc.text_font_sb, "", 8)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(0, 5, "PIX COPIA E COLA", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(2)

            payload_y = pdf.get_y()
            payload_cell_w = page_w - 12

            pdf.set_font(doc.text_font, "", 7)
            result = pdf.multi_cell(payload_cell_w, 4, pix_payload, dry_run=True, output="LINES")
            text_h = len(result) * 4
            payload_h = text_h + 8

            pdf.set_fill_color(*c["row_alt"])
            pdf.rect(x, payload_y, page_w, payload_h, "F")
            pdf.set_draw_color(*c["border_color"])
            pdf.set_line_width(0.3)
            pdf.rect(x, payload_y, page_w, payload_h, "D")

            pdf.set_xy(x + 6, payload_y + 4)
            pdf.set_font(doc.text_font, "", 7)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(payload_cell_w, 4, pix_payload)

            pdf.set_y(payload_y + payload_h + 4)

    def _draw_footer(self, doc: PdfDocument) -> None:
        draw_footer(doc, offset=_FOOTER_OFFSET, gap=_FOOTER_GAP)
