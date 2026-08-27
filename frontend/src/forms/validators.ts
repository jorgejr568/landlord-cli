import { parseBrl } from "../lib/format";

export type ValidationResult<T> = { value: T } | { error: string };

export function validateMoney(value: string, { minimum = 0 }: { minimum?: number } = {}): ValidationResult<number> {
  const parsed = parseBrl(value);
  if (parsed === null) return { error: "Informe um valor válido." };
  if (parsed < minimum) return { error: "Informe um valor maior que zero." };
  return { value: parsed };
}

/** bcrypt accepts at most 72 UTF-8 bytes, independently of character count. */
export function validatePassword(value: string): ValidationResult<string> {
  if (new TextEncoder().encode(value).length > 72) return { error: "Senha muito longa." };
  return { value };
}

export function passwordValidationError(...values: string[]): string | null {
  for (const value of values) {
    const result = validatePassword(value);
    if ("error" in result) return result.error;
  }
  return null;
}

export function validateText(value: string, { maxLength, required = false }: { maxLength: number; required?: boolean }): ValidationResult<string> {
  const normalized = value.trim();
  if (required && !normalized) return { error: "Este campo é obrigatório." };
  if (Array.from(normalized).length > maxLength) return { error: `Informe no máximo ${maxLength} caracteres.` };
  return { value: normalized };
}

export function normalizeEmail(value: string): ValidationResult<string> {
  const normalized = value.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) return { error: "Informe um e-mail válido." };
  if (Array.from(normalized).length > 320) return { error: "Informe no máximo 320 caracteres." };
  return { value: normalized };
}

export interface ContactDraft { email: string; name: string; }

export function validateContacts(contacts: ContactDraft[]): { value: Array<{ email: string; name: string }> } | { errors: Record<string, string> } {
  const errors: Record<string, string> = {};
  const value: Array<{ email: string; name: string }> = [];
  contacts.forEach((contact, index) => {
    const name = contact.name.trim();
    const email = contact.email.trim();
    if (!name && !email) return;
    if (!name) errors[`${index}.name`] = "Este campo é obrigatório.";
    else if (Array.from(name).length > 255) errors[`${index}.name`] = "Informe no máximo 255 caracteres.";
    const normalizedEmail = normalizeEmail(email);
    if (!email) errors[`${index}.email`] = "Este campo é obrigatório.";
    else if ("error" in normalizedEmail) errors[`${index}.email`] = normalizedEmail.error;
    if (name && "value" in normalizedEmail) value.push({ email: normalizedEmail.value, name });
  });
  return Object.keys(errors).length ? { errors } : { value };
}

export interface PixDraft { city: string; key: string; name: string; }

const BRAZIL_AREA_CODES = new Set([
  "11", "12", "13", "14", "15", "16", "17", "18", "19",
  "21", "22", "24", "27", "28",
  "31", "32", "33", "34", "35", "37", "38",
  "41", "42", "43", "44", "45", "46", "47", "48", "49",
  "51", "53", "54", "55",
  "61", "62", "63", "64", "65", "66", "67", "68", "69",
  "71", "73", "74", "75", "77", "79",
  "81", "82", "83", "84", "85", "86", "87", "88", "89",
  "91", "92", "93", "94", "95", "96", "97", "98", "99"
]);

function isValidCpf(value: string): boolean {
  if (new Set(value).size === 1) return false;
  const digits = Array.from(value, Number);
  const checkDigit = (length: number) => {
    const sum = digits.slice(0, length).reduce((total, digit, index) => total + digit * (length + 1 - index), 0);
    const result = (sum * 10) % 11;
    return result === 10 ? 0 : result;
  };
  return digits[9] === checkDigit(9) && digits[10] === checkDigit(10);
}

function isValidBrazilianPhone(value: string): boolean {
  return /^\+55\d{10,11}$/.test(value) && BRAZIL_AREA_CODES.has(value.slice(3, 5));
}

function normalizePixKey(value: string): string | null {
  const raw = value.trim();
  if (Array.from(raw).some((character) => character.charCodeAt(0) > 127)) return null;
  const digits = raw.replace(/[.\-/\s()]/g, "");
  if (/^\d+$/.test(digits)) {
    if (digits.length === 11) {
      if (isValidCpf(digits)) return digits;
      const phone = `+55${digits}`;
      return isValidBrazilianPhone(phone) ? phone : null;
    }
    if (digits.length === 14) return digits;
    if (digits.length === 10) {
      const phone = `+55${digits}`;
      return isValidBrazilianPhone(phone) ? phone : null;
    }
  }
  if (raw.startsWith("+")) {
    const phone = `+${raw.slice(1).replace(/[\s()-]/g, "")}`;
    return isValidBrazilianPhone(phone) ? phone : null;
  }
  if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(raw)) return raw.toLowerCase();
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(raw)) return raw.toLowerCase();
  return null;
}

export function validatePix(pix: PixDraft): { value: PixDraft } | { errors: Record<string, string> } {
  const value = { city: pix.city.trim(), key: pix.key.trim(), name: pix.name.trim() };
  const complete = Boolean(value.key && value.name && value.city);
  const empty = !value.key && !value.name && !value.city;
  if (empty) return { value };
  const errors: Record<string, string> = {};
  if (!value.key) errors.key = "Informe a chave PIX.";
  else {
    const normalizedKey = normalizePixKey(value.key);
    if (normalizedKey) value.key = normalizedKey;
    else errors.key = "Informe uma chave PIX válida.";
  }
  if (!value.name) errors.name = "Informe o nome do recebedor.";
  if (!value.city) errors.city = "Informe a cidade do recebedor.";
  if (Array.from(value.name).length > 255) errors.name = "Informe no máximo 255 caracteres.";
  if (Array.from(value.city).length > 255) errors.city = "Informe no máximo 255 caracteres.";
  return complete && !Object.keys(errors).length ? { value } : { errors };
}

export function communicationBodyBytes(value: string): number {
  return new TextEncoder().encode(value).length;
}

const allowedUploadTypes = new Set(["application/pdf", "image/jpeg", "image/png"]);
const maxUploadBytes = 10 * 1024 * 1024;

export interface UploadValidationMessages {
  empty?: (file: File) => string;
  oversized?: (file: File) => string;
  unsupported?: (file: File) => string;
}

export function validateUpload(file: File, messages: UploadValidationMessages = {}): ValidationResult<File> {
  if (!allowedUploadTypes.has(file.type)) {
    return { error: messages.unsupported?.(file) ?? "Envie um arquivo PDF, JPG ou PNG." };
  }
  if (file.size === 0) {
    return { error: messages.empty?.(file) ?? "O arquivo está vazio." };
  }
  if (file.size > maxUploadBytes) {
    return { error: messages.oversized?.(file) ?? "O arquivo deve ter no máximo 10 MB." };
  }
  return { value: file };
}
