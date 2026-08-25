import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { BILLING_CAPABILITIES_ALL, jsonResponse, problemResponse } from "../../test/auth";
import { BillGeneratePage } from "./BillGeneratePage";

const analytics = vi.hoisted(() => ({ pushAnalyticsFromResponse: vi.fn() }));
vi.mock("../auth/analytics", () => analytics);

type Billing = components["schemas"]["BillingResponse"];
const FIXED_ITEM_UUID = "01J00000000000000000000010";
const VARIABLE_ITEM_UUID = "01J00000000000000000000011";

const billing: Billing = {
  capabilities: { ...BILLING_CAPABILITIES_ALL, can_transfer: false },
  communication_templates: [],
  created_at: "2026-07-18T10:00:00Z",
  description: "Apartamento 302",
  items: [
    { amount: 250000, description: "Aluguel", item_type: "fixed", uuid: FIXED_ITEM_UUID },
    { amount: 0, description: "Água", item_type: "variable", uuid: VARIABLE_ITEM_UUID }
  ],
  name: "Residencial Sol",
  owner: { type: "user", uuid: null },
  pix_key: "financeiro@example.com",
  pix_merchant_city: "SALVADOR",
  pix_merchant_name: "RESIDENCIAL SOL",
  pix_needs_setup: false,
  recipients: [],
  reply_to: [],
  stats: {
    active_count: 0, billed_count: 0, expected: 0, net_income: 0, overdue: 0,
    overdue_count: 0, paid_count: 0, pending: 0, pending_count: 0, received: 0,
    total_expenses: 0, year: 2026
  },
  updated_at: "2026-07-18T10:00:00Z",
  uuid: "billing-public-uuid"
};

afterEach(() => {
  cleanup();
  analytics.pushAnalyticsFromResponse.mockReset();
  vi.unstubAllGlobals();
});

function LocationProbe() {
  return <output data-testid="location">{useLocation().pathname}</output>;
}

function RouteSwitch() {
  const navigate = useNavigate();
  return <button onClick={() => navigate("/billings/billing-second/bills/generate")} type="button">Trocar cobrança</button>;
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

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/billings/billing-public-uuid/bills/generate"]}>
      <Routes>
        <Route element={<><BillGeneratePage /><LocationProbe /><RouteSwitch /></>} path="/billings/:billingUuid/bills/generate" />
        <Route element={<LocationProbe />} path="/billings/:billingUuid/bills/:billUuid" />
      </Routes>
    </MemoryRouter>
  );
}

async function moveToItems(user: ReturnType<typeof userEvent.setup>, referenceMonth = "2026-07", dueDate = "") {
  await screen.findByRole("heading", { name: "Competência" });
  if (!screen.getByLabelText("Mês de Referência").getAttribute("value")) {
    await user.type(screen.getByLabelText("Mês de Referência"), referenceMonth);
  }
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  if (dueDate) fireEvent.change(screen.getByLabelText("Vencimento"), { target: { value: dueDate } });
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  await screen.findByRole("heading", { name: "Itens" });
}

async function moveFromItemsToReview(user: ReturnType<typeof userEvent.setup>, notes = "") {
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  await screen.findByRole("heading", { name: "Observações e comprovantes" });
  if (notes) await user.type(screen.getByLabelText("Observações"), notes);
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  await screen.findByRole("heading", { name: "Revisar fatura" });
}

it("guides invoice generation through validated desktop steps and a review", async () => {
  const user = userEvent.setup();
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing)
  });
  renderPage();

  expect(await screen.findByRole("heading", { name: "Competência" })).toBeVisible();
  expect(screen.queryByLabelText("Vencimento")).not.toBeInTheDocument();
  expect(screen.getByText("Etapa 1 de 5")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(await screen.findByText("Informe o mês de referência.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Mês de Referência")).toHaveFocus());

  await user.type(screen.getByLabelText("Mês de Referência"), "2026-07");
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(screen.getByRole("heading", { name: "Vencimento" })).toHaveFocus();
  fireEvent.change(screen.getByLabelText("Vencimento"), { target: { value: "2026-08-10" } });
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(screen.getByRole("heading", { name: "Itens" })).toHaveFocus();
  await user.type(screen.getByLabelText("Água"), "123,45");
  expect(screen.getByRole("complementary", { name: "Resumo da fatura" })).toHaveTextContent("R$ 2.623,45");
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(screen.getByRole("heading", { name: "Observações e comprovantes" })).toHaveFocus();
  await user.type(screen.getByLabelText("Observações"), "Pagar até o vencimento");
  await user.click(screen.getByRole("button", { name: "Continuar" }));

  expect(screen.getByRole("heading", { name: "Revisar fatura" })).toHaveFocus();
  expect(screen.getAllByText("Julho/2026").length).toBeGreaterThanOrEqual(1);
  expect(screen.getByText("Pagar até o vencimento")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Editar Itens e valores" }));
  expect(screen.getByRole("heading", { name: "Itens" })).toHaveFocus();
});

it("generates a typed invoice with variable values, extras, dates, notes, and receipt files", async () => {
  const user = userEvent.setup();
  const receipt = new File(["receipt"], "comprovante.pdf", { type: "application/pdf" });
  let submitted: FormData | undefined;
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing),
    "POST /api/v1/billings/billing-public-uuid/bills": (init) => {
      submitted = init?.body as FormData;
      return jsonResponse({
        available_transitions: [], capabilities: {
          can_compose: true,
          can_delete: true, can_delete_receipts: true, can_download_invoice: true,
          can_download_recibo: false, can_open_recibo: false, can_edit: true, can_regenerate: true,
          can_reorder_receipts: true, can_send_invoice: true, can_send_recibo: false,
          can_transition: true, can_upload_receipts: true
        }, communications: [], created_at: "2026-07-18T10:00:00Z", due_date: "2026-08-10",
        has_invoice: true, has_recibo: false, line_items: [], notes: "Pagar até o vencimento",
        pdf_render_status: "pending", receipt_upload: { attached: 1, skipped: 0, total_bytes: 7 },
        receipts: [], reference_month: "2026-07", status: "draft", status_updated_at: null,
        total_amount: 263456, uuid: "bill-public-uuid"
      }, 201, { "X-Rentivo-Analytics-Event": "rentivo_bill_generated" });
    }
  });
  document.title = "Anterior";
  const view = renderPage();

  expect(screen.getByText("Carregando cobrança...")).toBeVisible();
  expect(await screen.findByRole("heading", { name: "Gerar Fatura" })).toHaveClass("mb-1");
  await moveToItems(user, "2026-07", "2026-08-10");
  expect(screen.getByDisplayValue("2.500,00")).toBeDisabled();
  await user.type(screen.getByLabelText("Água"), "123,45");
  await user.click(screen.getByRole("button", { name: "Adicionar despesa extra" }));
  await user.type(screen.getByPlaceholderText("Descrição"), "Gás");
  await user.type(screen.getByLabelText("Valor da despesa extra 1"), "12,11");
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  await user.type(screen.getByLabelText("Observações"), "Pagar até o vencimento");
  await user.upload(screen.getByLabelText("Anexar comprovantes"), receipt);
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));

  await waitFor(() => expect(submitted).toBeInstanceOf(FormData));
  expect(JSON.parse(String(submitted?.get("payload")))).toEqual({
    due_date: "2026-08-10",
    extras: [{ amount: 1211, description: "Gás" }],
    notes: "Pagar até o vencimento",
    reference_month: "2026-07",
    variable_amounts: { [VARIABLE_ITEM_UUID]: 12345 }
  });
  expect(submitted?.getAll("receipt_files")).toEqual([receipt]);
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/billing-public-uuid/bills/bill-public-uuid"));
  expect(analytics.pushAnalyticsFromResponse).toHaveBeenCalledOnce();
  view.unmount();
  expect(document.title).toBe("Anterior");
});

it("normalizes body field errors, focuses the invalid input, and retries a failed load", async () => {
  const user = userEvent.setup();
  let loads = 0;
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => {
      loads += 1;
      return loads === 1 ? problemResponse({
        code: "offline", detail: "Sem conexão.", fields: {}, request_id: "req", status: 503,
        title: "Indisponível", type: "problem"
      }) : jsonResponse(billing);
    },
    "POST /api/v1/billings/billing-public-uuid/bills": () => problemResponse({
      code: "validation_error", detail: "Confira os campos.",
      fields: { "body.reference_month": "Mês inválido.", [`body.variable_amounts.${VARIABLE_ITEM_UUID}`]: "Informe o valor." },
      request_id: "req", status: 422, title: "Dados inválidos", type: "problem"
    })
  });
  renderPage();

  expect(await screen.findByText("Sem conexão.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "0");
  await moveFromItemsToReview(user);
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));
  expect(await screen.findByText("Mês inválido.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Mês de Referência")).toHaveFocus());
  await user.click(screen.getByRole("button", { name: /Itens/ }));
  expect(screen.getByText("Informe o valor.")).toBeVisible();
});

it("renders backend-denied and fresh-template nested states", async () => {
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse({ ...billing, items: [] })
  });
  const emptyView = renderPage();
  expect(await screen.findByRole("heading", { name: "Nenhum item cadastrado" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Cadastrar itens" })).toHaveAttribute("href", "/billings/billing-public-uuid/edit");
  emptyView.unmount();

  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse({
      ...billing,
      capabilities: { ...billing.capabilities, can_manage_bills: false }
    })
  });
  renderPage();
  expect(await screen.findByRole("heading", { name: "Geração indisponível" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Gerar Fatura" })).not.toBeInTheDocument();
  cleanup();

  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse({ ...billing, pix_needs_setup: true })
  });
  renderPage();
  expect(await screen.findByRole("heading", { name: "PIX necessário" })).toBeVisible();
  expect(screen.getByRole("link", { name: "Configurar PIX" })).toHaveAttribute("href", "/billings/billing-public-uuid/edit");
});

it("keeps bill generation available but omits receipt files without files:write", async () => {
  const user = userEvent.setup();
  let submitted: FormData | undefined;
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse({
      ...billing,
      capabilities: { ...billing.capabilities, can_upload_bill_receipts: false }
    }),
    "POST /api/v1/billings/billing-public-uuid/bills": (init) => {
      submitted = init?.body as FormData;
      return jsonResponse({ uuid: "bill-without-receipt" }, 201);
    }
  });
  renderPage();

  expect(await screen.findByRole("heading", { name: "Gerar Fatura" })).toBeVisible();
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "10,00");
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(screen.queryByLabelText("Anexar comprovantes")).not.toBeInTheDocument();
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));

  await waitFor(() => expect(submitted).toBeInstanceOf(FormData));
  expect(submitted?.has("receipt_files")).toBe(false);
  // Navigation happens once the create response resolves, after the request is observable.
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/billing-public-uuid/bills/bill-without-receipt"));
});

it("rejects invalid receipt files before generating a bill", async () => {
  const user = userEvent.setup();
  const fetchMock = installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing)
  });
  renderPage();

  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "10,00");
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  const input = screen.getByLabelText("Anexar comprovantes");
  fireEvent.change(input, { target: { files: [new File(["text"], "notes.txt", { type: "text/plain" })] } });
  await user.click(screen.getByRole("button", { name: "Continuar" }));

  expect(await screen.findByText("O arquivo notes.txt deve ser PDF, JPEG ou PNG.")).toBeVisible();
  await waitFor(() => expect(input).toHaveFocus());
  expect(fetchMock.mock.calls.filter(([, init]) => init?.method === "POST")).toHaveLength(0);
});

it("validates extras locally, removes rows, and focuses nested API errors", async () => {
  const user = userEvent.setup();
  let attempts = 0;
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing),
    "POST /api/v1/billings/billing-public-uuid/bills": () => {
      attempts += 1;
      if (attempts === 1) return problemResponse({
        code: "validation_error", detail: "Confira os extras.", fields: { "body.extras.0.description": "Descrição já utilizada." },
        request_id: "req", status: 422, title: "Dados inválidos", type: "problem"
      });
      throw new Error("offline");
    }
  });
  renderPage();
  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "10,00");
  await user.click(screen.getByRole("button", { name: "Adicionar despesa extra" }));
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(await screen.findByText("Informe a descrição.")).toBeVisible();
  expect(screen.getByText("Informe um valor maior que zero.")).toBeVisible();
  const extraDescription = screen.getByLabelText("Descrição da despesa extra 1");
  await waitFor(() => expect(extraDescription).toHaveFocus());

  fireEvent.change(extraDescription, { target: { value: "😀".repeat(256) } });
  expect(extraDescription).toHaveValue("😀".repeat(255));
  fireEvent.change(screen.getByLabelText("Valor da despesa extra 1"), { target: { value: "10,00" } });

  await user.click(screen.getByRole("button", { name: "Adicionar despesa extra" }));
  await user.clear(screen.getByLabelText("Descrição da despesa extra 1"));
  await user.clear(screen.getByLabelText("Valor da despesa extra 1"));
  await user.type(screen.getByLabelText("Descrição da despesa extra 1"), "Seguro");
  await user.type(screen.getByLabelText("Valor da despesa extra 1"), "10,00");
  await user.type(screen.getByLabelText("Descrição da despesa extra 2"), "Limpeza");
  await user.type(screen.getByLabelText("Valor da despesa extra 2"), "20,00");
  await moveFromItemsToReview(user);
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));
  expect(await screen.findByText("Descrição já utilizada.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Descrição da despesa extra 1")).toHaveFocus());

  await user.click(screen.getByRole("button", { name: "Remover despesa extra 1" }));
  await user.click(screen.getByRole("button", { name: "Remover despesa extra 1" }));
  expect(screen.getByText("Nenhuma despesa extra.")).toBeVisible();
  await moveFromItemsToReview(user);
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));
  expect(await screen.findByText("Não foi possível gerar a fatura.")).toBeVisible();
});

it("rejects an unparsable variable amount and tolerates an unknown backend UUID field key", async () => {
  const user = userEvent.setup();
  let attempts = 0;
  let payload: Record<string, unknown> | undefined;
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
    callback(0);
    return 1;
  });
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing),
    "POST /api/v1/billings/billing-public-uuid/bills": (init) => {
      attempts += 1;
      payload = JSON.parse(String((init?.body as FormData).get("payload")));
      return problemResponse({
        code: "validation_error", detail: "Valor desconhecido.",
        fields: attempts === 1
          ? { [`body.variable_amounts.${VARIABLE_ITEM_UUID}`]: "Informe o valor novamente." }
          : { "body.variable_amounts.01J99999999999999999999999": "Item não encontrado." },
        request_id: "req", status: 422, title: "Dados inválidos", type: "problem"
      });
    }
  });
  renderPage();
  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "invalido");
  await user.click(screen.getByRole("button", { name: "Continuar" }));
  expect(await screen.findByText("Informe um valor válido.")).toBeVisible();
  expect(screen.getByLabelText("Água")).toHaveFocus();
  expect(attempts).toBe(0);
  await user.clear(screen.getByLabelText("Água"));
  await user.type(screen.getByLabelText("Água"), "10,00");
  await moveFromItemsToReview(user);
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));
  expect(await screen.findByText("Valor desconhecido.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Água")).toHaveFocus());
  await moveFromItemsToReview(user);
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));
  await waitFor(() => expect(attempts).toBe(2));
  expect(payload).toEqual(expect.objectContaining({ variable_amounts: { [VARIABLE_ITEM_UUID]: 1000 } }));
});

it("rejects a generated bill total beyond the persistence limit", async () => {
  const user = userEvent.setup();
  const fetchMock = installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing)
  });
  renderPage();
  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "21.474.836,47");
  await user.click(screen.getByRole("button", { name: "Continuar" }));

  expect(await screen.findByText("O valor total deve ser de no máximo R$ 21.474.836,47.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Água")).toHaveFocus());
  expect(fetchMock.mock.calls.filter(([, init]) => init?.method === "POST")).toHaveLength(0);
});

it("focuses the first extra when an extras-only total exceeds the persistence limit", async () => {
  const user = userEvent.setup();
  const fetchMock = installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse({
      ...billing,
      items: [{ amount: 250000, description: "Aluguel", item_type: "fixed", uuid: FIXED_ITEM_UUID }]
    })
  });
  renderPage();
  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.click(screen.getByRole("button", { name: "Adicionar despesa extra" }));
  await user.type(screen.getByLabelText("Descrição da despesa extra 1"), "Reforma");
  await user.type(screen.getByLabelText("Valor da despesa extra 1"), "21.474.836,47");
  await user.click(screen.getByRole("button", { name: "Continuar" }));

  expect(await screen.findByText("O valor total deve ser de no máximo R$ 21.474.836,47.")).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Valor da despesa extra 1")).toHaveFocus());
  expect(fetchMock.mock.calls.filter(([, init]) => init?.method === "POST")).toHaveLength(0);
});

it.each(["resolve", "reject"] as const)("resets every resource when a stale generation mutation %s after the billing route changes", async (outcome) => {
  const user = userEvent.setup();
  let generationPosts = 0;
  let settleGeneration!: () => void;
  const pendingGeneration = new Promise<Response>((resolve, reject) => {
    settleGeneration = outcome === "resolve"
      ? () => resolve(jsonResponse({ uuid: "stale-bill" }))
      : () => reject(new Error("stale generation failed"));
  });
  installFetch({
    "GET /api/v1/billings/billing-public-uuid": () => jsonResponse(billing),
    "GET /api/v1/billings/billing-second": () => jsonResponse({
      ...billing,
      items: [{ amount: 0, description: "Energia", item_type: "variable", uuid: "01J00000000000000000000012" }],
      name: "Residencial Lua",
      uuid: "billing-second"
    }),
    "POST /api/v1/billings/billing-public-uuid/bills": () => {
      generationPosts += 1;
      return pendingGeneration;
    }
  });
  renderPage();
  await screen.findByRole("heading", { name: "Gerar Fatura" });
  await moveToItems(user);
  await user.type(screen.getByLabelText("Água"), "10,00");
  await moveFromItemsToReview(user, "Não pode vazar");
  await user.click(screen.getByRole("button", { name: "Gerar Fatura" }));
  expect(screen.getByRole("button", { name: "Gerando..." })).toBeDisabled();
  fireEvent.submit(screen.getByRole("button", { name: "Gerando..." }).closest("form")!);
  expect(generationPosts).toBe(1);

  await user.click(screen.getByRole("button", { name: "Trocar cobrança" }));
  expect((await screen.findAllByText("Residencial Lua")).length).toBeGreaterThanOrEqual(1);
  expect(screen.getByLabelText("Mês de Referência")).toHaveValue("");
  await moveToItems(user);
  expect(screen.getByLabelText("Energia")).toHaveValue("");
  expect(screen.getByRole("button", { name: "Continuar" })).toBeEnabled();

  settleGeneration();
  await new Promise((resolve) => setTimeout(resolve, 0));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/billing-second/bills/generate"));
});
