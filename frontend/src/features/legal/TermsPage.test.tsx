import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { expect, it } from "vitest";

import { TermsPage } from "./TermsPage";

it("renders a navigable terms document with its legal copy intact", () => {
  render(
    <MemoryRouter>
      <TermsPage />
    </MemoryRouter>
  );

  expect(
    screen.getByRole("heading", { level: 1, name: "Termos de Uso" })
  ).toBeVisible();
  expect(screen.getByRole("article", { name: "Termos de Uso" })).toBeVisible();
  expect(screen.getByRole("navigation", { name: "Nestes termos" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Pagamentos" })).toHaveAttribute(
    "href",
    "#pagamentos"
  );
  expect(screen.getByRole("link", { name: "Voltar ao início" })).toHaveAttribute(
    "href",
    "/"
  );
  expect(screen.getByRole("link", { name: "Pular para o conteúdo" })).toHaveAttribute(
    "href",
    "#terms-content"
  );
  expect(screen.getByText("23 de julho de 2026")).toHaveAttribute(
    "datetime",
    "2026-07-23"
  );
  expect(
    screen.getByRole("heading", { level: 2, name: "O serviço" })
  ).toBeVisible();
  expect(
    screen.getByRole("heading", { level: 2, name: "Pagamentos" })
  ).toBeVisible();
  expect(screen.getByText(/não é instituição de pagamento/)).toBeVisible();
  expect(screen.getByText(/serviço é fornecido "como está"/)).toBeVisible();
  expect(screen.getByText(/regidos pelas leis brasileiras/)).toBeVisible();
  expect(
    screen.getByRole("link", { name: "Política de Privacidade" })
  ).toHaveAttribute("href", "/privacy");
  expect(
    screen.getByRole("link", { name: "suporte@rentivo.com.br" })
  ).toHaveAttribute("href", "mailto:suporte@rentivo.com.br");
  expect(document.title).toBe("Termos de Uso - Rentivo");
});
