import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { jsonResponse } from "../../test/auth";
import { BillingDetailPage } from "./BillingDetailPage";

const analytics = vi.hoisted(() => ({ pushAnalyticsFromResponse: vi.fn() }));
vi.mock("../auth/analytics", () => analytics);

vi.mock("../../components/ConfirmDialog", () => ({
  ConfirmDialog: ({ onConfirm, title }: { onConfirm: () => void; title: string }) => (
    <button onClick={onConfirm} type="button">{`confirm ${title}`}</button>
  )
}));

type Billing = components["schemas"]["BillingResponse"];

const stats: components["schemas"]["BillingStatsResponse"] = {
  active_count: 1, billed_count: 1, expected: 285_000, net_income: 0, overdue: 0, overdue_count: 0,
  paid_count: 0, pending: 285_000, pending_count: 1, received: 0, total_expenses: 0, year: 2026
};
const billing: Billing = {
  capabilities: {
    can_create_bills: true, can_create_exports: true, can_delete: true, can_edit: true,
    can_manage_bills: true, can_manage_theme: true, can_read_attachments: true, can_read_bills: true,
    can_read_expenses: true, can_read_theme: true, can_transfer: true, can_upload_bill_receipts: true,
    can_write_attachments: true, can_write_expenses: true
  },
  communication_templates: [], created_at: null, description: "Inquilino atual",
  items: [{ amount: 285_000, description: "Aluguel", item_type: "fixed", uuid: "item-rent" }],
  name: "Apartamento 302", owner: { name: null, type: "user", uuid: null }, pix_key: "pix@example.com",
  pix_merchant_city: "SALVADOR", pix_merchant_name: "MARIA", pix_needs_setup: false,
  recipients: [], reply_to: [], stats, updated_at: null, uuid: "billing-public"
};
const organization: components["schemas"]["OrganizationResponse"] = {
  capabilities: { can_create_billing: false, can_invite: false, can_manage: false, can_view_billing_stats: false }, created_at: null,
  current_role: "viewer", enforce_mfa: false, name: "Ribeiro Imóveis", updated_at: null, uuid: "org-public"
};

afterEach(() => {
  cleanup();
  analytics.pushAnalyticsFromResponse.mockReset();
  vi.unstubAllGlobals();
});

function installFetch(handler: (key: string, init?: RequestInit) => Response | Promise<Response>) {
  const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => handler(`${init?.method ?? "GET"} ${String(input)}`, init));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}
function dataResponse(key: string) {
  if (key === "GET /api/v1/billings/billing-public") return jsonResponse(billing);
  if (key === "GET /api/v1/billings/billing-public/bills") return jsonResponse({ items: [] });
  if (key === "GET /api/v1/billings/billing-public/expenses") return jsonResponse({ items: [] });
  if (key === "GET /api/v1/billings/billing-public/attachments") return jsonResponse({ items: [] });
  if (key === "GET /api/v1/organizations") return jsonResponse({ items: [organization] });
  throw new Error(`Unexpected request: ${key}`);
}

it("ignores a stray dialog confirmation when no expense removal is pending", async () => {
  const user = userEvent.setup();
  const requests: string[] = [];
  installFetch((key) => { requests.push(key); return dataResponse(key); });
  render(<MemoryRouter initialEntries={["/billings/billing-public"]}><Routes>
    <Route element={<BillingDetailPage />} path="/billings/:billingUuid" />
  </Routes></MemoryRouter>);
  await screen.findByRole("heading", { name: "Apartamento 302" });

  await user.click(screen.getByRole("button", { name: "confirm Remover esta despesa?" }));

  expect(requests.filter((key) => key.startsWith("DELETE"))).toHaveLength(0);
  expect(analytics.pushAnalyticsFromResponse).not.toHaveBeenCalled();
});
