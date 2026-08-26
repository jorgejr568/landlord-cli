import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { jsonResponse } from "../../test/auth";
import { OrganizationEditPage } from "./OrganizationEditPage";

const analytics = vi.hoisted(() => ({ pushAnalyticsFromResponse: vi.fn() }));
vi.mock("../auth/analytics", () => analytics);

type OrganizationDetail = components["schemas"]["OrganizationLoginDetailResponse"];

const detail: OrganizationDetail = {
  capabilities: { can_create_billing: true, can_invite: true, can_manage: true, can_view_billing_stats: true },
  created_at: "2026-07-18T10:00:00Z",
  current_role: "admin",
  enforce_mfa: false,
  invites: [],
  members: [],
  name: "Ribeiro Gestão Patrimonial",
  settings: {
    pix_key: "+5571999999999",
    pix_merchant_city: "SALVADOR",
    pix_merchant_name: "RIBEIRO GESTAO"
  },
  stats: {
    active_count: 0,
    billed_count: 0,
    expected: 0,
    net_income: 0,
    overdue: 0,
    overdue_count: 0,
    paid_count: 0,
    pending: 0,
    pending_count: 0,
    received: 0,
    total_expenses: 0,
    year: 2026
  },
  updated_at: "2026-07-18T11:00:00Z",
  uuid: "org-public-uuid"
};

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function renderPage(settings: OrganizationDetail["settings"] = detail.settings) {
  vi.stubGlobal("fetch", vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const key = `${init?.method ?? "GET"} ${String(input)}`;
    if (key !== "GET /api/v1/organizations/org-public-uuid") throw new Error(`Unexpected request: ${key}`);
    return Promise.resolve(jsonResponse({ ...detail, settings }));
  }));

  return render(
    <MemoryRouter initialEntries={["/organizations/org-public-uuid/edit"]}>
      <Routes>
        <Route element={<OrganizationEditPage />} path="/organizations/:orgUuid/edit" />
      </Routes>
    </MemoryRouter>
  );
}

function renderPendingPage() {
  vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>(() => undefined)));
  return render(
    <MemoryRouter initialEntries={["/organizations/org-public-uuid/edit"]}>
      <Routes>
        <Route element={<OrganizationEditPage />} path="/organizations/:orgUuid/edit" />
      </Routes>
    </MemoryRouter>
  );
}

it("keeps navigation and page context visible while organization settings load", () => {
  renderPendingPage();

  expect(screen.getByRole("heading", { level: 1, name: "Editar Organização" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Organizações" })).toHaveAttribute("href", "/organizations/");
  expect(screen.getByRole("status", { name: "Carregando organização…" })).toBeVisible();
});

it("frames organization editing as one connected settings workspace", async () => {
  renderPage();

  expect(await screen.findByRole("heading", { level: 1, name: "Editar Organização" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Ribeiro Gestão Patrimonial" })).toHaveAttribute("href", "/organizations/org-public-uuid");
  expect(screen.getByRole("region", { name: "Configurações da organização" })).toBeVisible();
  expect(screen.getByRole("complementary", { name: "Resumo da configuração" })).toBeVisible();
  expect(screen.getByText("PIX configurado")).toBeVisible();
  expect(screen.getByRole("button", { name: "Salvar alterações" })).toBeVisible();
});

it("provides complete field semantics and clear section hierarchy", async () => {
  renderPage();

  const name = await screen.findByLabelText("Nome da organização");
  const pixKey = screen.getByLabelText("Chave PIX");
  expect(screen.getByRole("heading", { level: 2, name: "Identificação" })).toBeVisible();
  expect(screen.getByRole("heading", { level: 2, name: "Recebimento PIX" })).toBeVisible();
  expect(name).toHaveAttribute("name", "name");
  expect(name).toHaveAttribute("autocomplete", "organization");
  expect(pixKey).toHaveAttribute("name", "pix_key");
  expect(pixKey).toHaveAttribute("autocomplete", "off");
  expect(pixKey).toHaveAttribute("spellcheck", "false");
  expect(pixKey).toHaveAccessibleDescription("Informe DDD + número. O +55 é opcional.");
});

it("makes missing PIX setup clear before editing", async () => {
  renderPage(null);

  expect(await screen.findByText("PIX pendente")).toBeVisible();
  expect(screen.getByText("Preencha os 3 campos de recebimento para emitir faturas com QR Code.")).toBeVisible();
});

it("keeps the summary in sync with the unsaved draft", async () => {
  const user = userEvent.setup();
  renderPage();

  expect(await screen.findByText("Sem alterações pendentes")).toBeVisible();
  await user.clear(screen.getByLabelText("Chave PIX"));

  expect(screen.getByText("Alterações pendentes")).toBeVisible();
  expect(screen.getByText("PIX pendente")).toBeVisible();

  await user.type(screen.getByLabelText("Chave PIX"), "+5571999999999");
  expect(screen.getByText("Sem alterações pendentes")).toBeVisible();
  expect(screen.getByText("PIX configurado")).toBeVisible();
});

it("ignores supplementary inputs outside the persisted organization fields", async () => {
  renderPage();

  expect(await screen.findByText("Sem alterações pendentes")).toBeVisible();
  const supplementaryInput = screen.getByLabelText("Nome da organização");
  supplementaryInput.id = "organization-note";
  fireEvent.change(supplementaryInput, { target: { value: "Nota local" } });

  expect(screen.getByText("Sem alterações pendentes")).toBeVisible();
});
