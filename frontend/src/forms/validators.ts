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

export function validatePix(pix: PixDraft): { value: PixDraft } | { errors: Record<string, string> } {
  const value = { city: pix.city.trim(), key: pix.key.trim(), name: pix.name.trim() };
  const complete = Boolean(value.key && value.name && value.city);
  const empty = !value.key && !value.name && !value.city;
  if (empty) return { value };
  const errors: Record<string, string> = {};
  if (!value.key) errors.key = "Informe a chave PIX.";
  if (!value.name) errors.name = "Informe o nome do recebedor.";
  if (!value.city) errors.city = "Informe a cidade do recebedor.";
  if (Array.from(value.name).length > 25) errors.name = "Informe no máximo 25 caracteres.";
  if (Array.from(value.city).length > 15) errors.city = "Informe no máximo 15 caracteres.";
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
