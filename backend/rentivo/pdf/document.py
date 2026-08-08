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
        "border_color": _shift(primary_light, -28),
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


def new_document(theme: Theme | None, *, semibold: bool = True) -> PdfDocument:
    """Open a single-page document themed by ``theme`` (the default when None).

    ``semibold`` registers the semibold variants; the recibo layout never uses
    them, and registering unused fonts would change the generated file.
    """
    from rentivo.models.theme import AVAILABLE_FONTS, DEFAULT_THEME

    theme = theme or DEFAULT_THEME

    # Resolve font families
    header_info = AVAILABLE_FONTS.get(theme.header_font, AVAILABLE_FONTS["Montserrat"])
    text_info = AVAILABLE_FONTS.get(theme.text_font, AVAILABLE_FONTS["Montserrat"])

    hf = theme.header_font.replace(" ", "")
    hf_sb = hf + "SB"
    tf = theme.text_font.replace(" ", "")
    tf_sb = tf + "SB"

    pdf = FPDF()
    pdf.add_page()
    pdf.set_auto_page_break(auto=True, margin=20)

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
    pdf.set_line_width(0.3)
    y = pdf.get_y()
    pdf.line(pdf.l_margin, y, pdf.l_margin + doc.page_w, y)
    pdf.ln(gap)
    pdf.set_font(doc.text_font, "", 7)
    pdf.set_text_color(*c["muted_text"])
    pdf.cell(0, 5, "Documento gerado automaticamente", align="C")
