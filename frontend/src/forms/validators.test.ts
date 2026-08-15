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
  expect(validatePix({ city: "SALVADOR", key: "chave", name: "" })).toEqual({ errors: { name: "Informe o nome do recebedor." } });
  expect(validatePix({ city: "SALVADOR", key: "chave", name: "MARIA" })).toEqual({ value: { city: "SALVADOR", key: "chave", name: "MARIA" } });
  expect(validatePix({ city: "", key: "chave", name: "x".repeat(26) })).toEqual({
    errors: { city: "Informe a cidade do recebedor.", name: "Informe no máximo 25 caracteres." }
  });
  expect(validatePix({ city: "x".repeat(16), key: "chave", name: "MARIA" })).toEqual({ errors: { city: "Informe no máximo 15 caracteres." } });
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

