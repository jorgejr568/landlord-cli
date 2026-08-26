import { expect, it, vi } from "vitest";

import { openMobileAuthorizationCallback } from "./mobileAuthorization";

it("opens the native mobile authorization callback", () => {
  const assign = vi.fn();

  openMobileAuthorizationCallback("rentivo://auth/callback?code=code&state=state", assign);

  expect(assign).toHaveBeenCalledWith("rentivo://auth/callback?code=code&state=state");
});

it("uses browser navigation by default", () => {
  expect(() => openMobileAuthorizationCallback("rentivo://auth/callback?code=code&state=state")).not.toThrow();
});
