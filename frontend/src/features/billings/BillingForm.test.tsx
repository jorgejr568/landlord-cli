import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, MemoryRouter, RouterProvider } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { BillingForm, type BillingFormValues } from "./BillingForm";
import { emptyBillingValues } from "./billingFormValues";

type Organization = components["schemas"]["OrganizationResponse"];

const organizations: Organization[] = [
  {
    capabilities: { can_create_billing: true, can_invite: false, can_manage: false, can_view_billing_stats: true },
    created_at: null,
    current_role: "viewer",
    enforce_mfa: false,
    name: "Permitida por capability",
    updated_at: null,
    uuid: "org-allowed"
  },
  {
    capabilities: { can_create_billing: false, can_invite: true, can_manage: true, can_view_billing_stats: false },
    created_at: null,
    current_role: "admin",
    enforce_mfa: false,
    name: "Negada por capability",
    updated_at: null,
    uuid: "org-denied"
  }
];

afterEach(cleanup);

function Harness({ fieldErrors = {} }: { fieldErrors?: Record<string, string> }) {
  const values = emptyBillingValues();
  values.recipients = [{ email: "", id: "recipient-error", name: "" }];
  const onSubmit = vi.fn();
  return <MemoryRouter><BillingForm error="" fieldErrors={fieldErrors} mode="create" onSubmit={onSubmit} organizations={organizations} saving={false} values={values} /></MemoryRouter>;
}

function renderForm(element: React.ReactNode) {
  return render(<MemoryRouter>{element}</MemoryRouter>);
}

it("preserves the create form structure and filters owners by capability instead of role", async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  const values = emptyBillingValues();
  renderForm(<BillingForm error="" fieldErrors={{}} mode="create" onSubmit={onSubmit} organizations={organizations} saving={false} values={values} />);

  expect(screen.getByLabelText("Nome do imóvel")).toHaveFocus();
  expect(screen.getByRole("heading", { name: "Detalhes" }).closest(".panel")).not.toBeNull();
  expect(screen.getByRole("option", { name: "Minha conta" })).toBeVisible();
  expect(screen.getByRole("option", { name: "Permitida por capability" })).toBeVisible();
  expect(screen.queryByRole("option", { name: "Negada por capability" })).not.toBeInTheDocument();
  expect(screen.getByText("Valor inválido")).toHaveAttribute("id", "fixed-subtotal");

  await user.type(screen.getByLabelText("Nome do imóvel"), "Apartamento 302");
  await user.type(screen.getByRole("textbox", { name: /^Descrição$/ }), "Inquilino atual");
  await user.click(screen.getByLabelText("Usar PIX personalizado"));
  await user.type(screen.getByLabelText("Chave PIX"), "pix@example.com");
  await user.type(screen.getByLabelText("Nome do recebedor"), "MARIA");
  await user.type(screen.getByLabelText("Cidade do recebedor"), "SALVADOR");
  await user.click(screen.getByRole("button", { name: "Adicionar destinatário" }));
  await user.type(screen.getByLabelText("Nome do destinatário 1"), " Ana ");
  await user.type(screen.getByLabelText("E-mail do destinatário 1"), " ANA@EXAMPLE.COM ");
  await user.click(screen.getByRole("button", { name: "Adicionar Reply-To" }));
  await user.type(screen.getByLabelText("Nome do Reply-To 1"), " Bia ");
  await user.type(screen.getByLabelText("E-mail do Reply-To 1"), " BIA@EXAMPLE.COM ");
  await user.type(screen.getByLabelText("Descrição do item 1"), "Aluguel");
  await user.type(screen.getByLabelText("Valor do item 1 (R$)"), "2.850,00");
  expect(screen.getByText("R$ 2.850,00")).toBeVisible();
  await user.selectOptions(screen.getByLabelText("Tipo do item 1"), "variable");
  expect(screen.queryByLabelText("Valor do item 1 (R$)")).not.toBeInTheDocument();
  expect(screen.getByText("R$ 0,00")).toBeVisible();
  await user.selectOptions(screen.getByLabelText("Tipo do item 1"), "fixed");
  expect(screen.getByLabelText("Valor do item 1 (R$)")).toHaveValue("");
  await user.selectOptions(screen.getByLabelText("Tipo do item 1"), "variable");
  expect(screen.queryByLabelText("Valor do item 1 (R$)")).not.toBeInTheDocument();

  await user.click(screen.getByRole("button", { name: "Adicionar item" }));
  expect(screen.getByLabelText("Descrição do item 2")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Remover item 2" }));
  expect(screen.queryByLabelText("Descrição do item 2")).not.toBeInTheDocument();
  await user.selectOptions(screen.getByLabelText("Proprietário"), "org-allowed");
  await user.selectOptions(screen.getByLabelText("Proprietário"), "");
  await user.selectOptions(screen.getByLabelText("Proprietário"), "org-allowed");
  await user.click(screen.getByRole("button", { name: "Adicionar destinatário" }));
  await user.click(screen.getByRole("button", { name: "Adicionar Reply-To" }));
  await user.click(screen.getByRole("button", { name: "Criar cobrança" }));

  expect(onSubmit).toHaveBeenCalledWith(expect.objectContaining({
    name: "Apartamento 302",
    ownerType: "organization",
    ownerUuid: "org-allowed",
    recipients: expect.arrayContaining([expect.objectContaining({ email: "ana@example.com", name: "Ana" })]),
    replyTo: expect.arrayContaining([expect.objectContaining({ email: "bia@example.com", name: "Bia" })])
  }));
});

it("renders field and form errors, focuses normalized controls and supports edit copy", async () => {
  const user = userEvent.setup();
  const values: BillingFormValues = {
    ...emptyBillingValues(),
    description: "Inquilino",
    items: [{ amount: "1.000,00", description: "Aluguel", id: "item-a", itemType: "fixed" }],
    name: "Casa",
    pixKey: "chave",
    pixMerchantCity: "SALVADOR",
    pixMerchantName: "MARIA",
    recipients: [{ email: "maria@example.com", id: "recipient-a", name: "Maria" }],
    replyTo: [{ email: "ana@example.com", id: "reply-a", name: "Ana" }]
  };
  const onSubmit = vi.fn();
  const view = renderForm(<BillingForm error="Falha geral." fieldErrors={{ "items.0.amount": "Valor inválido.", name: "Nome inválido." }} mode="edit" onSubmit={onSubmit} organizations={[]} saving values={values} />);

  expect(screen.getByText("Falha geral.")).toHaveAttribute("role", "alert");
  expect(screen.getByText("Nome inválido.")).toBeVisible();
  expect(screen.getByText("Valor inválido.")).toBeVisible();
  expect(screen.getByLabelText("Nome do imóvel")).toHaveFocus();
  expect(screen.queryByLabelText("Proprietário")).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Salvando..." })).toBeDisabled();

  view.rerender(<MemoryRouter><BillingForm error="" fieldErrors={{ "items.0.amount": "Valor inválido." }} mode="edit" onSubmit={onSubmit} organizations={[]} saving={false} values={values} /></MemoryRouter>);
  expect(screen.getByLabelText("Valor do item 1 (R$)")).toHaveFocus();
  await user.click(screen.getByRole("button", { name: "Salvar alterações" }));
  expect(onSubmit).toHaveBeenCalled();
});

it("keeps invalid currency visible and prevents removing the final item row", async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  renderForm(<BillingForm error="" fieldErrors={{}} mode="create" onSubmit={onSubmit} organizations={[]} saving={false} values={emptyBillingValues()} />);

  await user.type(screen.getByLabelText("Valor do item 1 (R$)"), "abc");
  expect(screen.getByText("Valor inválido")).toBeVisible();
  expect(screen.getByRole("button", { name: "Remover item 1" })).toBeDisabled();
  await user.click(screen.getByRole("button", { name: "Adicionar item" }));
  expect(screen.getByRole("button", { name: "Remover item 1" })).toBeEnabled();
  await user.click(screen.getByRole("button", { name: "Remover item 2" }));
  expect(screen.getByRole("button", { name: "Remover item 1" })).toBeDisabled();
});

it("blocks invalid fixed money and incomplete custom PIX locally with accessible field errors", async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  renderForm(<BillingForm error="" fieldErrors={{}} mode="create" onSubmit={onSubmit} organizations={[]} saving={false} values={emptyBillingValues()} />);

  await user.type(screen.getByLabelText("Nome do imóvel"), "Casa");
  await user.click(screen.getByLabelText("Usar PIX personalizado"));
  await user.type(screen.getByLabelText("Descrição do item 1"), "Aluguel");
  await user.type(screen.getByLabelText("Valor do item 1 (R$)"), "invalido");
  await user.type(screen.getByLabelText("Nome do recebedor"), "MARIA");
  await user.click(screen.getByRole("button", { name: "Criar cobrança" }));

  expect(onSubmit).not.toHaveBeenCalled();
  expect(screen.getByText("Informe um valor válido.")).toBeVisible();
  expect(screen.getByText("Informe a chave PIX.")).toBeVisible();
  expect(screen.getByLabelText("Valor do item 1 (R$)")).toHaveAttribute("aria-describedby", expect.stringContaining("amount-error"));
  expect(screen.getByLabelText("Valor do item 1 (R$)")).toHaveFocus();
});

it("reports every trimmed field, PIX, recipient, and reply-to validation error locally", async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  renderForm(<BillingForm error="" fieldErrors={{}} mode="create" onSubmit={onSubmit} organizations={[]} saving={false} values={emptyBillingValues()} />);

  fireEvent.change(screen.getByRole("textbox", { name: /^Descrição$/ }), { target: { value: "x".repeat(2001) } });
  await user.click(screen.getByLabelText("Usar PIX personalizado"));
  fireEvent.change(screen.getByLabelText("Nome do recebedor"), { target: { value: "M".repeat(26) } });
  await user.click(screen.getByRole("button", { name: "Adicionar destinatário" }));
  await user.type(screen.getByLabelText("E-mail do destinatário 1"), "invalido");
  await user.click(screen.getByRole("button", { name: "Adicionar Reply-To" }));
  await user.type(screen.getByLabelText("E-mail do Reply-To 1"), "invalido");
  fireEvent.submit(screen.getByRole("button", { name: "Criar cobrança" }).closest("form")!);

  expect(onSubmit).not.toHaveBeenCalled();
  expect(screen.getAllByText("Este campo é obrigatório.")).toHaveLength(4);
  expect(screen.getAllByText("Informe um e-mail válido.")).toHaveLength(2);
  expect(screen.getByText("Informe no máximo 2000 caracteres.")).toBeVisible();
  expect(screen.getByText("Informe no máximo 25 caracteres.")).toBeVisible();
  expect(screen.getByText("Informe a chave PIX.")).toBeVisible();
  expect(screen.getByText("Informe a cidade do recebedor.")).toBeVisible();
});

it("renders an aggregate items error and focuses the first item description", () => {
  renderForm(<BillingForm error="" fieldErrors={{ items: "Adicione pelo menos um item." }} mode="create" onSubmit={vi.fn()} organizations={[]} saving={false} values={emptyBillingValues()} />);

  expect(screen.getByText("Adicione pelo menos um item.")).toBeVisible();
  expect(screen.getByLabelText("Descrição do item 1")).toHaveFocus();
});

it("focuses the add action for an aggregate items error without rows and describes row errors", () => {
  const valuesWithoutItems = emptyBillingValues();
  valuesWithoutItems.items = [];
  const view = renderForm(<BillingForm error="" fieldErrors={{ items: "Adicione pelo menos um item." }} mode="create" onSubmit={vi.fn()} organizations={[]} saving={false} values={valuesWithoutItems} />);

  expect(screen.getByRole("button", { name: "Adicionar item" })).toHaveFocus();
  view.unmount();

  renderForm(<BillingForm error="" fieldErrors={{ "items.0.description": "Informe a descrição." }} mode="create" onSubmit={vi.fn()} organizations={[]} saving={false} values={emptyBillingValues()} />);
  expect(screen.getByText("Informe a descrição.")).toBeVisible();
  expect(screen.getByLabelText("Descrição do item 1")).toHaveAttribute("aria-describedby", expect.stringContaining("description-error"));
});

it("focuses PIX and contact fields when their server errors change", () => {
  const view = render(<Harness fieldErrors={{ pix_key: "PIX inválido." }} />);
  expect(screen.getByLabelText("Chave PIX")).toHaveFocus();
  view.rerender(<Harness fieldErrors={{ "recipients.0.email": "E-mail inválido." }} />);
  expect(screen.getByText("E-mail inválido.")).toBeVisible();
  view.rerender(<Harness fieldErrors={{ "recipients.0.name": "Nome inválido." }} />);
  expect(screen.getByText("Nome inválido.")).toBeVisible();
  view.rerender(<Harness fieldErrors={{ description: "Descrição inválida." }} />);
  expect(screen.getByText("Descrição inválida.")).toBeVisible();
  view.rerender(<Harness fieldErrors={{ unexpected: "Erro inesperado." }} />);
});

it("renders an organization-owned billing owner as read-only in edit mode", () => {
  const values = { ...emptyBillingValues(), ownerType: "organization" as const, ownerUuid: "org-allowed" };
  renderForm(<BillingForm error="" fieldErrors={{}} mode="edit" onSubmit={vi.fn()} organizations={organizations} ownerName="Ribeiro Imóveis" saving={false} values={values} />);

  expect(screen.getByLabelText("Proprietário")).toHaveValue("Ribeiro Imóveis");
  expect(screen.getByLabelText("Proprietário")).toBeDisabled();
  expect(screen.queryByRole("option", { name: "Minha conta" })).not.toBeInTheDocument();
});

it("uses an organization fallback label when an organization owner has no display name", () => {
  const values = { ...emptyBillingValues(), ownerType: "organization" as const, ownerUuid: "org-allowed" };
  renderForm(<BillingForm error="" fieldErrors={{}} mode="edit" onSubmit={vi.fn()} organizations={organizations} saving={false} values={values} />);

  expect(screen.getByLabelText("Proprietário")).toHaveValue("Organização");
});

it("blocks internal navigation after an edit until the user confirms discarding the draft", async () => {
  const user = userEvent.setup();
  const confirm = vi.spyOn(window, "confirm").mockReturnValueOnce(false).mockReturnValueOnce(true);
  const router = createMemoryRouter([
    { element: <BillingForm cancelTo="/next" error="" fieldErrors={{}} mode="edit" onSubmit={vi.fn()} organizations={[]} saving={false} values={emptyBillingValues()} />, path: "/" },
    { element: <p>Outra página</p>, path: "/next" }
  ], { initialEntries: ["/"] });
  render(<RouterProvider router={router} />);

  const cleanUnload = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(cleanUnload);
  expect(cleanUnload.defaultPrevented).toBe(false);
  await user.click(screen.getByLabelText("Usar PIX personalizado"));
  const unload = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(unload);
  expect(unload.defaultPrevented).toBe(true);
  await user.click(screen.getByRole("link", { name: "Cancelar" }));
  expect(confirm).toHaveBeenCalledTimes(1);
  expect(screen.queryByText("Outra página")).not.toBeInTheDocument();

  await user.click(screen.getByRole("link", { name: "Cancelar" }));
  expect(await screen.findByText("Outra página")).toBeVisible();
  expect(confirm).toHaveBeenCalledTimes(2);
});
