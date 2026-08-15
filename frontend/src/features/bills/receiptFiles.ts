const ALLOWED_RECEIPT_TYPES = new Set(["application/pdf", "image/jpeg", "image/png"]);
const MAX_RECEIPT_BYTES = 10 * 1024 * 1024;

export function receiptFileError(files: File[]): string | null {
  const unsupported = files.find((file) => !ALLOWED_RECEIPT_TYPES.has(file.type.toLowerCase()));
  if (unsupported) return `O arquivo ${unsupported.name} deve ser PDF, JPEG ou PNG.`;

  const empty = files.find((file) => file.size === 0);
  if (empty) return `O arquivo ${empty.name} está vazio.`;

  const oversized = files.find((file) => file.size > MAX_RECEIPT_BYTES);
  if (oversized) return `O arquivo ${oversized.name} excede o limite de 10 MB.`;

  return null;
}
