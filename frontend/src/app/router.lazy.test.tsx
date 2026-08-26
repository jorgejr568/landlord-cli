import { act, lazy } from "react";
import { render, screen } from "@testing-library/react";
import { RouterProvider } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import { AUTH_CONFIG, AUTHENTICATED_RESPONSE, jsonResponse } from "../test/auth";
import { createAppRouter } from "./router";

afterEach(() => {
  vi.unstubAllGlobals();
  window.history.pushState({}, "", "/");
});

it("keeps the authenticated shell visible while a protected route chunk loads", async () => {
  let finishLoading!: () => void;
  const LazyPage = lazy(
    () =>
      new Promise<{ default: () => React.JSX.Element }>((resolve) => {
        finishLoading = () => resolve({ default: () => <h1>Relatório carregado</h1> });
      })
  );
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL) => {
      if (String(input) === "/api/v1/auth/config") return jsonResponse(AUTH_CONFIG);
      if (String(input) === "/api/v1/auth/session") {
        return jsonResponse(AUTHENTICATED_RESPONSE);
      }
      throw new Error(`Unexpected request: ${String(input)}`);
    })
  );
  window.history.pushState({}, "", "/lazy-preview");
  const router = createAppRouter([{ element: <LazyPage />, path: "/lazy-preview" }]);
  const view = render(<RouterProvider router={router} />);

  expect(await screen.findByRole("button", { name: "user@example.com" })).toBeVisible();
  expect(screen.getByRole("status")).toHaveTextContent("Carregando página...");
  expect(screen.getByRole("main")).toContainElement(screen.getByRole("status"));

  await act(async () => finishLoading());

  expect(await screen.findByRole("heading", { name: "Relatório carregado" })).toBeVisible();
  expect(screen.queryByRole("status")).not.toBeInTheDocument();

  view.unmount();
  router.dispose();
});
