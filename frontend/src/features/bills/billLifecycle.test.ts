import { describe, expect, it } from "vitest";

import { groupBillTransitions, modelBillLifecycle } from "./billLifecycle";

describe("groupBillTransitions", () => {
  it("promotes the semantic next action regardless of backend ordering", () => {
    const cancel = { label: "Cancelar fatura", requires_confirmation: true, style: "danger", target: "cancelled" };
    const reverse = { label: "Voltar para publicado", requires_confirmation: true, style: "other", target: "published" };
    const pay = { label: "Marcar como pago", requires_confirmation: true, style: "primary", target: "paid" };

    expect(groupBillTransitions("sent", [cancel, reverse, pay])).toEqual({
      destructive: [cancel],
      primary: pay,
      secondary: [reverse]
    });
  });

  it("treats reopening as the next action for a cancelled bill", () => {
    const reopen = { label: "Reabrir fatura", requires_confirmation: true, style: "primary", target: "draft" };
    expect(groupBillTransitions("cancelled", [reopen])).toEqual({ destructive: [], primary: reopen, secondary: [] });
  });
});

describe("modelBillLifecycle", () => {
  it("shows delayed payment as a branch from sent without replacing the canonical path", () => {
    expect(modelBillLifecycle("delayed_payment")).toEqual({
      branch: { id: "delayed_payment", label: "Pagamento atrasado", state: "current" },
      stages: [
        { id: "draft", label: "Rascunho", state: "complete" },
        { id: "published", label: "Publicado", state: "complete" },
        { id: "sent", label: "Enviado", state: "complete" },
        { id: "paid", label: "Pago", state: "future" }
      ]
    });
  });

  it("keeps cancellation isolated from the successful lifecycle", () => {
    expect(modelBillLifecycle("cancelled")).toEqual({
      branch: { id: "cancelled", label: "Cancelado", state: "current" },
      stages: []
    });
  });
});
