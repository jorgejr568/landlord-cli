from __future__ import annotations

from typing import TYPE_CHECKING

import structlog

from rentivo.constants import format_month
from rentivo.models import format_brl
from rentivo.models.bill import Bill
from rentivo.observability import traced
from rentivo.pdf.document import PdfDocument, draw_footer, new_document

if TYPE_CHECKING:
    from rentivo.models.theme import Theme

logger = structlog.get_logger(__name__)

# Success green is fixed (not theme-derived): the badge must read as "paid"
# regardless of the billing's theme palette.
_SUCCESS_GREEN = (22, 150, 95)

_FOOTER_OFFSET = -18
_FOOTER_GAP = 4


class ReciboPDF:
    @traced("pdf.generate_recibo")
    def generate(
        self,
        bill: Bill,
        billing_name: str,
        issuer_name: str,
        payment_date: str,
        theme: Theme | None = None,
    ) -> bytes:
        # The recibo layout never uses the semibold variants.
        doc = new_document(theme, semibold=False)
        pdf = doc.pdf

        rows: list[tuple[str, str]] = []
        if issuer_name:
            rows.append(("Emitente", issuer_name))
        rows.append(("Referência", f"{billing_name} — {format_month(bill.reference_month)}"))
        if payment_date:
            rows.append(("Data do pagamento", payment_date))

        self._draw_header(doc)
        self._draw_success_badge(doc)
        self._draw_details_table(doc, rows)
        self._draw_amount_box(doc, bill.total_amount)
        self._draw_footer(doc)

        output = pdf.output()
        logger.debug(
            "recibo_generated",
            billing_name=billing_name,
            total_centavos=bill.total_amount,
            bytes=len(output),
        )
        return output

    def _draw_header(self, doc: PdfDocument) -> None:
        pdf = doc.pdf
        c = doc.colors
        x = pdf.l_margin
        y = pdf.get_y()

        pdf.set_fill_color(*c["primary"])
        pdf.rect(x, y, doc.page_w, 40, "F")

        pdf.set_y(y + 10)
        pdf.set_text_color(*c["text_contrast"])
        pdf.set_font(doc.header_font, "B", 26)
        pdf.cell(0, 14, "RECIBO DE PAGAMENTO", align="C", new_x="LMARGIN", new_y="NEXT")

        pdf.set_font(doc.text_font, "", 9)
        pdf.set_text_color(210, 195, 215)
        pdf.cell(0, 8, "Comprovante de quitação", align="C", new_x="LMARGIN", new_y="NEXT")

        pdf.set_y(y + 40 + 14)

    def _draw_success_badge(self, doc: PdfDocument) -> None:
        """A green circle with a white check + 'PAGAMENTO CONFIRMADO' label."""
        pdf = doc.pdf
        cx = pdf.l_margin + doc.page_w / 2
        y = pdf.get_y() + 2
        r = 9.0

        pdf.set_fill_color(*_SUCCESS_GREEN)
        pdf.ellipse(cx - r, y, r * 2, r * 2, style="F")

        cy = y + r
        pdf.set_draw_color(255, 255, 255)
        pdf.set_line_width(1.6)
        pdf.line(cx - 4.2, cy + 0.4, cx - 1.4, cy + 3.6)
        pdf.line(cx - 1.4, cy + 3.6, cx + 4.6, cy - 3.4)
        pdf.set_line_width(0.2)

        pdf.set_xy(pdf.l_margin, y + r * 2 + 4)
        pdf.set_font(doc.header_font, "B", 11)
        pdf.set_text_color(*_SUCCESS_GREEN)
        pdf.cell(doc.page_w, 7, "PAGAMENTO CONFIRMADO", align="C", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(9)

    def _draw_details_table(self, doc: PdfDocument, rows: list[tuple[str, str]]) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        x = pdf.l_margin
        row_h = 12.0
        label_w = 58.0
        start_y = pdf.get_y()

        for i, (label, value) in enumerate(rows):
            y = pdf.get_y()
            if i % 2 == 1:
                pdf.set_fill_color(*c["row_alt"])
                pdf.rect(x, y, page_w, row_h, "F")
            pdf.set_xy(x + 5, y)
            pdf.set_font(doc.text_font, "", 9)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(label_w, row_h, label.upper())
            pdf.set_xy(x + label_w, y)
            pdf.set_font(doc.text_font, "B", 11)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(page_w - label_w - 5, row_h, value)
            pdf.set_y(y + row_h)

        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.3)
        pdf.rect(x, start_y, page_w, row_h * len(rows))
        pdf.set_line_width(0.2)

    def _draw_amount_box(self, doc: PdfDocument, total_centavos: int) -> None:
        """The amount received, anchored near the bottom of the page."""
        pdf = doc.pdf
        c = doc.colors
        x = pdf.l_margin
        box_h = 28.0
        y = pdf.h - pdf.b_margin - box_h - 14

        pdf.set_fill_color(*c["secondary_dark"])
        pdf.rect(x, y, doc.page_w, box_h, "F")
        pdf.set_xy(x + 12, y + 6)
        pdf.set_font(doc.text_font, "", 9)
        pdf.set_text_color(190, 222, 222)
        pdf.cell(0, 5, "VALOR RECEBIDO")
        pdf.set_xy(x + 12, y + 13)
        pdf.set_font(doc.header_font, "B", 24)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(0, 13, format_brl(total_centavos))

    def _draw_footer(self, doc: PdfDocument) -> None:
        # The footer sits below the bottom margin (offset -18), so writing its
        # text would otherwise trip auto page-break and spill onto a second page.
        # The recibo is a fixed single-page layout and the amount box above is
        # already positioned, so turning the break off here keeps it on page one.
        draw_footer(doc, offset=_FOOTER_OFFSET, gap=_FOOTER_GAP, disable_page_break=True)
