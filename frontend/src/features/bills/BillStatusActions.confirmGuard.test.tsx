import { cleanup, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";

import type { ConfirmDialogProps } from "../../components/ConfirmDialog";
import type { components } from "../../lib/api/schema";
import { BillStatusActions } from "./BillStatusActions";

const analytics = vi.hoisted(() => ({ pushAnalyticsFromResponse: vi.fn() }));
vi.mock("../auth/analytics", () => analytics);

// The real ConfirmDialog only renders its accept button while a transition is
// selected. This stub keeps the confirmation reachable with no selection so
// the guard against a stray confirmation can be exercised.
vi.mock("../../components/ConfirmDialog", () => ({
  ConfirmDialog: ({ onConfirm }: ConfirmDialogProps) => (
    <button onClick={onConfirm} type="button">Confirmar transição</button>
  )
}));

type Bill = components["schemas"]["BillDetailResponse"];
const bill: Bill = {
  available_transitions: [
    { label: "Marcar como pago", requires_confirmation: true, style: "primary", target: "paid" }
  ],
  capabilities: {
    can_compose: true,
    can_delete: true, can_delete_receipts: true, can_download_invoice: true,
    can_download_recibo: false, can_edit: true, can_regenerate: true,
    can_reorder_receipts: true, can_send_invoice: true, can_send_recibo: false,
    can_transition: true, can_upload_receipts: true
  },
  communications: [], created_at: "2026-07-18T10:00:00Z", due_date: "2026-08-10",
  has_invoice: true, has_recibo: false, line_items: [], notes: "", pdf_render_status: null,
  receipts: [], reference_month: "2026-07", status: "sent", status_updated_at: null,
  total_amount: 250000, uuid: "bill-public-uuid"
};

afterEach(() => {
  cleanup();
  analytics.pushAnalyticsFromResponse.mockReset();
  vi.unstubAllGlobals();
});

it("ignores a dialog confirmation raised without a selected transition", async () => {
  const user = userEvent.setup();
  const fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  const onChange = vi.fn();
  render(<BillStatusActions billingUuid="billing-public-uuid" bill={bill} onChange={onChange} onStale={vi.fn()} />);

  await user.click(screen.getByRole("button", { name: "Confirmar transição" }));

  expect(fetchMock).not.toHaveBeenCalled();
  expect(onChange).not.toHaveBeenCalled();
  expect(screen.getByRole("button", { name: "Marcar como pago" })).toBeEnabled();
});
