import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router";

import { NotFoundPage } from "./NotFoundPage";

it("shows the missing route with clear destinations back into the workspace", () => {
  render(
    <MemoryRouter initialEntries={["/caminho/que-nao-existe"]}>
      <NotFoundPage />
    </MemoryRouter>
  );

  expect(screen.getByText("404")).toBeVisible();
  expect(screen.getByRole("heading", { name: "Esta página não está no mapa" })).toBeVisible();
  expect(screen.getByText("/caminho/que-nao-existe")).toBeVisible();
  expect(screen.getByRole("link", { name: "Minhas cobranças" })).toHaveAttribute("href", "/billings/");
  expect(screen.getByRole("link", { name: "Nova cobrança" })).toHaveAttribute("href", "/billings/create");
  expect(screen.getByRole("link", { name: "Organizações" })).toHaveAttribute("href", "/organizations/");
  expect(screen.getByRole("navigation", { name: "Atalhos de recuperação" })).toBeVisible();
  expect(document.title).toBe("Página não encontrada - Rentivo");
});

it("returns to the previous page without replacing browser history", async () => {
  const user = userEvent.setup();
  render(
    <MemoryRouter initialEntries={["/origem", "/caminho-perdido"]} initialIndex={1}>
      <Routes>
        <Route element={<h1>Página anterior</h1>} path="/origem" />
        <Route element={<NotFoundPage />} path="*" />
      </Routes>
    </MemoryRouter>
  );

  await user.click(screen.getByRole("button", { name: "Voltar" }));

  expect(screen.getByRole("heading", { name: "Página anterior" })).toBeVisible();
});
