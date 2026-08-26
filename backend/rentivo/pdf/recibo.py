from __future__ import annotations

from typing import TYPE_CHECKING

import structlog

from rentivo.constants import format_month
from rentivo.models import format_brl
from rentivo.models.bill import Bill
from rentivo.observability import traced
from rentivo.pdf.document import PdfDocument, draw_document_header, draw_footer, new_document

if TYPE_CHECKING:
    from rentivo.models.theme import Theme

logger = structlog.get_logger(__name__)

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
        doc = new_document(theme, semibold=False)
        rows: list[tuple[str, str]] = [
            ("Cobrança", billing_name),
            ("Referência", format_month(bill.reference_month)),
        ]
        if issuer_name:
            rows.append(("Emitente", issuer_name))
        if payment_date:
            rows.append(("Data do pagamento", payment_date))

        self._draw_header(doc)
        self._draw_confirmation(doc)
        self._draw_receipt_ledger(doc, rows, bill.total_amount)
        self._draw_footer(doc)

        output = doc.pdf.output()
        logger.debug(
            "recibo_generated",
            billing_name=billing_name,
            total_centavos=bill.total_amount,
            bytes=len(output),
        )
        return output

    @staticmethod
    def _draw_header(doc: PdfDocument) -> None:
        draw_document_header(
            doc,
            title="RECIBO DE PAGAMENTO",
            subtitle="Comprovante de quitação",
            show_wordmark=False,
        )

    @staticmethod
    def _draw_confirmation(doc: PdfDocument) -> None:
        pdf = doc.pdf
        c = doc.colors
        x = pdf.l_margin
        y = pdf.get_y()
        mark_size = 9.0

        pdf.set_fill_color(*_SUCCESS_GREEN)
        pdf.ellipse(x, y, mark_size, mark_size, style="F")
        cx = x + mark_size / 2
        cy = y + mark_size / 2
        pdf.set_draw_color(255, 255, 255)
        pdf.set_line_width(1.0)
        pdf.line(cx - 2.5, cy, cx - 0.7, cy + 2.0)
        pdf.line(cx - 0.7, cy + 2.0, cx + 2.7, cy - 2.0)

        pdf.set_xy(x + 13, y - 0.3)
        pdf.set_font(doc.header_font, "B", 11)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(doc.page_w - 13, 5, "PAGAMENTO CONFIRMADO")
        pdf.set_xy(x + 13, y + 5.2)
        pdf.set_font(doc.text_font, "", 8.5)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(doc.page_w - 13, 5, "Este documento confirma a quitação da cobrança abaixo.")
        pdf.set_y(y + 17)

    def _draw_receipt_ledger(
        self,
        doc: PdfDocument,
        rows: list[tuple[str, str]],
        total_centavos: int,
    ) -> None:
        pdf = doc.pdf
        c = doc.colors
        x = pdf.l_margin
        y = pdf.get_y()
        page_w = doc.page_w
        amount_h = 38.0
        heading_h = 15.0
        label_w = 48.0

        measured: list[tuple[str, str, list[str], float]] = []
        pdf.set_font(doc.text_font, "B", 10)
        for label, value in rows:
            lines = pdf.multi_cell(
                page_w - label_w - 14,
                5,
                value,
                align="L",
                dry_run=True,
                output="LINES",
            )
            measured.append((label, value, lines, max(13.0, len(lines) * 5 + 7)))

        detail_h = sum(row_h for _, _, _, row_h in measured)
        panel_h = amount_h + heading_h + detail_h

        pdf.set_fill_color(*c["secondary_dark"])
        pdf.rect(x + 1.4, y + 1.4, page_w, panel_h, style="F", round_corners=True, corner_radius=3.2)
        pdf.set_fill_color(255, 255, 255)
        pdf.rect(x, y, page_w, panel_h, style="F", round_corners=True, corner_radius=3.2)

        pdf.set_fill_color(*c["primary"])
        pdf.rect(x, y, page_w, amount_h, style="F", round_corners=True, corner_radius=3.2)
        pdf.rect(x, y + amount_h - 4, page_w, 4, style="F")
        pdf.set_xy(x + 10, y + 7)
        pdf.set_font(doc.text_font, "B", 8)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(page_w - 20, 5, "VALOR RECEBIDO")
        pdf.set_xy(x + 10, y + 15)
        pdf.set_font(doc.header_font, "B", 23)
        pdf.cell(page_w - 20, 13, format_brl(total_centavos))

        heading_y = y + amount_h
        pdf.set_fill_color(*c["secondary"])
        pdf.rect(x, heading_y, page_w, heading_h, style="F")
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.35)
        pdf.line(x, heading_y, x + page_w, heading_y)
        pdf.line(x, heading_y + heading_h, x + page_w, heading_y + heading_h)
        pdf.set_xy(x + 8, heading_y + 4.5)
        pdf.set_font(doc.header_font, "B", 10.5)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(page_w - 16, 6, "DETALHES DO PAGAMENTO")

        row_y = heading_y + heading_h
        for index, (label, _value, lines, row_h) in enumerate(measured):
            if index:
                pdf.set_draw_color(*c["border_color"])
                pdf.set_line_width(0.25)
                pdf.line(x + 6, row_y, x + page_w - 6, row_y)
            pdf.set_xy(x + 8, row_y + (row_h - 5) / 2)
            pdf.set_font(doc.text_font, "B", 7.2)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(label_w - 8, 5, label.upper())
            text_h = len(lines) * 5
            pdf.set_xy(x + label_w, row_y + (row_h - text_h) / 2)
            pdf.set_font(doc.text_font, "B", 10)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(page_w - label_w - 8, 5, "\n".join(lines), align="L", max_line_height=5)
            row_y += row_h

        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.6)
        pdf.rect(x, y, page_w, panel_h, style="D", round_corners=True, corner_radius=3.2)

        pdf.set_y(y + panel_h + 8)
        pdf.set_font(doc.text_font, "", 7.5)
        pdf.set_text_color(*c["muted_text"])
        pdf.multi_cell(
            page_w,
            4.5,
            "Guarde este comprovante para seus registros. A autenticidade dos dados acompanha a cobrança emitida.",
            align="L",
        )

    @staticmethod
    def _draw_footer(doc: PdfDocument) -> None:
        draw_footer(doc, offset=_FOOTER_OFFSET, gap=_FOOTER_GAP, disable_page_break=True)
