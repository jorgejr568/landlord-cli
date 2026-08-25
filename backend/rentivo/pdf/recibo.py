from __future__ import annotations

from typing import TYPE_CHECKING

import structlog

from rentivo.constants import format_month
from rentivo.models import format_brl
from rentivo.models.bill import Bill
from rentivo.observability import traced
from rentivo.pdf.document import PdfDocument, draw_box, draw_document_header, draw_footer, new_document

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
        rows.append(("Referência", f"{billing_name} / {format_month(bill.reference_month)}"))
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
        draw_document_header(doc, title="RECIBO", subtitle="Comprovante de quitação")

    def _draw_success_badge(self, doc: PdfDocument) -> None:
        """Draw the confirmed-payment state as a branded status panel."""
        pdf = doc.pdf
        c = doc.colors
        x = pdf.l_margin
        y = pdf.get_y()
        panel_h = 20.0
        draw_box(doc, x, y, doc.page_w, panel_h, fill=c["primary_light"], shadow=False)

        mark_x = x + 7
        mark_y = y + 5
        mark_size = 10.0
        pdf.set_fill_color(*_SUCCESS_GREEN)
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.55)
        pdf.rect(mark_x, mark_y, mark_size, mark_size, style="DF", round_corners=True, corner_radius=2.0)

        cx = mark_x + mark_size / 2
        cy = mark_y + mark_size / 2
        pdf.set_draw_color(255, 255, 255)
        pdf.set_line_width(1.1)
        pdf.line(cx - 2.8, cy, cx - 0.8, cy + 2.3)
        pdf.line(cx - 0.8, cy + 2.3, cx + 3.0, cy - 2.2)
        pdf.set_line_width(0.2)

        pdf.set_xy(x + 23, y + 5)
        pdf.set_font(doc.header_font, "B", 12)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(doc.page_w - 30, 10, "PAGAMENTO CONFIRMADO")
        pdf.set_y(y + panel_h + 15)

    def _draw_details_table(self, doc: PdfDocument, rows: list[tuple[str, str]]) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        x = pdf.l_margin
        row_h = 13.0
        label_w = 54.0

        pdf.set_font(doc.header_font, "B", 11)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(0, 7, "DETALHES DO PAGAMENTO", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(3)

        start_y = pdf.get_y()
        draw_box(doc, x, start_y, page_w, row_h * len(rows), fill=c["text_contrast"])

        for i, (label, value) in enumerate(rows):
            y = pdf.get_y()
            if i:
                pdf.set_draw_color(*c["border_color"])
                pdf.set_line_width(0.25)
                pdf.line(x + 4, y, x + page_w - 4, y)
            pdf.set_xy(x + 7, y)
            pdf.set_font(doc.text_font, "B", 7.5)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(label_w, row_h, label.upper())
            pdf.set_xy(x + label_w, y)
            pdf.set_font(doc.text_font, "B", 10.5)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(page_w - label_w - 5, row_h, value)
            pdf.set_y(y + row_h)

        pdf.set_y(start_y + row_h * len(rows) + 16)

    def _draw_amount_box(self, doc: PdfDocument, total_centavos: int) -> None:
        """Draw the amount received as the final high-emphasis block."""
        pdf = doc.pdf
        c = doc.colors
        x = pdf.l_margin
        box_h = 30.0
        y = pdf.get_y()

        draw_box(doc, x, y, doc.page_w, box_h, fill=c["primary"], radius=4.0)
        pdf.set_xy(x + 10, y + 6)
        pdf.set_font(doc.text_font, "B", 8)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(doc.page_w * 0.36, 15, "VALOR RECEBIDO")
        pdf.set_font(doc.header_font, "B", 22)
        pdf.cell(doc.page_w * 0.55, 15, format_brl(total_centavos), align="R")

    def _draw_footer(self, doc: PdfDocument) -> None:
        # The footer sits below the bottom margin (offset -18), so writing its
        # text would otherwise trip auto page-break and spill onto a second page.
        # The recibo is a fixed single-page layout and the amount box above is
        # already positioned, so turning the break off here keeps it on page one.
        draw_footer(doc, offset=_FOOTER_OFFSET, gap=_FOOTER_GAP, disable_page_break=True)
