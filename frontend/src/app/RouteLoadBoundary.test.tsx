import { act, lazy, useState } from "react";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { Link, MemoryRouter } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import { RouteLoadBoundary } from "./RouteLoadBoundary";

afterEach(() => {
  vi.restoreAllMocks();
  window.history.pushState({}, "", "/");
});

it("shows an accessible skeleton until a lazy route is ready", async () => {
  let finishLoading!: () => void;
  const LazyPage = lazy(
    () =>
      new Promise<{ default: () => React.JSX.Element }>((resolve) => {
        finishLoading = () => resolve({ default: () => <h1>Página carregada</h1> });
      })
  );

  render(
    <MemoryRouter>
      <RouteLoadBoundary>
        <LazyPage />
      </RouteLoadBoundary>
    </MemoryRouter>
  );

  const loading = screen.getByRole("status");
  expect(loading).toHaveTextContent("Carregando página...");
  expect(loading).toHaveAttribute("aria-busy", "true");
  expect(loading).toHaveClass("route-skeleton", "route-skeleton--landing");
  expect(loading.querySelectorAll("[aria-hidden='true']").length).toBeGreaterThan(2);
  expect(screen.queryByRole("heading", { name: "Página carregada" })).not.toBeInTheDocument();

  await act(async () => finishLoading());

  expect(await screen.findByRole("heading", { name: "Página carregada" })).toBeVisible();
  expect(screen.queryByRole("status")).not.toBeInTheDocument();
});

it.each([
  ["/login", "route-skeleton--auth"],
  ["/billings/", "route-skeleton--collection"],
  ["/billings/billing-1", "route-skeleton--detail"]
])("matches the lazy skeleton to the %s route shape", (pathname, expectedClass) => {
  const PendingPage = lazy(
    () => new Promise<{ default: () => React.JSX.Element }>(() => undefined)
  );

  render(
    <MemoryRouter initialEntries={[pathname]}>
      <RouteLoadBoundary>
        <PendingPage />
      </RouteLoadBoundary>
    </MemoryRouter>
  );

  expect(screen.getByRole("status")).toHaveClass("route-skeleton", expectedClass);
});

it("preserves loaded page state when only the search parameters change", async () => {
  const user = userEvent.setup();

  function StatefulPage() {
    const [count, setCount] = useState(0);
    return (
      <>
        <button onClick={() => setCount((current) => current + 1)} type="button">
          Alterações {count}
        </button>
        <Link to="?aba=historico">Ver histórico</Link>
      </>
    );
  }

  render(
    <MemoryRouter initialEntries={["/cobrancas/atual"]}>
      <RouteLoadBoundary>
        <StatefulPage />
      </RouteLoadBoundary>
    </MemoryRouter>
  );

  await user.click(screen.getByRole("button", { name: "Alterações 0" }));
  await user.click(screen.getByRole("link", { name: "Ver histórico" }));

  expect(screen.getByRole("button", { name: "Alterações 1" })).toBeVisible();
});

it("offers a reload action when a route chunk cannot be loaded", async () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);
  const BrokenPage = lazy(() => Promise.reject(new Error("chunk unavailable")));
  window.history.pushState({}, "", "/cobrancas/pendentes");

  render(
    <MemoryRouter>
      <RouteLoadBoundary>
        <BrokenPage />
      </RouteLoadBoundary>
    </MemoryRouter>
  );

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Não foi possível carregar esta página."
  );
  expect(screen.getByRole("link", { name: "Recarregar página" })).toHaveAttribute(
    "href",
    window.location.href
  );
  expect(consoleError).toHaveBeenCalled();
});
