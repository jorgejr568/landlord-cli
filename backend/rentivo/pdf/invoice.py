from __future__ import annotations

from io import BytesIO
from typing import TYPE_CHECKING

import structlog

from rentivo.constants import TYPE_LABELS, format_month
from rentivo.models import format_brl
from rentivo.models.bill import Bill, BillLineItem
from rentivo.observability import traced
from rentivo.pdf.document import PdfDocument, draw_document_header, draw_footer, new_document

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
        self._draw_table(doc, bill, billing_name)
        self._draw_total(doc, bill.total_amount)

        if bill.notes:
            self._draw_notes(doc, bill.notes, billing_name, bill.reference_month)

        self._draw_footer(doc)

        if pix_qrcode_png:
            pdf.add_page()
            self._draw_pix_page(
                doc,
                pix_qrcode_png,
                bill.total_amount,
                pix_key,
                pix_payload,
                billing_name=billing_name,
                reference_month=bill.reference_month,
            )
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
        draw_document_header(
            doc,
            title="FATURA",
            subtitle="Documento de cobran\u00e7a",
            show_wordmark=False,
        )

        fields = [("COBRAN\u00c7A", billing_name), ("REFER\u00caNCIA", format_month(reference_month))]
        if due_date:
            fields.append(("VENCIMENTO", due_date))

        widths = [page_w * 0.50, page_w * 0.25, page_w * 0.25] if due_date else [page_w * 0.62, page_w * 0.38]
        pdf.set_font(doc.header_font, "B", 12)
        value_lines = [
            pdf.multi_cell(
                field_w - 12,
                5.5,
                value,
                align="L",
                dry_run=True,
                output="LINES",
            )
            for (_, value), field_w in zip(fields, widths, strict=True)
        ]
        metadata_y = pdf.get_y()
        metadata_h = max(27.0, max(len(lines) for lines in value_lines) * 5.5 + 17.0)
        pdf.set_fill_color(*c["secondary"])
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.65)
        pdf.rect(x, metadata_y, page_w, metadata_h, style="DF")

        field_x = x
        for index, ((label, value), field_w) in enumerate(zip(fields, widths, strict=True)):
            if index:
                pdf.set_draw_color(*c["border_color"])
                pdf.set_line_width(0.45)
                pdf.line(field_x, metadata_y + 4, field_x, metadata_y + metadata_h - 4)
            pdf.set_xy(field_x + 7, metadata_y + 5)
            pdf.set_font(doc.text_font_sb, "", 7)
            pdf.set_text_color(*c["muted_text"])
            pdf.cell(field_w - 12, 5, label)
            pdf.set_xy(field_x + 7, metadata_y + 12)
            pdf.set_font(doc.header_font, "B", 12)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(field_w - 12, 5.5, value, align="L", max_line_height=5.5)
            field_x += field_w

        pdf.set_y(metadata_y + metadata_h + 12)

    def _draw_table(self, doc: PdfDocument, bill: Bill, billing_name: str) -> None:
        pdf = doc.pdf
        rows = self._measure_table_rows(doc, bill.line_items)
        total_rows = len(rows)
        content_bottom = pdf.h + _FOOTER_OFFSET - 7
        summary_h = self._summary_height(doc, bill.notes)
        continuation = False

        while rows:
            heading_h = 11.0
            header_h = 11.5
            first_row_h = self._table_row_height(rows[0][1])
            required_h = heading_h + header_h + first_row_h + summary_h
            fresh_rows_h = content_bottom - (pdf.t_margin + 52.0 + heading_h + header_h)
            first_row_fits_fresh = first_row_h + summary_h <= fresh_rows_h
            if not continuation and first_row_fits_fresh and pdf.get_y() + required_h > content_bottom:
                self._start_table_continuation(doc, billing_name, bill.reference_month)
                continuation = True

            self._draw_table_heading(doc, total_rows, continuation=continuation)
            table_y = pdf.get_y()
            available_h = content_bottom - table_y - header_h
            remaining_h = sum(self._table_row_height(lines) for _, lines, _ in rows)

            if remaining_h + summary_h <= available_h:
                self._draw_table_group(doc, rows)
                return

            page_rows = self._take_table_page(rows, available_h)
            self._draw_table_group(doc, page_rows)
            self._start_table_continuation(doc, billing_name, bill.reference_month)
            continuation = True

    def _start_table_continuation(self, doc: PdfDocument, billing_name: str, reference_month: str) -> None:
        self._draw_footer(doc)
        doc.pdf.add_page()
        draw_document_header(
            doc,
            title="FATURA",
            subtitle=f"{billing_name}  ·  {format_month(reference_month)}  ·  Itens - continuação",
            show_wordmark=False,
        )

    def _take_table_page(
        self,
        rows: list[tuple[BillLineItem, list[str], bool]],
        available_h: float,
    ) -> list[tuple[BillLineItem, list[str], bool]]:
        page_rows: list[tuple[BillLineItem, list[str], bool]] = []
        used_h = 0.0

        while rows:
            item, lines, show_values = rows[0]
            row_h = self._table_row_height(lines)
            room_h = available_h - used_h

            if row_h <= room_h and len(rows) > 1:
                page_rows.append(rows.pop(0))
                used_h += row_h
                continue

            if row_h <= room_h and page_rows:
                # A normal final row belongs with the summary. Move it intact
                # instead of leaving its description on one page and values on
                # the next.
                break

            if row_h <= room_h:
                # All content fits, but the caller already established that the
                # summary does not. With no previous rows to preserve on this
                # page, this is an over-tall row: keep its final line for the
                # fragment that owns type and value.
                max_lines = len(lines) - 1
                page_rows.append((item, lines[:max_lines], False))
                rows[0] = (item, lines[max_lines:], show_values)
                break

            if page_rows:
                break

            # A non-fitting first row has at least two lines: one-line rows use
            # the 11.5mm minimum height and fit the page budget. Keep at least
            # one line for the final fragment, where type and value are drawn.
            max_lines = min(len(lines) - 1, max(1, int((room_h - 5) // 5)))

            page_rows.append((item, lines[:max_lines], False))
            rows[0] = (item, lines[max_lines:], show_values)
            break

        return page_rows

    @staticmethod
    def _table_row_height(lines: list[str]) -> float:
        return max(11.5, len(lines) * 5 + 5)

    def _measure_table_rows(
        self,
        doc: PdfDocument,
        items: list[BillLineItem],
    ) -> list[tuple[BillLineItem, list[str], bool]]:
        pdf = doc.pdf
        description_w = doc.page_w * 0.50 - 10
        pdf.set_font(doc.text_font, "", 9.5)
        rows: list[tuple[BillLineItem, list[str], bool]] = []
        for item in items:
            lines = pdf.multi_cell(
                description_w,
                5,
                item.description,
                align="L",
                dry_run=True,
                output="LINES",
            )
            rows.append((item, lines, True))
        return rows

    def _draw_table_heading(self, doc: PdfDocument, item_count: int, *, continuation: bool) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        title = "ITENS DA FATURA (CONTINUAÇÃO)" if continuation else "ITENS DA FATURA"

        pdf.set_font(doc.header_font, "B", 12)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(page_w * 0.70, 8, title)
        pdf.set_font(doc.text_font_sb, "", 7)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(page_w * 0.30, 8, f"{item_count} ITENS", align="R", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(3)

    def _draw_table_group(
        self,
        doc: PdfDocument,
        rows: list[tuple[BillLineItem, list[str], bool]],
    ) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        col_desc = page_w * 0.50
        col_type = page_w * 0.22
        col_amount = page_w * 0.28
        header_h = 11.5
        table_x = pdf.l_margin
        table_y = pdf.get_y()
        table_h = header_h + sum(self._table_row_height(lines) for _, lines, _ in rows)

        pdf.set_fill_color(*c["primary_light"])
        pdf.rect(table_x, table_y, page_w, header_h, style="F")
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.65)
        pdf.rect(table_x, table_y, page_w, table_h)
        pdf.set_xy(table_x, table_y)
        pdf.set_font(doc.text_font_sb, "", 8)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(col_desc, header_h, "  DESCRI\u00c7\u00c3O")
        pdf.cell(col_type, header_h, "TIPO", align="C")
        pdf.cell(col_amount, header_h, "VALOR  ", align="R")

        row_y = table_y + header_h
        for item, description_lines, show_values in rows:
            row_h = self._table_row_height(description_lines)
            pdf.set_draw_color(*c["border_color"])
            pdf.set_line_width(0.25)
            pdf.line(table_x, row_y, table_x + page_w, row_y)

            text_h = len(description_lines) * 5
            pdf.set_xy(table_x + 5, row_y + (row_h - text_h) / 2)
            pdf.set_font(doc.text_font, "", 9.5)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(
                col_desc - 10,
                5,
                "\n".join(description_lines),
                align="L",
                max_line_height=5,
            )

            if show_values:
                pdf.set_xy(table_x + col_desc, row_y)
                pdf.set_font(doc.text_font, "", 8.5)
                pdf.cell(col_type, row_h, TYPE_LABELS.get(item.item_type, item.item_type), align="C")
                pdf.set_xy(table_x + col_desc + col_type, row_y)
                pdf.set_font(doc.text_font_sb, "", 9.5)
                pdf.cell(col_amount, row_h, f"{format_brl(item.amount)}  ", align="R")
            row_y += row_h

        pdf.set_y(table_y + table_h)

    def _summary_height(self, doc: PdfDocument, notes: str) -> float:
        height = 25.0
        if notes:
            # Reserve a useful first observations panel while allowing very
            # long notes to continue explicitly on branded pages.
            height += 22.0 + min(44.0, self._measure_notes_height(doc, notes))
        return height

    def _draw_total(self, doc: PdfDocument, total_amount: int) -> None:
        pdf = doc.pdf
        c = doc.colors
        total_w = doc.page_w
        total_h = 19.0
        x = pdf.l_margin
        y = pdf.get_y()

        pdf.set_fill_color(*c["primary"])
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.65)
        pdf.rect(x, y, total_w, total_h, style="DF")
        pdf.set_xy(x + 8, y + 4.5)
        pdf.set_font(doc.text_font_sb, "", 8)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(total_w * 0.45, 10, "TOTAL A PAGAR")
        pdf.set_font(doc.header_font, "B", 15.5)
        pdf.cell(total_w * 0.47, 10, format_brl(total_amount), align="R")
        pdf.set_y(y + total_h)

    def _draw_notes(self, doc: PdfDocument, notes: str, billing_name: str, reference_month: str) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        lines = self._measure_notes_lines(doc, notes)
        continuation = False

        while lines:
            pdf.ln(4 if continuation else 12)
            pdf.set_font(doc.header_font, "B", 11)
            pdf.set_text_color(*c["text_color"])
            heading = "OBSERVAÇÕES (CONTINUAÇÃO)" if continuation else "OBSERVAÇÕES"
            pdf.cell(0, 7, heading, new_x="LMARGIN", new_y="NEXT")
            pdf.ln(3)

            x = pdf.l_margin
            y = pdf.get_y()
            content_bottom = pdf.h + _FOOTER_OFFSET - 7
            available_h = content_bottom - y
            # _summary_height reserves at least one notes row on the invoice;
            # continuation pages start directly below the shared masthead.
            max_lines = max(1, int((available_h - 10) // 5.5))

            page_lines = lines[:max_lines]
            lines = lines[max_lines:]
            notes_h = max(20.0, len(page_lines) * 5.5 + 10)
            pdf.set_fill_color(*c["primary_light"])
            pdf.set_draw_color(*c["border_color"])
            pdf.set_line_width(0.65)
            pdf.rect(x, y, page_w, notes_h, style="DF")
            pdf.set_xy(x + 8, y + 5)
            pdf.set_text_color(*c["text_color"])
            pdf.set_font(doc.text_font, "", 9.5)
            pdf.multi_cell(page_w - 16, 5.5, "\n".join(page_lines), align="L")
            pdf.set_y(y + notes_h)

            if lines:
                self._draw_footer(doc)
                pdf.add_page()
                draw_document_header(
                    doc,
                    title="FATURA",
                    subtitle=f"{billing_name}  ·  {format_month(reference_month)}  ·  Observações - continuação",
                    show_wordmark=False,
                )
                continuation = True

    def _measure_notes_height(self, doc: PdfDocument, notes: str) -> float:
        return max(20.0, len(self._measure_notes_lines(doc, notes)) * 5.5 + 10)

    @staticmethod
    def _measure_notes_lines(doc: PdfDocument, notes: str) -> list[str]:
        pdf = doc.pdf
        pdf.set_font(doc.text_font, "", 9.5)
        return pdf.multi_cell(
            doc.page_w - 16,
            5.5,
            notes,
            align="L",
            dry_run=True,
            output="LINES",
        )

    def _draw_pix_page(
        self,
        doc: PdfDocument,
        qrcode_png: bytes,
        total_amount: int,
        pix_key: str,
        pix_payload: str,
        *,
        billing_name: str,
        reference_month: str,
    ) -> None:
        pdf = doc.pdf
        c = doc.colors
        page_w = doc.page_w
        x = pdf.l_margin
        reference = format_month(reference_month)
        draw_document_header(
            doc,
            title="FATURA",
            subtitle=f"{billing_name}  ·  {reference}",
            show_wordmark=False,
        )

        pdf.set_font(doc.header_font, "B", 16)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(page_w * 0.62, 8, "PAGUE COM PIX")
        pdf.set_font(doc.text_font, "", 8)
        pdf.set_text_color(*c["muted_text"])
        pdf.cell(page_w * 0.38, 8, "Pagamento seguro pelo seu banco", align="R", new_x="LMARGIN", new_y="NEXT")
        pdf.ln(4)

        panel_h = 76.0
        qr_col_w = 78.0
        qr_y = pdf.get_y()
        pdf.set_draw_color(*c["border_color"])
        pdf.set_line_width(0.65)
        pdf.rect(x, qr_y, page_w, panel_h)
        pdf.line(x + qr_col_w, qr_y, x + qr_col_w, qr_y + panel_h)
        qr_size = 56.0
        qr_x = x + (qr_col_w - qr_size) / 2
        buf = BytesIO(qrcode_png)
        pdf.image(buf, x=qr_x, y=qr_y + (panel_h - qr_size) / 2, w=qr_size, h=qr_size)

        aside_x = x + qr_col_w
        aside_w = page_w - qr_col_w
        aside_pad = 9.0
        content_x = aside_x + aside_pad
        content_w = aside_w - (aside_pad * 2)
        amount_h = 27.0
        pdf.set_fill_color(*c["primary"])
        pdf.rect(content_x, qr_y + aside_pad, content_w, amount_h, style="F")
        pdf.set_xy(content_x + 7, qr_y + aside_pad + 5)
        pdf.set_font(doc.text_font_sb, "", 7.5)
        pdf.set_text_color(*c["text_contrast"])
        pdf.cell(content_w - 14, 5, "VALOR A PAGAR")
        pdf.set_xy(content_x + 7, qr_y + aside_pad + 12)
        pdf.set_font(doc.header_font, "B", 17)
        pdf.cell(content_w - 14, 10, format_brl(total_amount))

        instructions_y = qr_y + aside_pad + amount_h + 8
        pdf.set_xy(content_x, instructions_y)
        pdf.set_font(doc.header_font, "B", 10.5)
        pdf.set_text_color(*c["text_color"])
        pdf.cell(content_w, 6, "COMO PAGAR")
        pdf.set_xy(content_x, instructions_y + 9)
        pdf.set_font(doc.text_font, "", 8.5)
        pdf.set_text_color(*c["muted_text"])
        pdf.multi_cell(
            content_w,
            5.5,
            "1. Abra o aplicativo do seu banco.\n2. Escolha pagar com PIX.\n3. Escaneie o QR Code ao lado.",
        )

        pdf.set_y(qr_y + panel_h + 15)

        # PIX key info card
        if pix_key:
            pdf.set_font(doc.header_font, "B", 10.5)
            pdf.set_text_color(*c["text_color"])
            pdf.cell(0, 6, "CHAVE PIX", new_x="LMARGIN", new_y="NEXT")
            pdf.ln(3)

            key_y = pdf.get_y()
            key_h = 16
            pdf.set_fill_color(*c["primary_light"])
            pdf.set_draw_color(*c["border_color"])
            pdf.set_line_width(0.65)
            pdf.rect(x, key_y, page_w, key_h, style="DF")
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
            pdf.set_fill_color(*c["primary_light"])
            pdf.set_draw_color(*c["border_color"])
            pdf.set_line_width(0.65)
            pdf.rect(x, payload_y, page_w, payload_h, style="DF")

            pdf.set_xy(x + 7, payload_y + 5)
            pdf.set_font(doc.text_font, "", 7)
            pdf.set_text_color(*c["text_color"])
            pdf.multi_cell(payload_cell_w, 4, pix_payload, align="L", wrapmode="CHAR")

            pdf.set_y(payload_y + payload_h + 4)

    def _draw_footer(self, doc: PdfDocument) -> None:
        draw_footer(doc, offset=_FOOTER_OFFSET, gap=_FOOTER_GAP)
