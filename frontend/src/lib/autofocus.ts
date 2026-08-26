export function shouldAutoFocus(): boolean {
  if (typeof matchMedia !== "function") return true;
  return !matchMedia("(max-width: 760px), (pointer: coarse)").matches;
}
