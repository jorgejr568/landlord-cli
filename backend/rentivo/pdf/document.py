"""Shared setup for the generated PDF documents.

Invoice and recibo share the same page geometry, theme-derived palette, font
registration, and footer. They differ only in whether the semibold font
variants are needed and in where the footer sits on the page.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from fpdf import FPDF

if TYPE_CHECKING:
    from rentivo.models.theme import Theme

FONTS_DIR = Path(__file__).parent / "fonts"


def _hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def _shift(rgb: tuple[int, int, int], delta: int) -> tuple[int, int, int]:
    """Brighten (delta > 0) or darken (delta < 0) an RGB tuple, clamped to 0-255."""
    r, g, b = (max(0, min(255, c + delta)) for c in rgb)
    return (r, g, b)


def _fit_single_line(pdf: FPDF, text: str, max_width: float) -> str:
    """Shorten one line with an ASCII ellipsis before it leaves its column."""
    if pdf.get_string_width(text) <= max_width:
        return text
    suffix = "..."
    low = 0
    high = len(text)
    while low < high:
        midpoint = (low + high + 1) // 2
        candidate = text[:midpoint].rstrip() + suffix
        if pdf.get_string_width(candidate) <= max_width:
            low = midpoint
        else:
            high = midpoint - 1
    return text[:low].rstrip() + suffix


def derive_colors(theme: Theme) -> dict[str, tuple[int, int, int]]:
    primary_light = _hex_to_rgb(theme.primary_light)
    text_color = _hex_to_rgb(theme.text_color)

    return {
        "primary": _hex_to_rgb(theme.primary),
        "primary_light": primary_light,
        "secondary": _hex_to_rgb(theme.secondary),
        "secondary_dark": _hex_to_rgb(theme.secondary_dark),
        "text_color": text_color,
        "text_contrast": _hex_to_rgb(theme.text_contrast),
        "muted_text": _shift(text_color, 68),
        "row_alt": _shift(primary_light, 6),
        "border_color": text_color,
    }


@dataclass(frozen=True)
class PdfDocument:
    """A prepared FPDF page plus everything the drawing helpers need.

    Passed explicitly through the ``_draw_*`` helpers so no generator has to
    stash late-bound state on ``self``.
    """

    pdf: FPDF
    colors: dict[str, tuple[int, int, int]]
    header_font: str
    header_font_sb: str
    text_font: str
    text_font_sb: str
    page_w: float


def draw_wordmark(doc: PdfDocument, x: float, y: float, *, inverted: bool = False) -> None:
    """Draw the compact Rentivo mark used by every generated document."""
    pdf = doc.pdf
    c = doc.colors
    mark_size = 7.5
    ink = c["text_contrast"] if inverted else c["text_color"]

    pdf.set_fill_color(*c["primary"])
    pdf.set_draw_color(*ink)
    pdf.set_line_width(0.45)
    pdf.rect(x, y, mark_size, mark_size, style="DF", round_corners=True, corner_radius=1.4)
    pdf.set_xy(x, y + 0.5)
    pdf.set_font(doc.header_font, "B", 6.5)
    pdf.set_text_color(*c["text_contrast"])
    pdf.cell(mark_size, mark_size - 0.5, "R", align="C")

    pdf.set_xy(x + mark_size + 2.2, y - 0.1)
    pdf.set_font(doc.header_font, "B", 9.5)
    pdf.set_text_color(*ink)
    pdf.cell(28, mark_size, "rentivo")
    pdf.set_line_width(0.2)


def draw_document_header(
    doc: PdfDocument,
    *,
    title: str,
    subtitle: str,
    show_wordmark: bool = True,
) -> None:
    """Draw the shared document rail and advance below it.

    The document identity leads; product branding is deliberately secondary.
    This keeps invoices and receipts recognizable as one family without
    turning their masthead into an application banner.
    """
    pdf = doc.pdf
    c = doc.colors
    x = pdf.l_margin
    y = pdf.get_y()
    header_h = 28.0

    pdf.set_fill_color(*c["primary"])
    pdf.rect(x, y + 1, 3.0, 19.0, style="F", round_corners=True, corner_radius=1.4)

    pdf.set_xy(x + 8, y)
    pdf.set_font(doc.header_font, "B", 21)
    pdf.set_text_color(*c["text_color"])
    pdf.cell(doc.page_w * 0.60, 10, title)

    subtitle_w = doc.page_w * (0.26 if show_wordmark else 0.42)
    subtitle_x = x + doc.page_w - subtitle_w
    pdf.set_xy(subtitle_x, y + 2.2)
    pdf.set_font(doc.text_font, "", 8.2)
    pdf.set_text_color(*c["muted_text"])
    pdf.cell(subtitle_w, 5, _fit_single_line(pdf, subtitle, subtitle_w), align="R")

    if show_wordmark:
        draw_wordmark(doc, x + doc.page_w - 36, y + 11.5)

    rule_y = y + header_h - 2
    pdf.set_draw_color(*c["border_color"])
    pdf.set_line_width(0.55)
    pdf.line(x, rule_y, x + doc.page_w, rule_y)
    pdf.set_draw_color(*c["primary"])
    pdf.set_line_width(1.8)
    pdf.line(x, rule_y, x + 31, rule_y)
    pdf.set_line_width(0.2)

    pdf.set_y(y + header_h + 7)


def new_document(theme: Theme | None, *, semibold: bool = True) -> PdfDocument:
    """Open a single-page document themed by ``theme`` (the default when None).

    ``semibold`` registers the semibold variants; the recibo layout never uses
    them, and registering unused fonts would change the generated file.
    """
    from rentivo.models.theme import AVAILABLE_FONTS, DEFAULT_THEME

    theme = theme or DEFAULT_THEME

    # Resolve font families
    header_info = AVAILABLE_FONTS.get(theme.header_font, AVAILABLE_FONTS[DEFAULT_THEME.header_font])
    text_info = AVAILABLE_FONTS.get(theme.text_font, AVAILABLE_FONTS[DEFAULT_THEME.text_font])

    hf = theme.header_font.replace(" ", "")
    hf_sb = hf + "SB"
    tf = theme.text_font.replace(" ", "")
    tf_sb = tf + "SB"

    pdf = FPDF()
    pdf.set_margins(14, 14, 14)
    pdf.set_auto_page_break(auto=True, margin=20)
    pdf.add_page()

    # Register header font
    pdf.add_font(hf, "", str(FONTS_DIR / header_info["regular"]))
    pdf.add_font(hf, "B", str(FONTS_DIR / header_info["bold"]))
    if semibold:
        pdf.add_font(hf_sb, "", str(FONTS_DIR / header_info["semibold"]))

    # Register text font if different
    if tf != hf:
        pdf.add_font(tf, "", str(FONTS_DIR / text_info["regular"]))
        pdf.add_font(tf, "B", str(FONTS_DIR / text_info["bold"]))
        if semibold:
            pdf.add_font(tf_sb, "", str(FONTS_DIR / text_info["semibold"]))
    else:
        tf_sb = hf_sb

    return PdfDocument(
        pdf=pdf,
        colors=derive_colors(theme),
        header_font=hf,
        header_font_sb=hf_sb,
        text_font=tf,
        text_font_sb=tf_sb,
        page_w=pdf.w - pdf.l_margin - pdf.r_margin,
    )


def draw_footer(
    doc: PdfDocument,
    *,
    offset: float,
    gap: float,
    disable_page_break: bool = False,
) -> None:
    """Draw the bottom rule and the generated-document note.

    ``offset`` is the negative ``set_y`` position of the rule and ``gap`` the
    space between rule and text; both differ between invoice and recibo.
    """
    pdf = doc.pdf
    c = doc.colors
    if disable_page_break:
        pdf.set_auto_page_break(False)
    pdf.set_y(offset)
    pdf.set_draw_color(*c["border_color"])
    pdf.set_line_width(0.45)
    y = pdf.get_y()
    pdf.line(pdf.l_margin, y, pdf.l_margin + doc.page_w, y)
    pdf.set_draw_color(*c["primary"])
    pdf.set_line_width(1.5)
    pdf.line(pdf.l_margin, y, pdf.l_margin + 24, y)
    pdf.ln(gap)
    pdf.set_font(doc.text_font, "", 7)
    pdf.set_text_color(*c["muted_text"])
    pdf.cell(doc.page_w * 0.5, 5, "rentivo  ·  Documento gerado automaticamente")
    pdf.cell(doc.page_w * 0.5, 5, f"Página {pdf.page_no()}", align="R")
