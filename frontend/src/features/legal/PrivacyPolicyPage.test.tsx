import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { expect, it } from "vitest";

import { PrivacyPolicyPage } from "./PrivacyPolicyPage";

it("renders a navigable privacy document with its legal copy intact", () => {
  render(
    <MemoryRouter>
      <PrivacyPolicyPage />
    </MemoryRouter>
  );

  expect(
    screen.getByRole("heading", { level: 1, name: "Política de Privacidade" })
  ).toBeVisible();
  expect(
    screen.getByRole("article", { name: "Política de Privacidade" })
  ).toBeVisible();
  expect(screen.getByRole("navigation", { name: "Nesta política" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Dados que coletamos" })).toHaveAttribute(
    "href",
    "#dados-coletados"
  );
  expect(screen.getByRole("link", { name: "Voltar ao início" })).toHaveAttribute(
    "href",
    "/"
  );
  expect(screen.getByRole("link", { name: "Pular para o conteúdo" })).toHaveAttribute(
    "href",
    "#privacy-content"
  );
  expect(screen.getByText("13 de agosto de 2026")).toHaveAttribute(
    "datetime",
    "2026-08-13"
  );
  expect(
    screen.getByRole("heading", { level: 2, name: "Dados que coletamos" })
  ).toBeVisible();
  expect(
    screen.getByRole("heading", { level: 2, name: "Seus direitos (LGPD)" })
  ).toBeVisible();
  expect(screen.getAllByRole("link", { name: "Termos de Uso" })).toHaveLength(1);
  expect(screen.getByText(/OpenRouter/)).toHaveTextContent(
    /análise opcional de segurança/
  );
  expect(
    screen.getByRole("link", { name: "suporte@rentivo.com.br" })
  ).toHaveAttribute("href", "mailto:suporte@rentivo.com.br");
  expect(screen.getByRole("link", { name: "Termos de Uso" })).toHaveAttribute(
    "href",
    "/terms"
  );
  expect(document.title).toBe("Política de Privacidade - Rentivo");
});
