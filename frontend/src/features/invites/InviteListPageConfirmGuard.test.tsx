import { cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { jsonResponse } from "../../test/auth";
import { InviteListPage } from "./InviteListPage";

const analytics = vi.hoisted(() => ({ pushAnalyticsFromResponse: vi.fn() }));
const auth = vi.hoisted(() => ({ refreshSession: vi.fn<() => Promise<void>>().mockResolvedValue(undefined) }));
vi.mock("../auth/analytics", () => analytics);
vi.mock("../auth/AuthProvider", () => ({ useAuth: () => auth }));
// A dialog stub that exposes onConfirm even while closed, so the page's
// selection guard can be exercised against a misbehaving dialog.
vi.mock("../../components/ConfirmDialog", () => ({
  ConfirmDialog: ({ onConfirm }: { onConfirm: () => void }) => (
    <button onClick={onConfirm} type="button">Confirmar seleção</button>
  )
}));

type Invite = components["schemas"]["PendingInviteLoginResponse"];

const acmeInvite: Invite = {
  created_at: "2026-07-18T10:00:00Z",
  enforce_mfa: false,
  invited_by_email: "owner@acme.com",
  organization_name: "Acme",
  organization_uuid: "org-acme",
  role: "manager",
  uuid: "invite-public-uuid"
};

afterEach(() => {
  cleanup();
  analytics.pushAnalyticsFromResponse.mockReset();
  auth.refreshSession.mockReset().mockResolvedValue(undefined);
  vi.unstubAllGlobals();
});

function LocationProbe() {
  const location = useLocation();
  return <output data-testid="location">{location.pathname}</output>;
}

it("ignores dialog confirmations fired without a selected invite", async () => {
  const user = userEvent.setup();
  const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const key = `${init?.method ?? "GET"} ${String(input)}`;
    if (key === "GET /api/v1/invites") return jsonResponse({ items: [acmeInvite] });
    if (key === "POST /api/v1/invites/invite-public-uuid/accept") {
      return jsonResponse({ mfa_setup_required: false, organization_uuid: "org-acme", status: "accepted" });
    }
    throw new Error(`Unexpected request: ${key}`);
  });
  vi.stubGlobal("fetch", fetchMock);
  render(
    <MemoryRouter initialEntries={["/invites/"]}>
      <Routes>
        <Route element={<><InviteListPage /><LocationProbe /></>} path="/invites/" />
        <Route element={<LocationProbe />} path="/organizations/:orgUuid" />
      </Routes>
    </MemoryRouter>
  );
  await screen.findByText("owner@acme.com");

  await user.click(screen.getByRole("button", { name: "Confirmar seleção" }));

  expect(fetchMock).toHaveBeenCalledTimes(1);
  expect(screen.getByTestId("location")).toHaveTextContent("/invites/");

  await user.click(screen.getByRole("button", { name: "Aceitar" }));
  await user.click(screen.getByRole("button", { name: "Confirmar seleção" }));

  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/organizations/org-acme"));
  expect(fetchMock).toHaveBeenCalledTimes(2);
});
