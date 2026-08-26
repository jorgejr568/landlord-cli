import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { MemoryRouter } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { BILLING_CAPABILITIES_ALL, BILLING_CAPABILITIES_NONE, jsonResponse, problemResponse } from "../../test/auth";
import { BillingListPage } from "./BillingListPage";
import { PixSetupDialog } from "./PixSetupDialog";

type BillingList = components["schemas"]["BillingListResponse"];
type SecuritySummary = components["schemas"]["SecuritySummaryResponse"];

const stats: components["schemas"]["BillingStatsResponse"] = {
  active_count: 2,
  billed_count: 4,
  expected: 900_000,
  net_income: 250_000,
  overdue: 100_000,
  overdue_count: 1,
  paid_count: 1,
  pending: 500_000,
  pending_count: 2,
  received: 300_000,
  total_expenses: 50_000,
  year: 2026
};

const incompleteSecurity: components["schemas"]["SecuritySummaryResponse"] = {
  mfa: { organization_enforced: false, setup_required: false },
  passkeys: [],
  profile: {
    email: "ana@example.com",
    pix_key: "",
    pix_merchant_city: "",
    pix_merchant_name: "ANA SILVA"
  },
  totp: { enabled: false, recovery_codes_remaining: 0 }
};

const emptyProfile: SecuritySummary["profile"] = {
  email: "ana@example.com",
  pix_key: "",
  pix_merchant_city: "",
  pix_merchant_name: ""
};

const securitySummary = (profile: SecuritySummary["profile"]): SecuritySummary => ({
  mfa: { organization_enforced: false, setup_required: false },
  passkeys: [],
  profile,
  totp: { enabled: false, recovery_codes_remaining: 0 }
});

const emptyBillingList = (userPixIncomplete: boolean): BillingList => ({
  items: [],
  stats: {
    ...stats,
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
    total_expenses: 0
  },
  user_pix_incomplete: userPixIncomplete
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function installFetch(responses: Array<Response | Error | Promise<Response>>) {
  const fetchMock = vi.fn((_input: RequestInfo | URL, _init?: RequestInit): Response | Promise<Response> => {
    void _input;
    void _init;
    const response = responses.shift();
    if (response instanceof Error) throw response;
    if (!response) throw new Error("Unexpected request");
    return response;
  });
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function renderPage() {
  return render(<MemoryRouter><BillingListPage /></MemoryRouter>);
}

function renderDialog(onSaved = vi.fn(async () => undefined), onClose = vi.fn()) {
  return {
    onClose,
    onSaved,
    ...render(<PixSetupDialog onClose={onClose} onSaved={onSaved} open />)
  };
}

it("shows loading and the exact fresh-account empty state with its first action", async () => {
  installFetch([jsonResponse({ items: [], stats: { ...stats, active_count: 0, billed_count: 0, expected: 0, net_income: 0, overdue: 0, overdue_count: 0, paid_count: 0, pending: 0, pending_count: 0, received: 0, total_expenses: 0 }, user_pix_incomplete: false } satisfies BillingList)]);
  document.title = "Anterior";
  const view = renderPage();

  expect(screen.getByText("Carregando cobranças...")).toBeVisible();
  expect(screen.getByRole("status", { name: "Carregando painel de cobranças" })).toBeVisible();
  expect(await screen.findByRole("heading", { name: "Cadastre seu primeiro imóvel" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Cadastrar imóvel" })).toHaveAttribute("href", "/billings/create");
  expect(screen.getByText("Nenhum imóvel em cobrança")).toBeVisible();
  expect(screen.getAllByRole("link", { name: "Cadastrar imóvel" })).toHaveLength(1);
  expect(screen.queryByText(/Faturado/)).not.toBeInTheDocument();
  expect(document.title).toBe("Minhas Cobranças - Rentivo");

  view.unmount();
  expect(document.title).toBe("Anterior");
});

it("retries a failed load and renders stats, PIX warnings, owners and current invoices", async () => {
  const user = userEvent.setup();
  const payload: BillingList = {
    items: [
      {
        capabilities: BILLING_CAPABILITIES_ALL,
        current_bill: { due_date: "2026-07-10", reference_month: "2026-07", status: "sent", total_amount: 285_000 },
        description: "Inquilino atual",
        item_count: 2,
        name: "Apartamento 302",
        owner: { name: null, type: "user", uuid: null },
        pix_needs_setup: true,
        uuid: "billing-personal"
      },
      {
        capabilities: BILLING_CAPABILITIES_NONE,
        current_bill: null,
        description: "",
        item_count: 1,
        name: "Sala Comercial",
        owner: { name: "Ribeiro Imóveis", type: "organization", uuid: "org-public" },
        pix_needs_setup: false,
        uuid: "billing-org"
      }
    ],
    stats,
    user_pix_incomplete: true
  };
  const fetchMock = installFetch([new Error("offline"), jsonResponse(payload)]);
  renderPage();

  expect(await screen.findByText("Não foi possível carregar as cobranças.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

  expect(await screen.findByRole("heading", { name: "Minhas Cobranças" })).toHaveClass("pagehead__title");
  expect(screen.getByText("2 imóveis em cobrança")).toBeVisible();
  expect(screen.getByRole("region", { name: "Resumo financeiro de 2026" })).toBeVisible();
  expect(screen.getByText("Faturado em 2026")).toBeVisible();
  expect(screen.getByText("R$ 9.000,00")).toBeVisible();
  expect(screen.getByText("R$ 3.000,00")).toBeVisible();
  expect(screen.getByText("R$ 5.000,00")).toBeVisible();
  expect(screen.getByText("R$ 1.000,00")).toBeVisible();
  expect(screen.getByRole("region", { name: "Pendências de configuração" })).toBeVisible();
  expect(screen.getByText("PIX da conta pendente")).toBeVisible();
  expect(screen.getByRole("button", { name: "Configurar PIX" })).toBeVisible();
  expect(screen.getAllByRole("link", { name: "Apartamento 302" })).toHaveLength(2);
  expect(screen.getAllByRole("link", { name: "Apartamento 302" })[1]).toHaveAttribute("href", "/billings/billing-personal");
  expect(screen.getByText("Org")).toHaveClass("tag--solid");
  expect(screen.getByText("Enviado")).toHaveClass("tag--sent");
  expect(screen.getByText("Sem fatura")).toHaveClass("tag--draft");
  const sentBillingRow = screen.getByRole("row", { name: /Apartamento 302/ });
  expect(within(sentBillingRow).getByText("Julho/2026")).toBeVisible();
  expect(within(sentBillingRow).getByText("Vence em 10/07/2026")).toBeVisible();
  expect(within(sentBillingRow).getByRole("link", { name: "Ver cobrança Apartamento 302" })).toHaveAttribute("href", "/billings/billing-personal");
  const billingWithoutInvoice = screen.getByRole("row", { name: /Sala Comercial/ });
  expect(within(billingWithoutInvoice).getByText("Ainda não emitida")).toBeVisible();
  expect(screen.getByText("1 cobrança sem dados de recebimento")).toBeVisible();
  expect(screen.getByRole("table", { name: "Imóveis e faturas atuais" })).toBeVisible();
  expect(screen.getByRole("columnheader", { name: "Ação" })).toBeVisible();
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it("opens a focused PIX setup dialog and validates its required fields locally", async () => {
  const user = userEvent.setup();
  const fetchMock = installFetch([
    jsonResponse(emptyBillingList(true)),
    jsonResponse(incompleteSecurity)
  ]);
  renderPage();

  await user.click(await screen.findByRole("button", { name: "Configurar PIX" }));

  const dialog = await screen.findByRole("dialog", { name: "Receber por PIX" });
  expect(within(dialog).getByText("Só precisamos destes 3 dados para colocar o PIX nas suas faturas pessoais.")).toBeVisible();
  expect(within(dialog).getByText("Digite o nome completo. Usaremos os primeiros 25 caracteres; o corte não afeta o pagamento.")).toBeVisible();
  expect(within(dialog).getByText("Digite normalmente, com acentos. No PIX, “São Paulo” vira “SAO PAULO”.")).toBeVisible();
  expect(within(dialog).getByLabelText("Nome do recebedor")).toHaveValue("ANA SILVA");
  expect(within(dialog).getByLabelText("Chave PIX")).toHaveFocus();

  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));

  expect(within(dialog).getByText("Informe a chave PIX.")).toBeVisible();
  expect(within(dialog).getByText("Informe a cidade do recebedor.")).toBeVisible();
  expect(within(dialog).getByLabelText("Chave PIX")).toHaveFocus();
  expect(fetchMock.mock.calls.some(([url, init]) =>
    url === "/api/v1/security/pix" && init?.method === "POST"
  )).toBe(false);
});

it("saves PIX from the dialog and removes the completed warning", async () => {
  const user = userEvent.setup();
  const completedProfile = {
    ...incompleteSecurity.profile,
    pix_key: "ana@example.com",
    pix_merchant_city: "SAO PAULO"
  };
  const fetchMock = installFetch([
    jsonResponse(emptyBillingList(true)),
    jsonResponse(incompleteSecurity),
    jsonResponse({ profile: completedProfile }),
    jsonResponse(emptyBillingList(false))
  ]);
  renderPage();

  await user.click(await screen.findByRole("button", { name: "Configurar PIX" }));
  const dialog = await screen.findByRole("dialog", { name: "Receber por PIX" });
  await user.type(within(dialog).getByLabelText("Chave PIX"), "ana@example.com");
  await user.type(within(dialog).getByLabelText("Cidade do recebedor"), "SAO PAULO");
  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));

  expect(await screen.findByRole("status")).toHaveTextContent("PIX configurado. Suas próximas faturas pessoais já podem usar estes dados.");
  await waitFor(() => expect(screen.queryByRole("dialog", { name: "Receber por PIX" })).not.toBeInTheDocument());
  expect(screen.queryByText("PIX da conta pendente")).not.toBeInTheDocument();
  const updateCall = fetchMock.mock.calls.find(([url, init]) =>
    url === "/api/v1/security/pix" && init?.method === "POST"
  );
  expect(JSON.parse(String(updateCall?.[1]?.body))).toEqual({
    pix_key: "ana@example.com",
    pix_merchant_city: "SAO PAULO",
    pix_merchant_name: "ANA SILVA"
  });
});

it("ignores billing list load settlements after the page unmounts", async () => {
  let resolveLoad: ((response: Response) => void) | undefined;
  vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>((resolve) => { resolveLoad = resolve; })));
  const view = renderPage();
  expect(screen.getByText("Carregando cobranças...")).toBeVisible();
  await waitFor(() => expect(resolveLoad).toBeDefined());
  view.unmount();
  await act(async () => { resolveLoad?.(jsonResponse({ items: [], stats, user_pix_incomplete: false } satisfies BillingList)); });
  expect(screen.queryByText("Nenhuma cobrança cadastrada.")).not.toBeInTheDocument();

  let rejectLoad: ((reason?: unknown) => void) | undefined;
  vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>((_resolve, reject) => { rejectLoad = reject; })));
  const second = renderPage();
  expect(screen.getByText("Carregando cobranças...")).toBeVisible();
  await waitFor(() => expect(rejectLoad).toBeDefined());
  second.unmount();
  await act(async () => { rejectLoad?.(new Error("late failure")); });
  expect(screen.queryByText("Não foi possível carregar as cobranças.")).not.toBeInTheDocument();
});

it("uses the owner-only PIX warning copy and singular billing count", async () => {
  const payload: BillingList = {
    items: [{
      capabilities: BILLING_CAPABILITIES_NONE,
      current_bill: { due_date: null, reference_month: "2026-06", status: "paid", total_amount: 100 },
      description: "",
      item_count: 1,
      name: "Casa",
      owner: { name: null, type: "user", uuid: null },
      pix_needs_setup: true,
      uuid: "billing-one"
    }, {
      capabilities: BILLING_CAPABILITIES_NONE,
      current_bill: { due_date: null, reference_month: "2026-05", status: "delayed_payment", total_amount: 200 },
      description: "", item_count: 1, name: "Sala", owner: { name: null, type: "user", uuid: null },
      pix_needs_setup: false, uuid: "billing-delayed"
    }, {
      capabilities: BILLING_CAPABILITIES_NONE,
      current_bill: { due_date: null, reference_month: "2026-04", status: "draft", total_amount: 300 },
      description: "", item_count: 1, name: "Loja", owner: { name: null, type: "user", uuid: null },
      pix_needs_setup: false, uuid: "billing-draft"
    }],
    stats: { ...stats, billed_count: 1, overdue_count: 2, paid_count: 1 },
    user_pix_incomplete: false
  };
  installFetch([jsonResponse(payload)]);
  renderPage();

  expect(await screen.findByText("3 imóveis em cobrança")).toBeVisible();
  expect(screen.getByText("1 fatura no ano")).toBeVisible();
  expect(screen.getByText("1 fatura paga")).toBeVisible();
  expect(screen.getByText("2 vencidas")).toBeVisible();
  expect(screen.getByText("Pago")).toHaveClass("tag--paid");
  expect(screen.getByText("Pag. Atrasado")).toHaveClass("tag--delayed");
  expect(screen.getByText("Rascunho")).toHaveClass("tag--draft");
  expect(screen.getByText("1 cobrança sem dados de recebimento")).toBeVisible();
  await waitFor(() => expect(document.title).toBe("Minhas Cobranças - Rentivo"));
});

it("recovers from PIX load failures and focuses each incomplete field", async () => {
  const user = userEvent.setup();
  installFetch([
    new Error("offline"),
    problemResponse({ code: "load", detail: "Sessão expirada.", fields: {}, request_id: "id", status: 403, title: "Negado", type: "problem" }),
    jsonResponse(securitySummary(emptyProfile)),
    new Error("offline"),
    problemResponse({ code: "save", detail: "Chave já cadastrada.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" }),
    jsonResponse({ profile: { ...emptyProfile, pix_key: "ana@example.com", pix_merchant_city: "SAO PAULO", pix_merchant_name: "ANA SILVA" } })
  ]);
  const { onClose, onSaved } = renderDialog();

  expect(await screen.findByRole("alert")).toHaveTextContent("Não foi possível carregar seus dados PIX.");
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
  expect(await screen.findByRole("alert")).toHaveTextContent("Sessão expirada.");
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

  const dialog = await screen.findByRole("dialog", { name: "Receber por PIX" });
  const key = within(dialog).getByLabelText("Chave PIX");
  const name = within(dialog).getByLabelText("Nome do recebedor");
  const city = within(dialog).getByLabelText("Cidade do recebedor");
  expect(key).toHaveFocus();

  await user.type(key, "ana@example.com");
  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));
  expect(name).toHaveFocus();
  expect(within(dialog).getByText("Informe o nome do recebedor.")).toBeVisible();

  await user.type(name, "José Carlos de Albuquerque Neto");
  expect(name).toHaveValue("José Carlos de Albuquerqu");
  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));
  expect(city).toHaveFocus();

  await user.type(city, "São Paulo do Sul");
  expect(city).toHaveValue("São Paulo do Su");
  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));
  expect(await within(dialog).findByRole("alert")).toHaveTextContent("Não foi possível salvar os dados PIX.");
  expect(key).toHaveFocus();

  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));
  expect(await within(dialog).findByRole("alert")).toHaveTextContent("Chave já cadastrada.");
  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));

  await waitFor(() => expect(onSaved).toHaveBeenCalledOnce());
  expect(onClose).toHaveBeenCalledOnce();
});

it("traps PIX dialog focus and supports each non-saving dismissal", async () => {
  const user = userEvent.setup();
  installFetch([
    jsonResponse(securitySummary({ ...emptyProfile, pix_key: "ana@example.com", pix_merchant_city: "SAO PAULO", pix_merchant_name: "ANA SILVA" })),
    jsonResponse(securitySummary(emptyProfile)),
    jsonResponse(securitySummary(emptyProfile))
  ]);

  function Harness() {
    const [open, setOpen] = useState(false);
    return <><button onClick={() => setOpen(true)} type="button">Abrir PIX</button><PixSetupDialog onClose={() => setOpen(false)} onSaved={async () => undefined} open={open} /></>;
  }

  render(<Harness />);
  await user.click(screen.getByRole("button", { name: "Abrir PIX" }));
  const dialog = await screen.findByRole("dialog", { name: "Receber por PIX" });
  const close = within(dialog).getByRole("button", { name: "Fechar" });
  const save = within(dialog).getByRole("button", { name: "Salvar PIX" });
  await waitFor(() => expect(within(dialog).getByLabelText("Chave PIX")).toHaveFocus());

  close.focus();
  await user.tab({ shift: true });
  expect(save).toHaveFocus();
  await user.tab();
  expect(close).toHaveFocus();
  within(dialog).getByLabelText("Chave PIX").focus();
  await user.tab();
  expect(within(dialog).getByLabelText("Nome do recebedor")).toHaveFocus();
  await user.keyboard("{Escape}");
  expect(screen.queryByRole("dialog", { name: "Receber por PIX" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Abrir PIX" })).toHaveFocus();

  await user.click(screen.getByRole("button", { name: "Abrir PIX" }));
  const overlay = (await screen.findByRole("dialog", { name: "Receber por PIX" })).parentElement;
  expect(overlay).not.toBeNull();
  fireEvent.mouseDown(overlay!);
  expect(screen.queryByRole("dialog", { name: "Receber por PIX" })).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Abrir PIX" }));
  await user.click(await screen.findByRole("button", { name: "Agora não" }));
  expect(screen.queryByRole("dialog", { name: "Receber por PIX" })).not.toBeInTheDocument();
});

it("focuses the first missing prefilled PIX profile value", async () => {
  installFetch([
    jsonResponse(securitySummary({ ...emptyProfile, pix_key: "ana@example.com", pix_merchant_name: "", pix_merchant_city: "" })),
    jsonResponse(securitySummary({ ...emptyProfile, pix_key: "ana@example.com", pix_merchant_name: "ANA SILVA", pix_merchant_city: "" }))
  ]);
  const first = renderDialog();
  await waitFor(() => expect(screen.getByLabelText("Nome do recebedor")).toHaveFocus());
  first.unmount();

  renderDialog();
  await waitFor(() => expect(screen.getByLabelText("Cidade do recebedor")).toHaveFocus());
});

it("cannot dismiss the PIX dialog while its save is pending", async () => {
  const user = userEvent.setup();
  let resolveSave: ((response: Response) => void) | undefined;
  const pendingSave = new Promise<Response>((resolve) => { resolveSave = resolve; });
  installFetch([
    jsonResponse(securitySummary({ ...emptyProfile, pix_key: "ana@example.com", pix_merchant_city: "SAO PAULO", pix_merchant_name: "ANA SILVA" })),
    pendingSave
  ]);
  const { onClose } = renderDialog();
  const dialog = await screen.findByRole("dialog", { name: "Receber por PIX" });

  await user.click(within(dialog).getByRole("button", { name: "Salvar PIX" }));
  expect(within(dialog).getByRole("button", { name: "Salvando..." })).toBeDisabled();
  fireEvent.mouseDown(dialog.parentElement!);
  await user.keyboard("{Escape}");
  expect(onClose).not.toHaveBeenCalled();

  await act(async () => resolveSave?.(jsonResponse({ profile: emptyProfile })));
  await waitFor(() => expect(onClose).toHaveBeenCalledOnce());
});

it("ignores PIX load settlements after the dialog closes", async () => {
  let resolveLoad: ((response: Response) => void) | undefined;
  let rejectLoad: ((reason?: unknown) => void) | undefined;
  const pendingLoad = new Promise<Response>((resolve) => { resolveLoad = resolve; });
  const pendingFailure = new Promise<Response>((_resolve, reject) => { rejectLoad = reject; });
  installFetch([pendingLoad, pendingFailure]);
  const props = { onClose: vi.fn(), onSaved: vi.fn(async () => undefined) };
  const view = render(<PixSetupDialog {...props} open />);
  expect(screen.getByRole("status", { name: "Carregando dados PIX" })).toBeVisible();
  view.rerender(<PixSetupDialog {...props} open={false} />);
  await act(async () => resolveLoad?.(jsonResponse(securitySummary(emptyProfile))));

  view.rerender(<PixSetupDialog {...props} open />);
  await waitFor(() => expect(screen.getByRole("status", { name: "Carregando dados PIX" })).toBeVisible());
  view.rerender(<PixSetupDialog {...props} open={false} />);
  await act(async () => rejectLoad?.(new Error("late failure")));
  expect(screen.queryByRole("alert")).not.toBeInTheDocument();
});
