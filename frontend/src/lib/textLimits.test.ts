import { expect, it } from "vitest";

import { limitApiCharacters } from "./textLimits";

it("limits text by Unicode code points like the API", () => {
  expect(limitApiCharacters("a😀b", 2)).toBe("a😀");
  expect(limitApiCharacters("😀".repeat(255), 255)).toBe("😀".repeat(255));
  expect(limitApiCharacters("😀".repeat(256), 255)).toBe("😀".repeat(255));
});
