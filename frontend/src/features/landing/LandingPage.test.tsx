import { render, screen, within } from "@testing-library/react";
import { expect, it } from "vitest";

import { LandingPage } from "./LandingPage";

it("guides visitors through the billing flow and its primary paths", () => {
  render(<LandingPage />);

  expect(
    screen.getByRole("heading", { level: 1, name: /cobranças de aluguel.*pix em segundos/i })
  ).toBeVisible();
  expect(screen.getByRole("link", { name: "Pular para o conteúdo" })).toHaveAttribute(
    "href", "#conteudo"
  );
  expect(screen.getByRole("navigation", { name: "Navegação principal" })).toBeVisible();

  const signupLinks = screen.getAllByRole("link", { name: "Criar conta" });
  expect(signupLinks).toHaveLength(3);
  signupLinks.forEach((link) => expect(link).toHaveAttribute("href", "/signup"));

  expect(screen.getByRole("region", { name: "Exemplo do fluxo de cobrança" })).toHaveTextContent(
    "CobrançaPDF + PIXPagamento"
  );
  const flow = screen.getByRole("list", { name: "Fluxo mensal" });
  expect(within(flow).getByRole("heading", { name: "Configure" })).toBeVisible();
  expect(within(flow).getByRole("heading", { name: "Gere" })).toBeVisible();
  expect(within(flow).getByRole("heading", { name: "Acompanhe" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "O aluguel segue um caminho claro" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Cada detalhe continua no mesmo lugar" })).toBeVisible();

  expect(screen.getAllByRole("link", { name: "GitHub" })[0]).toHaveAttribute(
    "href",
    "https://github.com/jorgejr568/rentivo"
  );
  expect(screen.getByRole("link", { name: "Privacidade" })).toHaveAttribute(
    "href",
    "/privacy"
  );
  expect(screen.getByRole("link", { name: "Termos" })).toHaveAttribute(
    "href",
    "/terms"
  );
  expect(screen.getByRole("link", { name: "Suporte" })).toHaveAttribute(
    "href",
    "/support"
  );
  expect(screen.getByRole("contentinfo")).toHaveTextContent(
    "Gestão de cobranças para imóveis."
  );
});
