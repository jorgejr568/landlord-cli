import { render, screen, within } from "@testing-library/react";
import { expect, it } from "vitest";

import { BillLifecycle } from "./InvoiceLifecycle";

it("renders the canonical invoice lifecycle with an overdue branch", () => {
  render(<BillLifecycle status="delayed_payment" />);

  const lifecycle = screen.getByRole("region", { name: "Progresso da fatura" });
  expect(within(lifecycle).getByText("Rascunho").closest("li")).toHaveAttribute("data-state", "complete");
  expect(within(lifecycle).getByText("Enviado").closest("li")).toHaveAttribute("data-state", "complete");
  expect(within(lifecycle).getByText("Pago").closest("li")).toHaveAttribute("data-state", "future");
  expect(within(lifecycle).getByText("Pagamento atrasado").closest("div")).toHaveAttribute("data-state", "current");
});

it("does not imply progress through the successful path for a cancelled invoice", () => {
  render(<BillLifecycle status="cancelled" />);

  expect(screen.getByText("Cancelado").closest("div")).toHaveAttribute("data-state", "current");
  expect(screen.queryByText("Pago")).not.toBeInTheDocument();
});
