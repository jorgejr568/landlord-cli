import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { expect, it } from "vitest";

import { SupportPage } from "./SupportPage";

function renderSupportPage() {
  render(
    <MemoryRouter>
      <SupportPage />
    </MemoryRouter>
  );
}

it("presents support as the page topic and keeps the verified contact expectation", () => {
  renderSupportPage();

  expect(
    screen.getByRole("heading", { level: 1, name: "Como podemos ajudar?" })
  ).toBeVisible();
  expect(
    screen.getByRole("link", { name: "suporte@rentivo.com.br" })
  ).toHaveAttribute("href", "mailto:suporte@rentivo.com.br");
  expect(screen.getByText("Respondemos em até 2 dias úteis.")).toBeVisible();
  expect(
    screen.getByRole("link", { name: "Enviar e-mail ao suporte" })
  ).toHaveAttribute("href", "mailto:suporte@rentivo.com.br");
  expect(document.title).toBe("Suporte - Rentivo");
});

it("routes common support needs to focused self-service destinations", () => {
  renderSupportPage();

  expect(screen.getByRole("link", { name: /Redefinir senha/ })).toHaveAttribute(
    "href",
    "/forgot-password"
  );
  expect(screen.getByRole("link", { name: /Entrar no Rentivo/ })).toHaveAttribute(
    "href",
    "/login"
  );
  expect(
    screen.getByRole("link", { name: /Ver privacidade/ })
  ).toHaveAttribute("href", "/privacy");
  expect(screen.getByRole("link", { name: "Termos de Uso" })).toHaveAttribute(
    "href",
    "/terms"
  );
});

it("provides institutional navigation and a keyboard skip target", () => {
  renderSupportPage();

  expect(
    screen.getByRole("navigation", { name: "Navegação institucional" })
  ).toBeVisible();
  expect(screen.getByRole("link", { name: "Pular para o suporte" })).toHaveAttribute(
    "href",
    "#support-content"
  );
  expect(document.querySelector("#support-content")).toHaveAttribute("tabindex", "-1");
});
