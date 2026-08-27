import { expect, it } from "vitest";

import {
  communicationBodyBytes,
  normalizeEmail,
  validateContacts,
  validateMoney,
  validatePassword,
  validatePix,
  validateText,
  validateUpload
} from "./validators";

it("rejects blank, malformed, and overflowing BRL input instead of coercing it to zero", () => {
  expect(validateMoney("", { minimum: 0 })).toEqual({ error: "Informe um valor válido." });
  expect(validateMoney("R$ 12", { minimum: 0 })).toEqual({ error: "Informe um valor válido." });
  expect(validateMoney("9007199254740992,00", { minimum: 0 })).toEqual({ error: "Informe um valor válido." });
  expect(validateMoney("0,00", { minimum: 1 })).toEqual({ error: "Informe um valor maior que zero." });
  expect(validateMoney("1.234,56", { minimum: 1 })).toEqual({ value: 123456 });
});

it("trims bounded required text and normalized emails", () => {
  expect(validateText("  Casa  ", { maxLength: 255, required: true })).toEqual({ value: "Casa" });
  expect(validateText("   ", { maxLength: 255, required: true })).toEqual({ error: "Este campo é obrigatório." });
  expect(validateText("x".repeat(256), { maxLength: 255 })).toEqual({ error: "Informe no máximo 255 caracteres." });
  expect(normalizeEmail("  ANA@EXAMPLE.COM ")).toEqual({ value: "ana@example.com" });
  expect(normalizeEmail("ana@localhost")).toEqual({ error: "Informe um e-mail válido." });
  expect(normalizeEmail(`${"a".repeat(310)}@example.com`)).toEqual({ error: "Informe no máximo 320 caracteres." });
});

it("omits blank contacts and rejects partial contacts without fabricating values", () => {
  expect(validateContacts([{ email: "", name: "" }, { email: " ANA@EXAMPLE.COM ", name: " Ana " }])).toEqual({
    value: [{ email: "ana@example.com", name: "Ana" }]
  });
  expect(validateContacts([{ email: "ana@example.com", name: "" }])).toEqual({
    errors: { "0.name": "Este campo é obrigatório." }
  });
  expect(validateContacts([{ email: "", name: "Ana" }, { email: "ana@localhost", name: "Ana" }, { email: "ana@example.com", name: "x".repeat(256) }])).toEqual({
    errors: {
      "0.email": "Este campo é obrigatório.",
      "1.email": "Informe um e-mail válido.",
      "2.name": "Informe no máximo 255 caracteres."
    }
  });
});

it("requires all custom PIX values or no custom PIX values", () => {
  expect(validatePix({ city: "", key: "", name: "" })).toEqual({ value: { city: "", key: "", name: "" } });
  expect(validatePix({ city: "SALVADOR", key: "", name: "MARIA" })).toEqual({ errors: { key: "Informe a chave PIX." } });
  expect(validatePix({ city: "SALVADOR", key: "pix@example.com", name: "" })).toEqual({ errors: { name: "Informe o nome do recebedor." } });
  expect(validatePix({ city: "SALVADOR", key: "pix@example.com", name: "MARIA" })).toEqual({ value: { city: "SALVADOR", key: "pix@example.com", name: "MARIA" } });
  expect(validatePix({ city: "", key: "pix@example.com", name: "x".repeat(256) })).toEqual({
    errors: { city: "Informe a cidade do recebedor.", name: "Informe no máximo 255 caracteres." }
  });
  expect(validatePix({ city: "x".repeat(256), key: "pix@example.com", name: "MARIA" })).toEqual({ errors: { city: "Informe no máximo 255 caracteres." } });
});

it("resolves an ambiguous 11-digit PIX key as CPF or Brazilian phone", () => {
  expect(validatePix({ city: "SALVADOR", key: "111.444.777-35", name: "MARIA" })).toEqual({
    value: { city: "SALVADOR", key: "11144477735", name: "MARIA" }
  });
  expect(validatePix({ city: "SALVADOR", key: "11987654321", name: "MARIA" })).toEqual({
    value: { city: "SALVADOR", key: "+5511987654321", name: "MARIA" }
  });
  expect(validatePix({ city: "SALVADOR", key: "11111111111", name: "MARIA" })).toEqual({
    value: { city: "SALVADOR", key: "+5511111111111", name: "MARIA" }
  });
  expect(validatePix({ city: "SALVADOR", key: "110.000.055-00", name: "MARIA" })).toEqual({
    value: { city: "SALVADOR", key: "11000005500", name: "MARIA" }
  });
  expect(validatePix({ city: "SALVADOR", key: "20987654321", name: "MARIA" })).toEqual({
    errors: { key: "Informe uma chave PIX válida." }
  });
});

it("rejects a phone PIX key when its Brazilian area code does not exist", () => {
  expect(validatePix({ city: "SALVADOR", key: "+5520912345678", name: "MARIA" })).toEqual({
    errors: { key: "Informe uma chave PIX válida." }
  });
});

it.each([
  "11", "12", "13", "14", "15", "16", "17", "18", "19",
  "21", "22", "24", "27", "28",
  "31", "32", "33", "34", "35", "37", "38",
  "41", "42", "43", "44", "45", "46", "47", "48", "49",
  "51", "53", "54", "55",
  "61", "62", "63", "64", "65", "66", "67", "68", "69",
  "71", "73", "74", "75", "77", "79",
  "81", "82", "83", "84", "85", "86", "87", "88", "89",
  "91", "92", "93", "94", "95", "96", "97", "98", "99"
])("accepts Brazilian phone area code %s", (areaCode) => {
  const key = `+55${areaCode}912345678`;
  expect(validatePix({ city: "SALVADOR", key, name: "MARIA" })).toEqual({
    value: { city: "SALVADOR", key, name: "MARIA" }
  });
});

it.each([
  ["12.345.678/0001-90", "12345678000190"],
  ["11 3333-4444", "+551133334444"],
  ["+55 (11) 98765-4321", "+5511987654321"],
  ["User@Example.com", "user@example.com"],
  ["123E4567-E89B-12D3-A456-426614174000", "123e4567-e89b-12d3-a456-426614174000"]
])("normalizes supported PIX key %s", (key, normalized) => {
  expect(validatePix({ city: "SALVADOR", key, name: "MARIA" })).toEqual({
    value: { city: "SALVADOR", key: normalized, name: "MARIA" }
  });
});

it.each(["pix", "1234", "joão@example.com", "+5511", "2033334444"])("rejects malformed PIX key %s", (key) => {
  expect(validatePix({ city: "SALVADOR", key, name: "MARIA" })).toEqual({
    errors: { key: "Informe uma chave PIX válida." }
  });
});

it("counts communication bytes as UTF-8 and preflights file type and size", () => {
  expect(communicationBodyBytes("á")).toBe(2);
  expect(communicationBodyBytes("x".repeat(4096))).toBe(4096);
  expect(communicationBodyBytes("á".repeat(2049))).toBe(4098);
  expect(validateUpload(new File(["x"], "nota.txt", { type: "text/plain" }))).toEqual({ error: "Envie um arquivo PDF, JPG ou PNG." });
  expect(validateUpload(new File([], "vazio.pdf", { type: "application/pdf" }))).toEqual({ error: "O arquivo está vazio." });
  expect(validateUpload(new File([new Uint8Array(10 * 1024 * 1024 + 1)], "nota.pdf", { type: "application/pdf" }))).toEqual({ error: "O arquivo deve ter no máximo 10 MB." });
  expect(validateUpload(new File(["x"], "nota.pdf", { type: "application/pdf" }))).toEqual({ value: expect.any(File) });
});

it("enforces bcrypt's 72-byte password limit instead of counting characters", () => {
  expect(validatePassword("á".repeat(36))).toEqual({ value: "á".repeat(36) });
  expect(validatePassword("á".repeat(37))).toEqual({ error: "Senha muito longa." });
});
