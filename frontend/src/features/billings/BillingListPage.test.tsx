import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useNavigate } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { BILLING_CAPABILITIES_ALL, BILLING_CAPABILITIES_NONE, jsonResponse } from "../../test/auth";
import { BillingListPage } from "./BillingListPage";

type BillingList = components["schemas"]["BillingListResponse"];

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

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function installFetch(responses: Array<Response | Error>) {
  const fetchMock = vi.fn(() => {
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
function ListRouteSwitcher() {
  const navigate = useNavigate();
  return <button onClick={() => navigate("/elsewhere")} type="button">Sair</button>;
}

it("shows loading and the exact fresh-account empty state with its first action", async () => {
  installFetch([jsonResponse({ items: [], stats: { ...stats, active_count: 0, billed_count: 0, expected: 0, net_income: 0, overdue: 0, overdue_count: 0, paid_count: 0, pending: 0, pending_count: 0, received: 0, total_expenses: 0 }, user_pix_incomplete: false } satisfies BillingList)]);
  document.title = "Anterior";
  const view = renderPage();

  expect(screen.getByText("Carregando cobranças...")).toBeVisible();
  expect(await screen.findByText("Nenhuma cobrança cadastrada.")).toBeVisible();
  expect(screen.getByRole("link", { name: "Criar primeira cobrança" })).toHaveAttribute("href", "/billings/create");
  expect(screen.getByText("0 imóveis cadastrados")).toBeVisible();
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
  expect(screen.getByText("2 imóveis cadastrados")).toBeVisible();
  expect(screen.getByText("Faturado · 2026")).toBeVisible();
  expect(screen.getByText("R$ 9.000,00")).toBeVisible();
  expect(screen.getByText("R$ 3.000,00")).toBeVisible();
  expect(screen.getByText("R$ 5.000,00")).toBeVisible();
  expect(screen.getByText("R$ 1.000,00")).toBeVisible();
  expect(screen.getByText("Você ainda não configurou seus dados de PIX.")).toBeVisible();
  expect(screen.getAllByRole("link", { name: "Apartamento 302" })).toHaveLength(2);
  expect(screen.getAllByRole("link", { name: "Apartamento 302" })[1]).toHaveAttribute("href", "/billings/billing-personal");
  expect(screen.getByText("Org")).toHaveClass("tag--solid");
  expect(screen.getByText("Enviado")).toHaveClass("tag--sent");
  expect(screen.getByText("Sem fatura")).toHaveClass("tag--draft");
  expect(screen.getByText("As cobranças a seguir não podem gerar faturas até que a chave PIX, o nome e a cidade do recebedor sejam preenchidos (na sua conta ou na organização, ou diretamente na cobrança):")).toBeVisible();
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

it("ignores a late successful response after navigating away while it was still loading", async () => {
  const user = userEvent.setup();
  let resolveList: ((response: Response) => void) | undefined;
  const fetchMock = vi.fn(() => new Promise<Response>((resolve) => { resolveList = resolve; }));
  vi.stubGlobal("fetch", fetchMock);
  const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

  render(<MemoryRouter initialEntries={["/billings"]}><Routes>
    <Route element={<><BillingListPage /><ListRouteSwitcher /></>} path="/billings" />
    <Route element={<p>Outra página</p>} path="/elsewhere" />
  </Routes></MemoryRouter>);

  expect(screen.getByText("Carregando cobranças...")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Sair" }));
  expect(screen.getByText("Outra página")).toBeVisible();

  await act(async () => {
    resolveList?.(jsonResponse({ items: [], stats, user_pix_incomplete: false } satisfies BillingList));
  });

  expect(screen.getByText("Outra página")).toBeVisible();
  expect(screen.queryByText("Minhas Cobranças")).not.toBeInTheDocument();
  expect(errorSpy).not.toHaveBeenCalled();
  errorSpy.mockRestore();
});

it("ignores a late failed response after navigating away while it was still loading", async () => {
  const user = userEvent.setup();
  let rejectList: ((reason?: unknown) => void) | undefined;
  const fetchMock = vi.fn(() => new Promise<Response>((_resolve, reject) => { rejectList = reject; }));
  vi.stubGlobal("fetch", fetchMock);
  const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

  render(<MemoryRouter initialEntries={["/billings"]}><Routes>
    <Route element={<><BillingListPage /><ListRouteSwitcher /></>} path="/billings" />
    <Route element={<p>Outra página</p>} path="/elsewhere" />
  </Routes></MemoryRouter>);

  expect(screen.getByText("Carregando cobranças...")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Sair" }));
  expect(screen.getByText("Outra página")).toBeVisible();

  await act(async () => { rejectList?.(new Error("offline")); });

  expect(screen.getByText("Outra página")).toBeVisible();
  expect(screen.queryByText("Não foi possível carregar as cobranças.")).not.toBeInTheDocument();
  expect(errorSpy).not.toHaveBeenCalled();
  errorSpy.mockRestore();
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

  expect(await screen.findByText("3 imóveis cadastrados")).toBeVisible();
  expect(screen.getByText("1 fatura no ano")).toBeVisible();
  expect(screen.getByText("1 fatura paga")).toBeVisible();
  expect(screen.getByText("2 vencidas")).toBeVisible();
  expect(screen.getByText("Pago")).toHaveClass("tag--paid");
  expect(screen.getByText("Pag. Atrasado")).toHaveClass("tag--delayed");
  expect(screen.getByText("Rascunho")).toHaveClass("tag--draft");
  expect(screen.getByText("As cobranças a seguir não podem gerar faturas até que a chave PIX, o nome e a cidade do recebedor sejam preenchidos (no proprietário ou na própria cobrança):")).toBeVisible();
  await waitFor(() => expect(document.title).toBe("Minhas Cobranças - Rentivo"));
});
