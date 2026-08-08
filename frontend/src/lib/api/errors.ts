import { ApiError } from "./client";

export function errorMessage(error: unknown, fallback: string): string {
  return error instanceof ApiError ? error.message : fallback;
}

export function normalizedFieldErrors(error: unknown): Record<string, string> {
  if (!(error instanceof ApiError)) return {};
  return Object.fromEntries(
    Object.entries(error.fields).map(([key, message]) => [key.replace(/^body\./, ""), message])
  );
}

export function firstFieldError(
  fields: Record<string, string>,
  preferred: string[]
): string | undefined {
  return preferred.find((key) => fields[key]) ?? Object.keys(fields)[0];
}
