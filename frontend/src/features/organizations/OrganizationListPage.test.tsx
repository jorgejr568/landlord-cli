import { act, cleanup, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, expect, it, vi } from "vitest";

import type { components } from "../../lib/api/schema";
import { jsonResponse, problemResponse } from "../../test/auth";
import { OrganizationListPage } from "./OrganizationListPage";

type Organization = components["schemas"]["OrganizationResponse"];

const organization: Organization = {
  capabilities: { can_create_billing: true, can_invite: true, can_manage: true, can_view_billing_stats: true },
  created_at: "2026-07-18T10:00:00Z",
  current_role: "admin",
  enforce_mfa: true,
  name: "Ribeiro Imóveis",
  updated_at: "2026-07-18T11:00:00Z",
  uuid: "org-public-uuid"
};

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function installList(items: Organization[]) {
  vi.stubGlobal("fetch", vi.fn(() => jsonResponse({ items })));
  return render(<MemoryRouter><OrganizationListPage /></MemoryRouter>);
}

it("guides a fresh account to its first organization with one clear action", async () => {
  document.title = "Anterior";
  let resolvePending!: (response: Response) => void;
  const pending = new Promise<Response>((resolve) => {
    resolvePending = resolve;
  });
  vi.stubGlobal("fetch", vi.fn(() => pending));
  const view = render(<MemoryRouter><OrganizationListPage /></MemoryRouter>);

  expect(screen.getByText("Carregando organizações…")).toBeVisible();
  resolvePending(jsonResponse({ items: [] }));

  expect(await screen.findByRole("heading", { name: "Organizações" })).toHaveClass("pagehead__title");
  expect(screen.getByRole("heading", { name: "Organize sua operação em equipe" })).toBeVisible();
  expect(screen.getByText(/Uma organização reúne imóveis, cobranças e pessoas/)).toBeVisible();
  const createLinks = screen.getAllByRole("link", { name: "Criar organização" });
  expect(createLinks).toHaveLength(1);
  expect(createLinks[0]).toHaveAttribute("href", "/organizations/create");
  await waitFor(() => expect(document.title).toBe("Organizações - Rentivo"));
  view.unmount();
  expect(document.title).toBe("Anterior");
});

it("renders a scannable organization directory with role, access and MFA context", async () => {
  installList([organization]);

  const card = await screen.findByRole("link", { name: /Ribeiro Imóveis/ });
  expect(card).toHaveClass("organization-directory__row");
  expect(card).toHaveAttribute("href", "/organizations/org-public-uuid");
  expect(card.querySelector(".organization-directory__mark")).toHaveTextContent("R");
  expect(screen.getByText("Administrador")).toBeVisible();
  expect(screen.getByText("Acesso completo")).toBeVisible();
  expect(screen.getByText("MFA exigido")).toBeVisible();
  expect(screen.getByText("1 organização")).toBeVisible();
  expect(screen.getByRole("link", { name: "Criar organização" })).toHaveClass("btn--primary");
});

it("handles long names and explains restricted access without hiding the destination", async () => {
  installList([{
    ...organization,
    capabilities: {
      can_create_billing: false,
      can_invite: false,
      can_manage: false,
      can_view_billing_stats: false
    },
    current_role: "viewer",
    enforce_mfa: false,
    name: "Administração Patrimonial Família Ribeiro e Associados do Centro Histórico",
    uuid: "org-long-name"
  }]);

  const row = await screen.findByRole("link", { name: /Administração Patrimonial/ });
  expect(row).toHaveAttribute("href", "/organizations/org-long-name");
  expect(row.querySelector(".organization-directory__name")).toHaveClass("organization-directory__name");
  expect(screen.getByText("Visualizador")).toBeVisible();
  expect(screen.getByText("Somente leitura")).toBeVisible();
  expect(screen.getByText("MFA opcional")).toBeVisible();
});

it("distinguishes billing managers in a multi-organization directory", async () => {
  installList([
    {
      ...organization,
      capabilities: {
        ...organization.capabilities,
        can_manage: false
      },
      current_role: "manager",
      name: "Ribeiro Operações",
      uuid: "org-manager"
    },
    {
      ...organization,
      name: "Ribeiro Administração",
      uuid: "org-admin"
    }
  ]);

  expect(await screen.findByText("2 organizações")).toBeVisible();
  expect(screen.getByText("Gerencia cobranças")).toBeVisible();
  expect(screen.getByText("Gerente")).toBeVisible();
});

it("retries API and network failures", async () => {
  const user = userEvent.setup();
  let attempts = 0;
  vi.stubGlobal("fetch", vi.fn(() => {
    attempts += 1;
    if (attempts === 1) {
      return problemResponse({
        code: "organizations_unavailable",
        detail: "Organizações indisponíveis.",
        fields: {},
        request_id: "request-id",
        status: 503,
        title: "Indisponível",
        type: "problem"
      });
    }
    if (attempts === 2) {
      throw new Error("offline");
    }
    return jsonResponse({ items: [organization] });
  }));
  render(<MemoryRouter><OrganizationListPage /></MemoryRouter>);

  expect(await screen.findByText("Organizações indisponíveis.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
  expect(await screen.findByText("Não foi possível carregar as organizações.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
  await waitFor(() => expect(screen.getByText("Ribeiro Imóveis")).toBeVisible());
});

it("ignores loads that settle after the page unmounts", async () => {
  let resolveLoad!: (response: Response) => void;
  const pendingLoad = new Promise<Response>((resolve) => { resolveLoad = resolve; });
  let loadSignal: AbortSignal | null | undefined;
  vi.stubGlobal("fetch", vi.fn((_input: RequestInfo | URL, init?: RequestInit) => {
    loadSignal = init?.signal;
    return pendingLoad;
  }));
  const view = render(<MemoryRouter><OrganizationListPage /></MemoryRouter>);

  expect(screen.getByText("Carregando organizações…")).toBeVisible();
  await waitFor(() => expect(loadSignal).toBeDefined());
  view.unmount();
  expect(loadSignal?.aborted).toBe(true);
  await act(async () => { resolveLoad(jsonResponse({ items: [organization] })); });

  let rejectLoad!: (reason?: unknown) => void;
  const failingLoad = new Promise<Response>((resolve, reject) => { rejectLoad = reject; });
  vi.stubGlobal("fetch", vi.fn(() => failingLoad));
  const second = render(<MemoryRouter><OrganizationListPage /></MemoryRouter>);
  second.unmount();
  await act(async () => { rejectLoad(new Error("offline")); });

  expect(screen.queryByText("Não foi possível carregar as organizações.")).not.toBeInTheDocument();
});
