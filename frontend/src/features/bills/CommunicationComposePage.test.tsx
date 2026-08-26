import { cleanup, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { BILLING_CAPABILITIES_ALL, jsonResponse } from "../../test/auth";
import { CommunicationComposePage } from "./CommunicationComposePage";

type Billing = components["schemas"]["BillingResponse"];
type Bill = components["schemas"]["BillDetailResponse"];

const billing: Billing = {
  capabilities: BILLING_CAPABILITIES_ALL,
  communication_templates: [{ body: "Olá {{nome_inquilino}}", comm_type: "bill_ready", subject: "Fatura de julho" }],
  created_at: null,
  description: "Apartamento 302",
  items: [{ amount: 250000, description: "Aluguel", item_type: "fixed", uuid: "01J00000000000000000000010" }],
  name: "Residencial Sol",
  owner: { type: "organization", uuid: "org-uuid", name: "Sol Imóveis" },
  pix_key: "financeiro@example.test",
  pix_merchant_city: "SALVADOR",
  pix_merchant_name: "SOL IMOVEIS",
  pix_needs_setup: false,
  recipients: [
    { email: "ana@example.test", name: "Ana", uuid: "recipient-ana" },
    { email: "bia@example.test", name: "Bia", uuid: "recipient-bia" }
  ],
  reply_to: [],
  stats: { active_count: 1, billed_count: 1, expected: 250000, net_income: 250000, overdue: 0, overdue_count: 0, paid_count: 0, pending: 250000, pending_count: 1, received: 0, total_expenses: 0, year: 2026 },
  updated_at: null,
  uuid: "billing-public-uuid"
};

const bill: Bill = {
  available_transitions: [],
  capabilities: {
    can_compose: true,
    can_delete: true,
    can_delete_receipts: true,
    can_download_invoice: true,
    can_download_recibo: false,
    can_edit: true,
    can_open_recibo: false,
    can_regenerate: true,
    can_reorder_receipts: true,
    can_send_invoice: true,
    can_send_recibo: false,
    can_transition: true,
    can_upload_receipts: true
  },
  communications: [],
  created_at: "2026-07-18T09:00:00Z",
  due_date: "2026-08-10",
  has_invoice: true,
  has_recibo: false,
  line_items: [{ amount: 250000, description: "Aluguel", item_type: "fixed", sort_order: 0 }],
  notes: "",
  pdf_render_status: null,
  receipts: [],
  reference_month: "2026-07",
  status: "pending",
  status_updated_at: "2026-07-18T10:00:00Z",
  total_amount: 250000,
  uuid: "bill-public-uuid"
};

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function renderComposer() {
  vi.stubGlobal("fetch", vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const key = `${init?.method ?? "GET"} ${String(input)}`;
    if (key === "GET /api/v1/billings/billing-public-uuid") return Promise.resolve(jsonResponse(billing));
    if (key === "GET /api/v1/billings/billing-public-uuid/bills/bill-public-uuid") return Promise.resolve(jsonResponse(bill));
    throw new Error(`Unexpected request: ${key}`);
  }));

  return render(
    <MemoryRouter initialEntries={["/billings/billing-public-uuid/bills/bill-public-uuid/communications/compose?type=bill_ready"]}>
      <Routes>
        <Route element={<CommunicationComposePage />} path="/billings/:billingUuid/bills/:billUuid/communications/compose" />
      </Routes>
    </MemoryRouter>
  );
}

it("keeps invoice context and recipient bulk controls in one sending workspace", async () => {
  const user = userEvent.setup();
  renderComposer();

  const workspace = await screen.findByRole("article", { name: "Envio da fatura de Julho/2026" });
  const summary = within(workspace).getByRole("region", { name: "Resumo do envio" });
  expect(summary).toHaveTextContent("R$ 2.500,00");
  expect(summary).toHaveTextContent("10/08/2026");
  expect(summary).toHaveTextContent("2 selecionados");

  await user.click(within(workspace).getByRole("button", { name: "Limpar seleção" }));
  expect(screen.getByLabelText("Ana <ana@example.test>")).not.toBeChecked();
  expect(screen.getByLabelText("Bia <bia@example.test>")).not.toBeChecked();
  expect(summary).toHaveTextContent("0 selecionados");

  await user.click(within(workspace).getByRole("button", { name: "Selecionar todos" }));
  expect(screen.getByLabelText("Ana <ana@example.test>")).toBeChecked();
  expect(screen.getByLabelText("Bia <bia@example.test>")).toBeChecked();
});
