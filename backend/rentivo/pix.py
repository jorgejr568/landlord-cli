"""PIX BR Code payload generator following BCB EMV QR Code specification.

Generates the payload string for a static PIX QR code and renders it as a PNG image.
"""

from __future__ import annotations

import re
import unicodedata
from io import BytesIO

import qrcode
from qrcode.image.pil import PilImage

from rentivo.pix_keys import PIX_KEY_PATTERNS


def validate_pix_key(key: str) -> str:
    """Validate a PIX key, returning its normalized form.

    - CPF/CNPJ/phone: strips common separators (., -, /, space, parentheses).
      10-digit numerics are treated as Brazilian landlines and prefixed with +55.
      **11-digit numerics are ambiguous**: they match CPF and are returned as CPF.
      Users registering a mobile phone must include the +55 country code.
    - email: lowercased.
    - evp: lowercased.

    Raises ValueError if the key is empty or does not match any recognized format.
    """
    if not key or not key.strip():
        raise ValueError("Chave PIX vazia")
    raw = key.strip()

    digits_only = re.sub(r"[.\-/\s()]", "", raw)
    if digits_only.isdigit():
        if len(digits_only) == 11:
            return digits_only  # CPF (11-digit mobiles are ambiguous; treated as CPF)
        if len(digits_only) == 14:
            return digits_only  # CNPJ
        if len(digits_only) == 10:
            return f"+55{digits_only}"  # assume Brazilian landline

    if raw.startswith("+") and re.sub(r"[\s()-]", "", raw).replace("+", "", 1).isdigit():
        normalized = "+" + re.sub(r"[\s()\-]", "", raw[1:])
        if PIX_KEY_PATTERNS["phone"].match(normalized):
            return normalized

    if "@" in raw:
        candidate = raw.lower()
        if PIX_KEY_PATTERNS["email"].match(candidate):
            return candidate

    if PIX_KEY_PATTERNS["evp"].match(raw):
        return raw.lower()

    raise ValueError("Chave PIX inválida. Use CPF, CNPJ, e-mail, telefone (+55...) ou chave aleatória (UUID).")


def normalize_pix_triple(
    pix_key: str | None, merchant_name: str | None, merchant_city: str | None
) -> tuple[str, str, str]:
    """Normalize a PIX override, requiring all of its recipient metadata together.

    An all-empty triple deliberately means that a billing inherits its owner's
    settings (or that a profile/organization clears them).  Any other partial
    value would produce a QR code that cannot be used, so reject it before a
    service could silently fall back to an owner's configuration.
    """
    key, name, city = (pix_key or "").strip(), (merchant_name or "").strip(), (merchant_city or "").strip()
    if not any((key, name, city)):
        return "", "", ""
    if not all((key, name, city)):
        raise ValueError("Informe chave PIX, nome e cidade do recebedor juntos.")
    return key, name, city


def _tlv(tag: str, value: str) -> str:
    """Build a TLV (Tag-Length-Value) field."""
    return f"{tag}{len(value):02d}{value}"


def _crc16_ccitt(data: str) -> str:
    """Compute CRC16-CCITT (0xFFFF) over the payload string."""
    crc = 0xFFFF
    for byte in data.encode("ascii"):
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ 0x1021
            else:
                crc <<= 1
            crc &= 0xFFFF
    return f"{crc:04X}"


def _format_amount_centavos(centavos: int) -> str:
    """Format integer centavos as a BRL decimal string without float rounding."""
    if centavos < 0:
        raise ValueError("amount_centavos must be non-negative")
    return f"{centavos // 100}.{centavos % 100:02d}"


def _strip_accents(text: str) -> str:
    """Remove accents for ASCII-safe PIX payload fields."""
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


def generate_pix_payload(
    *,
    pix_key: str,
    merchant_name: str,
    merchant_city: str,
    amount_centavos: int | None = None,
    txid: str = "***",
) -> str:
    """Generate a PIX BR Code payload string.

    Args:
        pix_key: The PIX key (CPF, CNPJ, phone, email, or random key).
        merchant_name: Recipient name, normalized for PIX and limited to 25 chars.
        merchant_city: Recipient city, normalized for PIX and limited to 15 chars.
        amount_centavos: Transaction amount in centavos (e.g. 15050 for R$ 150,50). None for open amount.
        txid: Transaction ID (default "***").

    Returns:
        The complete BR Code payload string with CRC16.
    """
    # PIX recipient fields are rendered in accent-free uppercase only at generation time.
    name = _strip_accents(merchant_name).upper()[:25]
    city = _strip_accents(merchant_city).upper()[:15]

    # Merchant Account Information (tag 26)
    mai = _tlv("00", "br.gov.bcb.pix") + _tlv("01", pix_key)
    # Additional Data Field Template (tag 62)
    adft = _tlv("05", txid)

    payload = (
        _tlv("00", "01")  # Payload Format Indicator
        + _tlv("26", mai)  # Merchant Account Information
        + _tlv("52", "0000")  # Merchant Category Code
        + _tlv("53", "986")  # Transaction Currency (BRL)
    )

    if amount_centavos is not None and amount_centavos > 0:
        payload += _tlv("54", _format_amount_centavos(amount_centavos))

    payload += (
        _tlv("58", "BR")  # Country Code
        + _tlv("59", name)  # Merchant Name
        + _tlv("60", city)  # Merchant City
        + _tlv("62", adft)  # Additional Data
    )

    # CRC16 placeholder: tag "63" + length "04" + actual CRC
    payload += "6304"
    crc = _crc16_ccitt(payload)
    payload += crc

    return payload


def generate_pix_qrcode_png(
    *,
    pix_key: str,
    merchant_name: str,
    merchant_city: str,
    amount_centavos: int | None = None,
    txid: str = "***",
    box_size: int = 10,
    border: int = 2,
    payload: str = "",
) -> bytes:
    """Generate a PIX QR code as PNG bytes.

    Args:
        payload: Pre-computed payload string. If empty, generates one from the other args.

    Returns:
        PNG image bytes ready to be saved or embedded in a PDF.
    """
    if not payload:
        payload = generate_pix_payload(
            pix_key=pix_key,
            merchant_name=merchant_name,
            merchant_city=merchant_city,
            amount_centavos=amount_centavos,
            txid=txid,
        )

    qr = qrcode.QRCode(
        version=None,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=box_size,
        border=border,
    )
    qr.add_data(payload)
    qr.make(fit=True)

    img: PilImage = qr.make_image(fill_color="black", back_color="white")

    buf = BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()
