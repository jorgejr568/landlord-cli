/**
 * Applies API string limits using Unicode code points, matching Python's
 * `len()` and Pydantic's `max_length` semantics.
 */
export function limitApiCharacters(value: string, maximum: number): string {
  return Array.from(value).slice(0, maximum).join("");
}
