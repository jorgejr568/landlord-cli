import { render, screen, waitFor } from "@testing-library/react";
import { RouterProvider, type RouteObject } from "react-router";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

import { AUTH_CONFIG, jsonResponse, problemResponse } from "../test/auth";
import { PUBLIC_AUTH_ROUTE_ID, createAppRouter } from "./router";

const GOOGLE_START_SELECTOR = 'a[href="/api/v1/auth/google/start"]';

beforeEach(() => {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/v1/auth/config") {
        return jsonResponse({
          ...AUTH_CONFIG,
          analytics: { gtm_container_id: "" },
          // Production returns google_auth: true. The gate, not the flag, is
          // what must keep Google out of the app.
          feature_flags: { google_auth: true, turnstile: false, turnstile_site_key: "" }
        });
      }
      // Anything else an auth page reaches for is irrelevant here; a failed
      // request still renders the page, which is all this test inspects.
      return problemResponse();
    })
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  sessionStorage.clear();
  window.history.pushState({}, "", "/");
  document.head
    .querySelectorAll("script[data-rentivo-gtm], script[data-rentivo-turnstile]")
    .forEach((script) => script.remove());
});

function findPublicAuthRoutes(routes: RouteObject[]): RouteObject[] {
  for (const route of routes) {
    if (route.id === PUBLIC_AUTH_ROUTE_ID) {
      return route.children ?? [];
    }
    const nested = findPublicAuthRoutes(route.children ?? []);
    if (nested.length > 0) {
      return nested;
    }
  }
  return [];
}

const publicAuthPaths = findPublicAuthRoutes(createAppRouter().routes)
  .map((route) => route.path)
  .filter((path): path is string => Boolean(path));

it("covers every anonymous authentication route", () => {
  // Guards the guard: if the route group is renamed or restructured, the
  // sweep below would silently pass with nothing to check.
  expect(publicAuthPaths.length).toBeGreaterThan(5);
  expect(publicAuthPaths).toContain("/login");
  expect(publicAuthPaths).toContain("/signup");
});

it("shows Google on the website, where guideline 4.8 does not apply", async () => {
  window.history.pushState({}, "", "/login");
  render(<RouterProvider router={createAppRouter()} />);

  await waitFor(() =>
    expect(document.querySelector(GOOGLE_START_SELECTOR)).toBeInTheDocument()
  );
});

// App Store guideline 4.8 rejected Rentivo 1.0.1 because the page the iOS app
// opens in ASWebAuthenticationSession offered Google sign-in. The app has no
// equivalent login service, so no page reachable inside that sheet may offer a
// third-party login. Driven off the route table so pages added later are
// covered without touching this test.
it.each(publicAuthPaths)("offers no third-party login at %s inside the iOS handoff", async (path) => {
  const separator = path.includes("?") ? "&" : "?";
  window.history.pushState({}, "", `${path}${separator}mobile_state=native-state`);
  render(<RouterProvider router={createAppRouter()} />);

  // Wait for the auth config to resolve, otherwise the assertion could pass
  // against a page still showing its loading state.
  await waitFor(() => expect(screen.queryByText("Carregando...")).not.toBeInTheDocument());
  expect(document.querySelector(GOOGLE_START_SELECTOR)).not.toBeInTheDocument();
});
