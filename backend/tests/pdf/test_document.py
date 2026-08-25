from dataclasses import FrozenInstanceError

import pytest

from rentivo.models.theme import DEFAULT_THEME, Theme
from rentivo.pdf.document import derive_colors, new_document


class TestDeriveColors:
    def test_maps_theme_hex_to_rgb(self):
        colors = derive_colors(Theme(primary="#FF5733", text_contrast="#FEFEFE"))
        assert colors["primary"] == (255, 87, 51)
        assert colors["text_contrast"] == (254, 254, 254)

    def test_derived_shades_are_offsets_of_their_source(self):
        colors = derive_colors(Theme(primary_light="#EEE4F1", text_color="#282830"))
        assert colors["primary_light"] == (238, 228, 241)
        assert colors["row_alt"] == (244, 234, 247)
        assert colors["border_color"] == (40, 40, 48)
        assert colors["muted_text"] == (108, 108, 116)

    def test_shift_clamps_at_the_upper_end(self):
        colors = derive_colors(Theme(text_color="#FFFFFF", primary_light="#FFFFFF"))
        assert colors["muted_text"] == (255, 255, 255)
        assert colors["row_alt"] == (255, 255, 255)


class TestNewDocument:
    def test_default_document_uses_rentivo_brand_tokens(self):
        doc = new_document(None)

        assert (doc.header_font, doc.text_font) == ("SpaceGrotesk", "HankenGrotesk")
        assert doc.colors == {
            "border_color": (27, 29, 41),
            "muted_text": (95, 97, 109),
            "primary": (0, 125, 83),
            "primary_light": (219, 246, 231),
            "row_alt": (225, 252, 237),
            "secondary": (245, 242, 235),
            "secondary_dark": (27, 29, 41),
            "text_color": (27, 29, 41),
            "text_contrast": (255, 255, 255),
        }

    def test_defaults_to_the_default_theme(self):
        assert new_document(None).colors == derive_colors(DEFAULT_THEME)

    def test_unknown_font_falls_back_to_the_default_font_files(self):
        doc = new_document(Theme(header_font="Nonexistent Face", text_font="Nonexistent Face"))
        # The family name still comes from the theme; only the files fall back.
        assert doc.header_font == "NonexistentFace"
        assert set(doc.pdf.fonts) == {"nonexistentface", "nonexistentfaceB", "nonexistentfacesb"}

    def test_single_family_reuses_the_header_semibold_alias(self):
        doc = new_document(Theme(header_font="Roboto", text_font="Roboto"))
        assert doc.text_font == doc.header_font == "Roboto"
        assert doc.text_font_sb == doc.header_font_sb == "RobotoSB"

    def test_distinct_families_register_both(self):
        doc = new_document(Theme(header_font="Roboto", text_font="Open Sans"))
        assert (doc.header_font, doc.text_font) == ("Roboto", "OpenSans")
        assert doc.text_font_sb == "OpenSansSB"
        assert set(doc.pdf.fonts) == {
            "roboto",
            "robotoB",
            "robotosb",
            "opensans",
            "opensansB",
            "opensanssb",
        }

    def test_semibold_off_skips_the_semibold_faces(self):
        doc = new_document(Theme(header_font="Roboto", text_font="Open Sans"), semibold=False)
        assert set(doc.pdf.fonts) == {"roboto", "robotoB", "opensans", "opensansB"}

    def test_page_width_excludes_the_margins(self):
        doc = new_document(None)
        pdf = doc.pdf
        assert doc.page_w == pytest.approx(pdf.w - pdf.l_margin - pdf.r_margin)

    def test_is_frozen(self):
        """Drawing helpers receive the document; they must not rebind its state."""
        doc = new_document(None)
        with pytest.raises(FrozenInstanceError):
            doc.page_w = 1.0
