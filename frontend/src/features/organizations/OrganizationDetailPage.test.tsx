import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import {
  BILLING_CAPABILITIES_ALL,
  BILLING_CAPABILITIES_NONE,
  jsonResponse,
  problemResponse
} from "../../test/auth";
import { chooseSelectOption } from "../../test/select";
import { OrganizationDetailPage } from "./OrganizationDetailPage";

const analytics = vi.hoisted(() => ({ pushAnalyticsFromResponse: vi.fn() }));
const auth = vi.hoisted(() => ({ refreshSession: vi.fn<() => Promise<void>>().mockResolvedValue(undefined) }));
vi.mock("../auth/analytics", () => analytics);
vi.mock("../auth/AuthProvider", () => ({ useAuth: () => auth }));

type Detail = components["schemas"]["OrganizationLoginDetailResponse"];
type BillingList = components["schemas"]["BillingListResponse"];

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((complete, fail) => { resolve = complete; reject = fail; });
  return { promise, reject, resolve };
}

const detail: Detail = {
  capabilities: { can_create_billing: true, can_invite: true, can_manage: true, can_view_billing_stats: true },
  created_at: "2026-07-18T10:00:00Z",
  current_role: "admin",
  enforce_mfa: false,
  invites: [
    { created_at: null, invited_email: "pending@example.com", responded_at: null, role: "manager", status: "pending", uuid: "sent-1" },
    { created_at: null, invited_email: "accepted@example.com", responded_at: null, role: "admin", status: "accepted", uuid: "sent-2" },
    { created_at: null, invited_email: "declined@example.com", responded_at: null, role: "viewer", status: "declined", uuid: "sent-3" }
  ],
  members: [
    { created_at: null, email: "owner@example.com", is_current_user: true, role: "admin", user_id: 42 },
    { created_at: null, email: "manager@example.com", is_current_user: false, role: "manager", user_id: 77 },
    { created_at: null, email: "viewer@example.com", is_current_user: false, role: "viewer", user_id: 88 }
  ],
  name: "Acme Imóveis",
  settings: { pix_key: "pix", pix_merchant_city: "SALVADOR", pix_merchant_name: "ACME" },
  stats: {
    active_count: 4,
    billed_count: 8,
    expected: 990000,
    net_income: 320000,
    overdue: 140000,
    overdue_count: 1,
    paid_count: 4,
    pending: 310000,
    pending_count: 2,
    received: 540000,
    total_expenses: 220000,
    year: 2026
  },
  updated_at: "2026-07-18T11:00:00Z",
  uuid: "org-public-uuid"
};

const emptyStats: BillingList["stats"] = {
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
};

const billings: BillingList = {
  items: [
    {
      capabilities: { ...BILLING_CAPABILITIES_ALL, can_transfer: false },
      current_bill: { due_date: "2026-07-20", reference_month: "2026-07", status: "paid", total_amount: 150000 },
      description: "Apartamento 101",
      item_count: 3,
      name: "Apartamento 101",
      owner: { name: "Acme Imóveis", type: "organization", uuid: "org-public-uuid" },
      pix_needs_setup: false,
      uuid: "billing-org-paid"
    },
    {
      capabilities: { ...BILLING_CAPABILITIES_ALL, can_transfer: false },
      current_bill: { due_date: "2026-07-20", reference_month: "2026-07", status: "delayed_payment", total_amount: 90000 },
      description: "Sala 2",
      item_count: 1,
      name: "Sala 2",
      owner: { name: "Acme Imóveis", type: "organization", uuid: "org-public-uuid" },
      pix_needs_setup: false,
      uuid: "billing-org-delayed"
    },
    {
      capabilities: { ...BILLING_CAPABILITIES_ALL, can_transfer: false },
      current_bill: null,
      description: "Casa sem fatura",
      item_count: 2,
      name: "Casa sem fatura",
      owner: { name: "Acme Imóveis", type: "organization", uuid: "org-public-uuid" },
      pix_needs_setup: false,
      uuid: "billing-org-empty"
    },
    {
      capabilities: BILLING_CAPABILITIES_ALL,
      current_bill: { due_date: null, reference_month: "2026-07", status: "sent", total_amount: 70000 },
      description: "Pessoal",
      item_count: 1,
      name: "Cobrança pessoal",
      owner: { name: "Usuário", type: "user", uuid: null },
      pix_needs_setup: false,
      uuid: "billing-personal"
    },
    {
      capabilities: BILLING_CAPABILITIES_NONE,
      current_bill: null,
      description: "Outra",
      item_count: 0,
      name: "Outra organização",
      owner: { name: "Beta", type: "organization", uuid: "org-other" },
      pix_needs_setup: false,
      uuid: "billing-other"
    }
  ],
  stats: { ...emptyStats, year: 2031 },
  user_pix_incomplete: false
};

afterEach(() => {
  cleanup();
  analytics.pushAnalyticsFromResponse.mockReset();
  auth.refreshSession.mockReset().mockResolvedValue(undefined);
  vi.unstubAllGlobals();
});

function LocationProbe() {
  const location = useLocation();
  return <output data-testid="location">{`${location.pathname}${location.search}`}</output>;
}

function OrganizationSwitcher() {
  const navigate = useNavigate();
  return <button onClick={() => navigate("/organizations/org-beta")} type="button">Abrir Beta</button>;
}

function installFetch(handlers: Record<string, (init?: RequestInit) => Response | Promise<Response>>) {
  const fetchMock = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const key = `${init?.method ?? "GET"} ${String(input)}`;
    const handler = handlers[key];
    if (!handler) throw new Error(`Unexpected request: ${key}`);
    return handler(init);
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function baseHandlers(overrides: Record<string, (init?: RequestInit) => Response | Promise<Response>> = {}) {
  return {
    "GET /api/v1/billings": () => jsonResponse(billings),
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse(detail),
    ...overrides
  };
}

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/organizations/org-public-uuid"]}>
      <Routes>
        <Route element={<><OrganizationDetailPage /><LocationProbe /></>} path="/organizations/:orgUuid" />
        <Route element={<LocationProbe />} path="/organizations/" />
        <Route element={<LocationProbe />} path="/security/totp/setup" />
      </Routes>
    </MemoryRouter>
  );
}

function renderSwitchablePage() {
  return render(
    <MemoryRouter initialEntries={["/organizations/org-public-uuid"]}>
      <Routes>
        <Route element={<><OrganizationSwitcher /><OrganizationDetailPage /><LocationProbe /></>} path="/organizations/:orgUuid" />
        <Route element={<LocationProbe />} path="/security/totp/setup" />
      </Routes>
    </MemoryRouter>
  );
}

async function openView(user: ReturnType<typeof userEvent.setup>, view: "access" | "billings" | "team") {
  const name = view === "access" ? "Acesso" : view === "billings" ? /^Cobranças/ : /^Equipe/;
  await user.click(await screen.findByRole("tab", { name }));
}

it("presents one compact workspace with deep-linked operation, team and access views", async () => {
  const user = userEvent.setup();
  installFetch(baseHandlers());
  renderPage();

  const workspace = await screen.findByRole("article", { name: "Organização Acme Imóveis" });
  expect(within(workspace).getByRole("heading", { name: "Acme Imóveis" })).toBeVisible();
  expect(within(workspace).getAllByRole("link", { name: "Criar cobrança" })).toHaveLength(1);
  expect(within(workspace).getAllByText("3 cobranças").length).toBeGreaterThan(0);
  expect(within(workspace).getByText("3 pessoas")).toBeVisible();
  expect(within(workspace).getByText("MFA opcional")).toBeVisible();

  const actions = within(workspace).getByRole("button", { name: "Ações da organização" });
  await user.click(actions);
  const editLink = within(workspace).getByRole("link", { name: "Editar organização" });
  const themeLink = within(workspace).getByRole("link", { name: "Tema da organização" });
  expect(editLink).toHaveAttribute("href", "/organizations/org-public-uuid/edit");
  expect(themeLink).toHaveAttribute("href", "/themes/organization/org-public-uuid");
  await user.keyboard("x");
  expect(actions).toHaveAttribute("aria-expanded", "true");
  await user.keyboard("{Escape}");
  expect(actions).toHaveFocus();

  await user.click(actions);
  fireEvent.click(document.getElementById("organization-actions-menu")!);
  expect(actions).toHaveAttribute("aria-expanded", "true");
  editLink.addEventListener("click", (event) => event.preventDefault(), { once: true });
  fireEvent.click(editLink);
  expect(actions).toHaveAttribute("aria-expanded", "false");
  await user.click(actions);
  themeLink.addEventListener("click", (event) => event.preventDefault(), { once: true });
  fireEvent.click(themeLink);
  expect(actions).toHaveAttribute("aria-expanded", "false");
  await user.click(actions);
  fireEvent.click(document.body);
  expect(actions).toHaveAttribute("aria-expanded", "false");

  const teamTab = within(workspace).getByRole("tab", { name: "Equipe 3" });
  await user.click(teamTab);
  expect(teamTab).toHaveAttribute("aria-selected", "true");
  expect(screen.getByTestId("location")).toHaveTextContent("?view=team");
  expect(within(workspace).getByRole("heading", { name: "Pessoas e convites" })).toBeVisible();
  expect(within(workspace).getByRole("heading", { name: "Convidar membro" })).toBeVisible();
  expect(within(workspace).queryByRole("heading", { name: "Cobranças da organização" })).not.toBeInTheDocument();

  const accessTab = within(workspace).getByRole("tab", { name: "Acesso" });
  await user.keyboard("{ArrowRight}");
  expect(accessTab).toHaveAttribute("aria-selected", "true");
  expect(accessTab).toHaveFocus();
  expect(screen.getByTestId("location")).toHaveTextContent("?view=access");
  expect(within(workspace).getByRole("heading", { name: "Segurança da organização" })).toBeVisible();
  expect(within(workspace).getByRole("button", { name: "Excluir organização" })).toBeVisible();

  await user.keyboard("{Home}");
  const billingsTab = within(workspace).getByRole("tab", { name: "Cobranças 3" });
  expect(billingsTab).toHaveFocus();
  expect(billingsTab).toHaveAttribute("aria-selected", "true");
  await user.keyboard("x");
  expect(billingsTab).toHaveAttribute("aria-selected", "true");
  await user.keyboard("{End}");
  expect(accessTab).toHaveFocus();
  await user.keyboard("{ArrowLeft}");
  expect(teamTab).toHaveFocus();
});

it("renders complete organization and billing payloads inside the workspace", async () => {
  const user = userEvent.setup();
  document.title = "Anterior";
  installFetch(baseHandlers());
  const view = renderPage();

  expect(screen.getByText("Carregando organização…")).toBeVisible();
  expect(await screen.findByRole("heading", { name: "Acme Imóveis" })).toHaveClass("pagehead__title");
  expect(screen.getByText("3 pessoas")).toBeVisible();
  expect(screen.getByRole("link", { name: "Tema da organização" })).toHaveAttribute("href", "/themes/organization/org-public-uuid");
  expect(screen.getByRole("link", { name: "Editar organização" })).toHaveAttribute("href", "/organizations/org-public-uuid/edit");
  expect(screen.getAllByRole("link", { name: "Criar cobrança" })).toHaveLength(1);
  expect(screen.getByText("R$ 9.900,00")).toBeVisible();
  expect(screen.getByText("Faturado em 2026")).toBeVisible();
  expect(screen.getByText("8 faturas no ano")).toBeVisible();
  expect(screen.getByText("4 faturas pagas")).toBeVisible();
  expect(screen.getByText("2 aguardando")).toBeVisible();
  expect(screen.getByText("1 vencida")).toBeVisible();
  expect(screen.getByText("Pago")).toHaveClass("tag--paid");
  expect(screen.getByText("Pag. Atrasado")).toHaveClass("tag--delayed");
  expect(screen.getByText("Sem fatura")).toHaveClass("tag--draft");
  const billingPanel = screen.getByRole("heading", { name: "Cobranças da organização" }).closest("[role=tabpanel]");
  expect(billingPanel).not.toBeNull();
  expect(within(billingPanel as HTMLElement).queryByText("Outra organização")).not.toBeInTheDocument();
  expect(within(billingPanel as HTMLElement).queryByRole("link", { name: "Cobrança pessoal" })).not.toBeInTheDocument();
  await openView(user, "team");
  expect(screen.getByText("você")).toHaveClass("you-chip");
  expect(screen.getAllByText("Pendente").find((element) => element.classList.contains("tag--pending"))).toBeVisible();
  expect(screen.getByText("Aceito")).toHaveClass("tag--paid");
  expect(screen.getByText("Recusado")).toHaveClass("tag--overdue");
  expect(screen.getByText("manager@example.com")).toBeVisible();
  expect(screen.getByRole("combobox", { name: "Papel de manager@example.com" })).toHaveValue("manager");
  expect(screen.getByRole("heading", { name: "Membros" }).closest(".organization-team__directory")).not.toBeNull();
  await waitFor(() => expect(document.title).toBe("Acme Imóveis - Rentivo"));
  view.unmount();
  expect(document.title).toBe("Anterior");
});

it("shows a truly empty organization and trusts false capabilities over an admin role", async () => {
  const user = userEvent.setup();
  installFetch(baseHandlers({
    "GET /api/v1/billings": () => jsonResponse({ ...billings, items: [] }),
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse({
      ...detail,
      capabilities: { can_create_billing: false, can_invite: false, can_manage: false, can_view_billing_stats: false },
      current_role: "admin",
      enforce_mfa: true,
      invites: [],
      members: [detail.members[0]],
      settings: null
    })
  }));
  renderPage();

  expect(await screen.findByText("Nenhuma cobrança por aqui")).toBeVisible();
  expect(screen.getByText("1 pessoa")).toBeVisible();
  expect(screen.queryByRole("link", { name: "Criar cobrança" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Editar organização" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Convidar membro" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Excluir organização" })).not.toBeInTheDocument();
  await openView(user, "access");
  expect(screen.getByRole("heading", { name: "Segurança da organização" })).toBeVisible();
  expect(screen.getByText("Obrigatória")).toHaveClass("tag--paid");
  expect(screen.getByText(/Seu acesso é somente leitura/)).toBeVisible();
});

it("renders read-only manager capabilities with MFA off and an empty billing action", async () => {
  const user = userEvent.setup();
  installFetch(baseHandlers({
    "GET /api/v1/billings": () => jsonResponse({ ...billings, items: [] }),
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse({
      ...detail,
      capabilities: { can_create_billing: true, can_invite: false, can_manage: false, can_view_billing_stats: true },
      current_role: "manager",
      enforce_mfa: false,
      invites: [],
      members: detail.members
    })
  }));
  renderPage();
  expect(await screen.findByText("Nenhuma cobrança por aqui")).toBeVisible();
  expect(screen.getAllByRole("link", { name: "Criar cobrança" })).toHaveLength(1);
  expect(screen.getByText("MFA opcional")).toBeVisible();
  await openView(user, "access");
  expect(screen.getByText(/Você pode criar cobranças e gerar faturas/)).toBeVisible();
  await openView(user, "team");
  expect(screen.queryByRole("combobox", { name: "Papel de manager@example.com" })).not.toBeInTheDocument();
  expect(screen.getAllByText("Gerente").every((element) => element.classList.contains("tag--variable"))).toBe(true);
});

it("uses numeric login member IDs for role updates/removal and mutates invite and transfer workflows", async () => {
  const user = userEvent.setup();
  const fetchMock = installFetch(baseHandlers({
    "DELETE /api/v1/organizations/org-public-uuid/members/88": () => new Response(null, { status: 204 }),
    "PATCH /api/v1/organizations/org-public-uuid/members/77": (init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ role: "viewer" });
      return jsonResponse({ ...detail.members[1], role: "viewer", user_id: 77 });
    },
    "POST /api/v1/organizations/org-public-uuid/billing-transfers": (init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ billing_uuid: "billing-personal" });
      return jsonResponse({ billing_uuid: "billing-personal", organization_uuid: "org-public-uuid" }, 200, {
        "X-Rentivo-Analytics-Event": "rentivo_billing_transferred"
      });
    },
    "POST /api/v1/organizations/org-public-uuid/invites": (init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ email: "new@example.com", role: "manager" });
      return jsonResponse({
        created_at: null,
        invited_email: "new@example.com",
        responded_at: null,
        role: "manager",
        status: "pending",
        uuid: "new-invite-public-uuid"
      }, 201, { "X-Rentivo-Analytics-Event": "rentivo_invite_sent" });
    }
  }));
  renderPage();
  await screen.findByText("Acme Imóveis");
  await openView(user, "team");
  const inviteEmail = screen.getByLabelText("E-mail");
  fireEvent.change(inviteEmail, { target: { value: `${"😀".repeat(318)}@a` } });
  expect(inviteEmail).toHaveValue(`${"😀".repeat(318)}@a`);
  fireEvent.change(inviteEmail, { target: { value: "😀".repeat(321) } });
  expect(inviteEmail).toHaveValue("😀".repeat(320));
  fireEvent.change(inviteEmail, { target: { value: "" } });

  await chooseSelectOption(user, screen.getByRole("combobox", { name: "Papel de manager@example.com" }), "Visualizador");
  expect(await screen.findByText("Papel atualizado com sucesso!")).toBeVisible();
  expect(screen.getByRole("combobox", { name: "Papel de manager@example.com" })).toHaveValue("viewer");

  await user.click(screen.getByRole("button", { name: "Remover viewer@example.com" }));
  expect(screen.getByRole("dialog", { name: "Remover membro?" })).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Remover membro" }));
  await waitFor(() => expect(screen.queryByText("viewer@example.com")).not.toBeInTheDocument());
  await waitFor(() => expect(screen.getByRole("button", { name: "Remover manager@example.com" })).toHaveFocus());

  await user.type(inviteEmail, "NEW@EXAMPLE.COM");
  await chooseSelectOption(user, screen.getByLabelText("Papel do convite"), "Gerente");
  await user.click(screen.getByRole("button", { name: "Enviar convite" }));
  expect(await screen.findByText("Convite enviado com sucesso!")).toBeVisible();
  expect(screen.getByText("new@example.com")).toBeVisible();

  await openView(user, "billings");
  await chooseSelectOption(user, screen.getByLabelText("Cobrança para transferir"), "Cobrança pessoal");
  await user.click(screen.getByRole("button", { name: "Transferir cobrança" }));
  await user.click(screen.getByRole("button", { name: "Transferir" }));
  expect(await screen.findByText("Cobrança transferida com sucesso!")).toBeVisible();
  expect(screen.queryByRole("option", { name: "Cobrança pessoal" })).not.toBeInTheDocument();
  expect(fetchMock.mock.calls.some(([input]) => String(input).endsWith("/members/77"))).toBe(true);
  expect(fetchMock.mock.calls.some(([input]) => String(input).endsWith("/members/88"))).toBe(true);
  expect(analytics.pushAnalyticsFromResponse).toHaveBeenCalledTimes(4);
});

it("focuses failed mutation controls and normalizes invite body fields", async () => {
  const user = userEvent.setup();
  let inviteAttempts = 0;
  let roleAttempts = 0;
  installFetch(baseHandlers({
    "PATCH /api/v1/organizations/org-public-uuid/members/77": () => {
      roleAttempts += 1;
      if (roleAttempts === 1) return problemResponse({ code: "membership_conflict", detail: "A associação mudou.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" });
      throw new Error("offline");
    },
    "POST /api/v1/organizations/org-public-uuid/invites": () => {
      inviteAttempts += 1;
      if (inviteAttempts === 1) return problemResponse({ code: "validation_error", detail: "Confira os campos.", fields: { "body.email": "E-mail inválido." }, request_id: "id", status: 422, title: "Dados inválidos", type: "problem" });
      if (inviteAttempts === 2) return problemResponse({ code: "invite_conflict", detail: "Convite duplicado.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" });
      throw new Error("offline");
    }
  }));
  renderPage();
  await openView(user, "team");
  const role = await screen.findByRole("combobox", { name: "Papel de manager@example.com" });

  await chooseSelectOption(user, role, "Visualizador");
  expect(await screen.findByText("A associação mudou.")).toBeVisible();
  expect(role).toHaveFocus();
  await chooseSelectOption(user, role, "Admin");
  expect(await screen.findByText("Não foi possível atualizar o papel.")).toBeVisible();
  expect(role).toHaveFocus();

  await user.type(screen.getByLabelText("E-mail"), "bad@example.com");
  expect(screen.getByLabelText("E-mail")).toHaveValue("bad@example.com");
  await waitFor(() => expect(screen.getByRole("button", { name: "Enviar convite" })).toBeEnabled());
  await user.click(screen.getByRole("button", { name: "Enviar convite" }));
  expect(await screen.findByText("E-mail inválido.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("E-mail")).toHaveFocus());
  await user.click(screen.getByRole("button", { name: "Enviar convite" }));
  expect(await screen.findByText("Convite duplicado.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Enviar convite" }));
  expect(await screen.findByText("Não foi possível enviar o convite.")).toBeVisible();
});

it("updates MFA policy, routes required setup, and deletes with confirmation", async () => {
  const user = userEvent.setup();
  let mfaAttempts = 0;
  installFetch(baseHandlers({
    "DELETE /api/v1/organizations/org-public-uuid": () => new Response(null, { headers: { "X-Rentivo-Analytics-Event": "rentivo_organization_deleted" }, status: 204 }),
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": () => {
      mfaAttempts += 1;
      return jsonResponse({ enforce_mfa: mfaAttempts === 1, mfa_setup_required: mfaAttempts === 1 });
    }
  }));
  const view = renderPage();
  await screen.findByText("Acme Imóveis");

  await openView(user, "access");
  await user.click(screen.getByRole("switch", { name: "Ativar exigência de MFA" }));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/security/totp/setup"));
  expect(auth.refreshSession).toHaveBeenCalledOnce();
  view.unmount();

  cleanup();
  installFetch(baseHandlers({
    "DELETE /api/v1/organizations/org-public-uuid": () => new Response(null, { headers: { "X-Rentivo-Analytics-Event": "rentivo_organization_deleted" }, status: 204 }),
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": () => jsonResponse({ enforce_mfa: true, mfa_setup_required: false })
  }));
  auth.refreshSession.mockRejectedValueOnce(new Error("offline"));
  renderPage();
  await openView(user, "access");
  await user.click(await screen.findByRole("switch", { name: "Ativar exigência de MFA" }));
  expect(await screen.findByText("Política de MFA atualizada.")).toBeVisible();
  expect(auth.refreshSession).toHaveBeenCalledTimes(2);
  expect(screen.getByRole("switch", { name: "Desativar exigência de MFA" })).toHaveAttribute("aria-checked", "true");

  await user.click(screen.getByRole("button", { name: "Excluir organização" }));
  const dialog = screen.getByRole("dialog", { name: "Excluir organização?" });
  expect(within(dialog).getByText(/não pode ser desfeita/i)).toBeVisible();
  await user.click(within(dialog).getByRole("button", { name: "Excluir organização" }));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/organizations/"));
});

it("retries detail loads and surfaces delete, transfer, MFA, and member removal errors", async () => {
  const user = userEvent.setup();
  let detailAttempts = 0;
  installFetch(baseHandlers({
    "DELETE /api/v1/organizations/org-public-uuid": () => problemResponse({ code: "delete", detail: "Exclusão bloqueada.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" }),
    "DELETE /api/v1/organizations/org-public-uuid/members/88": () => problemResponse({ code: "membership_conflict", detail: "Membro já removido.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" }),
    "GET /api/v1/organizations/org-public-uuid": () => {
      detailAttempts += 1;
      if (detailAttempts === 1) throw new Error("offline");
      return jsonResponse(detail);
    },
    "POST /api/v1/organizations/org-public-uuid/billing-transfers": () => { throw new Error("offline"); },
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": () => problemResponse({ code: "mfa", detail: "MFA indisponível.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" })
  }));
  renderPage();

  expect(await screen.findByText("Não foi possível carregar a organização.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
  await screen.findByText("Acme Imóveis");

  await openView(user, "team");
  await user.click(screen.getByRole("button", { name: "Remover viewer@example.com" }));
  await user.click(screen.getByRole("button", { name: "Remover membro" }));
  expect(await screen.findByText("Membro já removido.")).toBeVisible();
  await waitFor(() => expect(screen.getByRole("button", { name: "Remover viewer@example.com" })).toHaveFocus());

  await openView(user, "billings");
  await chooseSelectOption(user, screen.getByLabelText("Cobrança para transferir"), "Cobrança pessoal");
  await user.click(screen.getByRole("button", { name: "Transferir cobrança" }));
  await user.click(screen.getByRole("button", { name: "Transferir" }));
  expect(await screen.findByText("Não foi possível transferir a cobrança.")).toBeVisible();
  expect(screen.getByRole("button", { name: "Transferir cobrança" })).toHaveFocus();

  await openView(user, "access");
  await user.click(screen.getByRole("switch", { name: "Ativar exigência de MFA" }));
  expect(await screen.findByText("MFA indisponível.")).toBeVisible();
  expect(screen.getByRole("switch", { name: "Ativar exigência de MFA" })).toHaveFocus();

  await user.click(screen.getByRole("button", { name: "Excluir organização" }));
  const deleteDialog = screen.getByRole("dialog", { name: "Excluir organização?" });
  await user.click(within(deleteDialog).getByRole("button", { name: "Excluir organização" }));
  expect(await screen.findByText("Exclusão bloqueada.")).toBeVisible();
  expect(screen.getByRole("button", { name: "Excluir organização" })).toHaveFocus();
});

it("clears organization data on route changes and ignores an aborted member response from the previous organization", async () => {
  const user = userEvent.setup();
  const betaLoad = deferred<Response>();
  const roleUpdate = deferred<Response>();
  let roleSignal: AbortSignal | null | undefined;
  const betaDetail: Detail = {
    ...detail,
    invites: [],
    members: [
      detail.members[0],
      { ...detail.members[1], email: "beta@example.com", role: "admin" }
    ],
    name: "Beta Imóveis",
    uuid: "org-beta"
  };
  installFetch({
    "GET /api/v1/billings": () => jsonResponse(billings),
    "GET /api/v1/organizations/org-beta": () => betaLoad.promise,
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse(detail),
    "PATCH /api/v1/organizations/org-public-uuid/members/77": (init) => {
      roleSignal = init?.signal;
      return roleUpdate.promise;
    }
  });
  renderSwitchablePage();
  await openView(user, "team");
  const role = await screen.findByRole("combobox", { name: "Papel de manager@example.com" });

  await chooseSelectOption(user, role, "Visualizador");
  await user.click(screen.getByRole("button", { name: "Abrir Beta" }));

  expect(screen.getByText("Carregando organização…")).toBeVisible();
  expect(screen.queryByText("Acme Imóveis")).not.toBeInTheDocument();
  expect(roleSignal?.aborted).toBe(true);
  await act(async () => { betaLoad.resolve(jsonResponse(betaDetail)); });
  expect(await screen.findByRole("heading", { name: "Beta Imóveis" })).toBeVisible();

  await act(async () => {
    roleUpdate.resolve(jsonResponse({ ...detail.members[1], role: "viewer" }));
  });
  await openView(user, "team");
  expect(screen.getByText("beta@example.com")).toBeVisible();
  expect(screen.queryByText("Papel atualizado com sucesso!")).not.toBeInTheDocument();
  expect(screen.getByTestId("location")).toHaveTextContent("/organizations/org-beta");
});

it("deduplicates and disables member, invite, and MFA mutations while each request is pending", async () => {
  const user = userEvent.setup();
  const roleUpdate = deferred<Response>();
  const inviteCreate = deferred<Response>();
  const mfaUpdate = deferred<Response>();
  const fetchMock = installFetch(baseHandlers({
    "PATCH /api/v1/organizations/org-public-uuid/members/77": () => roleUpdate.promise,
    "POST /api/v1/organizations/org-public-uuid/invites": () => inviteCreate.promise,
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": () => mfaUpdate.promise
  }));
  renderPage();
  await openView(user, "team");
  const role = await screen.findByRole("combobox", { name: "Papel de manager@example.com" });

  await chooseSelectOption(user, role, "Visualizador");
  expect(role).toBeDisabled();
  await user.click(role);
  await waitFor(() => expect(fetchMock.mock.calls.filter(([input]) => String(input).endsWith("/members/77"))).toHaveLength(1));
  await act(async () => { roleUpdate.resolve(jsonResponse({ ...detail.members[1], role: "viewer" })); });

  await user.type(screen.getByLabelText("E-mail"), "new@example.com");
  const inviteForm = screen.getByRole("button", { name: "Enviar convite" }).closest("form") as HTMLFormElement;
  fireEvent.submit(inviteForm);
  fireEvent.submit(inviteForm);
  expect(screen.getByRole("button", { name: "Enviando…" })).toBeDisabled();
  expect(screen.getByLabelText("E-mail")).toBeDisabled();
  await waitFor(() => expect(fetchMock.mock.calls.filter(([input]) => String(input).endsWith("/invites"))).toHaveLength(1));
  await act(async () => {
    inviteCreate.resolve(jsonResponse({
      created_at: null,
      invited_email: "new@example.com",
      responded_at: null,
      role: "viewer",
      status: "pending",
      uuid: "new-invite"
    }, 201));
  });

  await openView(user, "access");
  const mfa = screen.getByRole("switch", { name: "Ativar exigência de MFA" });
  fireEvent.click(mfa);
  fireEvent.click(mfa);
  expect(mfa).toBeDisabled();
  await waitFor(() => expect(fetchMock.mock.calls.filter(([input]) => String(input).endsWith("/mfa-policy"))).toHaveLength(1));
  await act(async () => { mfaUpdate.resolve(jsonResponse({ enforce_mfa: true, mfa_setup_required: false })); });
  expect(await screen.findByText("Política de MFA atualizada.")).toBeVisible();
});

it("does not navigate when an MFA response resolves after the organization route changes", async () => {
  const user = userEvent.setup();
  const mfaUpdate = deferred<Response>();
  installFetch({
    "GET /api/v1/billings": () => jsonResponse(billings),
    "GET /api/v1/organizations/org-beta": () => jsonResponse({ ...detail, name: "Beta Imóveis", uuid: "org-beta" }),
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse(detail),
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": () => mfaUpdate.promise
  });
  renderSwitchablePage();
  await openView(user, "access");
  await user.click(await screen.findByRole("switch", { name: "Ativar exigência de MFA" }));
  await user.click(screen.getByRole("button", { name: "Abrir Beta" }));
  await screen.findByRole("heading", { name: "Beta Imóveis" });

  await act(async () => { mfaUpdate.resolve(jsonResponse({ enforce_mfa: true, mfa_setup_required: true })); });
  expect(screen.getByTestId("location")).toHaveTextContent("/organizations/org-beta");
});

it("focuses the members heading after removing the final manageable member", async () => {
  const user = userEvent.setup();
  installFetch(baseHandlers({
    "DELETE /api/v1/organizations/org-public-uuid/members/88": () => new Response(null, { status: 204 }),
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse({
      ...detail,
      members: [detail.members[0], detail.members[2]]
    })
  }));
  renderPage();
  await openView(user, "team");
  await user.click(await screen.findByRole("button", { name: "Remover viewer@example.com" }));
  await user.click(screen.getByRole("button", { name: "Remover membro" }));

  await waitFor(() => expect(screen.getByRole("heading", { name: "Membros" })).toHaveFocus());
});

it("ignores initial organization loads that settle after the page unmounts", async () => {
  const detailLoad = deferred<Response>();
  let detailSignal: AbortSignal | null | undefined;
  installFetch({
    "GET /api/v1/billings": () => jsonResponse(billings),
    "GET /api/v1/organizations/org-public-uuid": (init) => {
      detailSignal = init?.signal;
      return detailLoad.promise;
    }
  });
  const view = renderPage();

  expect(screen.getByText("Carregando organização…")).toBeVisible();
  await waitFor(() => expect(detailSignal).toBeDefined());
  view.unmount();
  expect(detailSignal?.aborted).toBe(true);
  await act(async () => { detailLoad.resolve(jsonResponse(detail)); });

  const failingLoad = deferred<Response>();
  installFetch({
    "GET /api/v1/billings": () => jsonResponse(billings),
    "GET /api/v1/organizations/org-public-uuid": () => failingLoad.promise
  });
  const second = renderPage();
  second.unmount();
  await act(async () => { failingLoad.reject(new Error("offline")); });

  expect(screen.queryByText("Não foi possível carregar a organização.")).not.toBeInTheDocument();
});

it("does not surface errors when an MFA request fails after the organization route changes", async () => {
  const user = userEvent.setup();
  const mfaUpdate = deferred<Response>();
  installFetch({
    "GET /api/v1/billings": () => jsonResponse(billings),
    "GET /api/v1/organizations/org-beta": () => jsonResponse({ ...detail, name: "Beta Imóveis", uuid: "org-beta" }),
    "GET /api/v1/organizations/org-public-uuid": () => jsonResponse(detail),
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": () => mfaUpdate.promise
  });
  renderSwitchablePage();
  await openView(user, "access");
  await user.click(await screen.findByRole("switch", { name: "Ativar exigência de MFA" }));
  await user.click(screen.getByRole("button", { name: "Abrir Beta" }));
  await screen.findByRole("heading", { name: "Beta Imóveis" });

  await act(async () => { mfaUpdate.reject(new Error("offline")); });

  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  expect(screen.getByTestId("location")).toHaveTextContent("/organizations/org-beta");
});

it("aborts an active organization mutation when the page unmounts", async () => {
  const user = userEvent.setup();
  const mfaUpdate = deferred<Response>();
  let signal: AbortSignal | null | undefined;
  installFetch(baseHandlers({
    "PUT /api/v1/organizations/org-public-uuid/mfa-policy": (init) => {
      signal = init?.signal;
      return mfaUpdate.promise;
    }
  }));
  const view = renderPage();
  await openView(user, "access");
  await user.click(await screen.findByRole("switch", { name: "Ativar exigência de MFA" }));
  await waitFor(() => expect(signal).toBeDefined());

  view.unmount();

  expect(signal?.aborted).toBe(true);
  await act(async () => { mfaUpdate.resolve(jsonResponse({ enforce_mfa: true, mfa_setup_required: false })); });
});
