"""Tests for rentivo.pdf.merger — PDF/image receipt merging."""

from __future__ import annotations

from io import BytesIO

from fpdf import FPDF
from PIL import Image
from pypdf import PdfReader

from rentivo.pdf.merger import _image_to_pdf, merge_receipts


def _make_pdf(num_pages: int = 1) -> bytes:
    """Create a simple test PDF with the given number of pages."""
    pdf = FPDF()
    for i in range(num_pages):
        pdf.add_page()
        pdf.set_font("Helvetica", size=12)
        pdf.cell(0, 10, f"Page {i + 1}")
    return bytes(pdf.output())


def _make_jpeg() -> bytes:
    """Create a small JPEG test image."""
    img = Image.new("RGB", (200, 300), color="red")
    buf = BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def _make_png() -> bytes:
    """Create a small PNG test image."""
    img = Image.new("RGB", (300, 200), color="blue")
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_png_rgba() -> bytes:
    """Create a PNG with alpha channel."""
    img = Image.new("RGBA", (100, 100), color=(0, 255, 0, 128))
    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _make_landscape_image() -> bytes:
    """Create a landscape-oriented image (wider than tall)."""
    img = Image.new("RGB", (800, 400), color="green")
    buf = BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


def _make_camera_resolution_photo() -> bytes:
    """A 4032x3024 (12MP) portrait JPEG — a typical modern phone-camera photo."""
    img = Image.new("RGB", (3024, 4032), color="gray")
    buf = BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def _make_exif_rotated_jpeg() -> bytes:
    """Create a JPEG stored landscape but tagged EXIF orientation 6 (upright).

    Phone cameras write the sensor buffer as-is and record the rotation in EXIF.
    Honoring the tag turns this 800x400 buffer into a 400x800 portrait image.
    """
    img = Image.new("RGB", (800, 400), color="orange")
    exif = img.getexif()
    exif[274] = 6  # ExifTags.Base.Orientation — rotate 270 degrees on display
    buf = BytesIO()
    img.save(buf, format="JPEG", exif=exif)
    return buf.getvalue()


class TestMergeReceipts:
    def test_no_receipts_returns_original(self):
        invoice = _make_pdf(2)
        result, failed = merge_receipts(invoice, [])
        assert result == invoice
        assert failed == []

    def test_merge_pdf_receipt(self):
        invoice = _make_pdf(1)
        receipt_pdf = _make_pdf(2)
        result, failed = merge_receipts(invoice, [(receipt_pdf, "application/pdf")])
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 3  # 1 invoice + 2 receipt pages
        assert failed == []

    def test_merge_jpeg_receipt(self):
        invoice = _make_pdf(1)
        jpeg = _make_jpeg()
        result, failed = merge_receipts(invoice, [(jpeg, "image/jpeg")])
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 2  # 1 invoice + 1 image page
        assert failed == []

    def test_merge_png_receipt(self):
        invoice = _make_pdf(1)
        png = _make_png()
        result, failed = merge_receipts(invoice, [(png, "image/png")])
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 2
        assert failed == []

    def test_merge_multiple_receipts(self):
        invoice = _make_pdf(1)
        receipts = [
            (_make_pdf(1), "application/pdf"),
            (_make_jpeg(), "image/jpeg"),
            (_make_png(), "image/png"),
        ]
        result, failed = merge_receipts(invoice, receipts)
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 4  # 1 + 1 + 1 + 1
        assert failed == []

    def test_merge_mixed_types(self):
        invoice = _make_pdf(2)
        receipt_pdf = _make_pdf(3)
        jpeg = _make_jpeg()
        result, failed = merge_receipts(invoice, [(receipt_pdf, "application/pdf"), (jpeg, "image/jpeg")])
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 6  # 2 + 3 + 1
        assert failed == []

    def test_unsupported_type_skipped(self):
        invoice = _make_pdf(1)
        result, failed = merge_receipts(invoice, [(b"data", "text/plain")])
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1  # Only invoice
        assert failed == [0]

    def test_corrupt_receipt_skipped(self):
        invoice = _make_pdf(1)
        result, failed = merge_receipts(invoice, [(b"not-a-pdf", "application/pdf")])
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1  # Only invoice, corrupt one skipped
        assert failed == [0]

    def test_corrupt_invoice_returns_original(self):
        bad_invoice = b"not-a-pdf"
        receipts = [(_make_pdf(1), "application/pdf")]
        result, failed = merge_receipts(bad_invoice, receipts)
        assert result == bad_invoice
        assert failed == [0]


class TestImageToPdf:
    def test_portrait_image(self):
        # 200x300 = portrait
        jpeg = _make_jpeg()
        result = _image_to_pdf(jpeg)
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1
        page = reader.pages[0]
        # Portrait A4: width < height
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        assert height > width

    def test_landscape_image(self):
        jpeg = _make_landscape_image()
        result = _image_to_pdf(jpeg)
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1
        page = reader.pages[0]
        # Landscape A4: width > height
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        assert width > height

    def test_rgba_image_converted(self):
        png = _make_png_rgba()
        result = _image_to_pdf(png)
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1

    def test_exif_orientation_is_honored(self):
        # Stored 800x400 but tagged orientation 6, so it displays as 400x800.
        jpeg = _make_exif_rotated_jpeg()
        result = _image_to_pdf(jpeg)
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1
        page = reader.pages[0]
        width = float(page.mediabox.width)
        height = float(page.mediabox.height)
        # Ignoring the EXIF tag would pick landscape A4 for the raw 800x400 size.
        assert height > width

    def test_square_image(self):
        img = Image.new("RGB", (500, 500), color="white")
        buf = BytesIO()
        img.save(buf, format="PNG")
        result = _image_to_pdf(buf.getvalue())
        reader = PdfReader(BytesIO(result))
        assert len(reader.pages) == 1

    def test_camera_resolution_photo_is_downscaled_to_print_size(self):
        # A 4032x3024 source embedded 1:1 previously produced a PDF tens of MB in size
        # for a single receipt — over common email attachment limits — even though every
        # viewer displays it no larger than an A4 page. The embedded image must shrink to
        # roughly what the print DPI needs, not carry the source resolution through.
        photo = _make_camera_resolution_photo()
        result = _image_to_pdf(photo)
        reader = PdfReader(BytesIO(result))
        embedded = next(iter(reader.pages[0].images))
        embedded_image = Image.open(BytesIO(embedded.data))
        assert max(embedded_image.size) < 2000

    def test_camera_resolution_photo_produces_a_small_pdf(self):
        photo = _make_camera_resolution_photo()
        result = _image_to_pdf(photo)
        # Well under the multi-megabyte size the unscaled/lossless embedding produced;
        # generous enough to not be flaky across encoder versions.
        assert len(result) < 500_000

    def test_small_image_is_not_upscaled(self):
        # An image already smaller than the print target must come through unchanged in
        # size — the fix downscales oversized images, it must never enlarge small ones.
        jpeg = _make_jpeg()  # 200x300
        source = Image.open(BytesIO(jpeg))
        result = _image_to_pdf(jpeg)
        reader = PdfReader(BytesIO(result))
        embedded = next(iter(reader.pages[0].images))
        embedded_image = Image.open(BytesIO(embedded.data))
        assert embedded_image.size == source.size
