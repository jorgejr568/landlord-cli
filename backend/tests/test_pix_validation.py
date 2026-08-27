"""Tests for PIX key validation/normalization."""

from __future__ import annotations

import pytest

from rentivo.pix import validate_pix_key
from rentivo.pix_keys import classify_pix_key


class TestClassifyPixKey:
    @pytest.mark.parametrize(
        "key,kind",
        [
            ("12345678901", "cpf"),
            ("12345678000190", "cnpj"),
            ("user@example.com", "email"),
            ("+5511987654321", "phone"),
            ("+551198765432", "phone"),
            ("123e4567-e89b-12d3-a456-426614174000", "evp"),
        ],
    )
    def test_recognized(self, key, kind):
        assert classify_pix_key(key) == kind

    @pytest.mark.parametrize(
        "key",
        [
            "",
            "not-a-key",
            "1234",
            "user@",
            "@example.com",
            "+1 555 1234567",  # non-BR country code
            "abcd-1234",
        ],
    )
    def test_rejected(self, key):
        assert classify_pix_key(key) is None


class TestValidatePixKey:
    def test_cpf_strips_punctuation(self):
        assert validate_pix_key("529.982.247-25") == "52998224725"

    def test_cnpj_strips_punctuation(self):
        assert validate_pix_key("12.345.678/0001-90") == "12345678000190"

    def test_phone_landline_prefixes_br_country_code(self):
        # 10 digits with DDD → Brazilian landline, not a CPF
        assert validate_pix_key("1133334444") == "+551133334444"

    def test_phone_with_country_code(self):
        assert validate_pix_key("+5511987654321") == "+5511987654321"

    def test_valid_cpf_wins_over_phone_inference(self):
        assert validate_pix_key("111.444.777-35") == "11144477735"

    def test_invalid_cpf_with_valid_area_code_becomes_phone(self):
        assert validate_pix_key("11987654321") == "+5511987654321"

    @pytest.mark.parametrize(
        "area_code",
        [
            "11",
            "12",
            "13",
            "14",
            "15",
            "16",
            "17",
            "18",
            "19",
            "21",
            "22",
            "24",
            "27",
            "28",
            "31",
            "32",
            "33",
            "34",
            "35",
            "37",
            "38",
            "41",
            "42",
            "43",
            "44",
            "45",
            "46",
            "47",
            "48",
            "49",
            "51",
            "53",
            "54",
            "55",
            "61",
            "62",
            "63",
            "64",
            "65",
            "66",
            "67",
            "68",
            "69",
            "71",
            "73",
            "74",
            "75",
            "77",
            "79",
            "81",
            "82",
            "83",
            "84",
            "85",
            "86",
            "87",
            "88",
            "89",
            "91",
            "92",
            "93",
            "94",
            "95",
            "96",
            "97",
            "98",
            "99",
        ],
    )
    def test_phone_accepts_every_brazilian_area_code(self, area_code):
        key = f"+55{area_code}912345678"
        assert validate_pix_key(key) == key

    @pytest.mark.parametrize("key", ["20987654321", "+5520912345678", "2033334444"])
    def test_phone_rejects_unknown_area_code(self, key):
        with pytest.raises(ValueError, match="Chave PIX inválida"):
            validate_pix_key(key)

    def test_email_lowercased(self):
        assert validate_pix_key("User@Example.com") == "user@example.com"

    def test_evp_lowercased(self):
        raw = "123E4567-E89B-12D3-A456-426614174000"
        assert validate_pix_key(raw) == raw.lower()

    def test_empty_raises(self):
        with pytest.raises(ValueError):
            validate_pix_key("")

    def test_whitespace_raises(self):
        with pytest.raises(ValueError):
            validate_pix_key("   ")

    def test_invalid_raises(self):
        with pytest.raises(ValueError):
            validate_pix_key("not-a-pix-key")

    @pytest.mark.parametrize(
        "key",
        [
            "joão@exemplo.com",  # the email pattern accepts any non-space character
            "٠١٢٣٤٥٦٧٨٩٠",  # str.isdigit() accepts non-ASCII digits
            "+55٠١٢٣٤٥٦٧٨٩",  # so does the \\d in the phone pattern
        ],
    )
    def test_non_ascii_raises(self, key):
        # The BR Code payload is ASCII-encoded when its CRC is computed, so a
        # non-ASCII key must never reach storage.
        with pytest.raises(ValueError, match="ASCII"):
            validate_pix_key(key)
