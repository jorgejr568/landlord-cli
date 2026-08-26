import { afterEach, expect, it, vi } from "vitest";

import { shouldAutoFocus } from "./autofocus";

afterEach(() => vi.unstubAllGlobals());

it("suppresses initial focus on narrow or coarse-pointer devices", () => {
  const matchMedia = vi.fn((query: string) => ({ matches: query.includes("max-width") }));
  vi.stubGlobal("matchMedia", matchMedia);

  expect(shouldAutoFocus()).toBe(false);
  expect(matchMedia).toHaveBeenCalledWith("(max-width: 760px), (pointer: coarse)");
});

it("keeps initial focus on desktop and in non-browser test fallbacks", () => {
  vi.stubGlobal("matchMedia", vi.fn(() => ({ matches: false })));
  expect(shouldAutoFocus()).toBe(true);

  vi.stubGlobal("matchMedia", undefined);
  expect(shouldAutoFocus()).toBe(true);
});
