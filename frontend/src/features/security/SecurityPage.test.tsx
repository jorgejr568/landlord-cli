import { act, fireEvent, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, expect, it, vi } from "vitest";

import { jsonResponse, problemResponse } from "../../test/auth";
import { renderAuth } from "../../test/renderAuth";
import type { components } from "../../lib/api/schema";
import { SecurityPage } from "./SecurityPage";
import { createPasskey } from "./webauthn";

vi.mock("./webauthn", () => ({ createPasskey: vi.fn() }));

const summary: components["schemas"]["SecuritySummaryResponse"] = {
  mfa: { organization_enforced: false, setup_required: false },
  passkeys: [],
  profile: { email: "user@example.com", pix_key: "pix", pix_merchant_city: "SP", pix_merchant_name: "User" },
  totp: { enabled: true, recovery_codes_remaining: 8 }
};

const apiKeyOptions = { default_expiration_days: 90, max_expiration_days: 365, organizations: [], personal_workspace: { resource_id: "personal", resource_type: "user" }, scopes: ["profile:read"] };

function renderPage(handlers: Record<string, (init?: RequestInit) => Response | Promise<Response>> = {}, value: components["schemas"]["SecuritySummaryResponse"] = summary) {
  return renderAuth(<SecurityPage />, {
    handlers: {
      "/api/v1/api-keys": () => jsonResponse({ items: [] }),
      "/api/v1/api-keys/options": () => jsonResponse(apiKeyOptions),
      "/api/v1/auth/logout": () => new Response(null, { status: 204 }),
      "/api/v1/security": () => jsonResponse(value),
      "/api/v1/security/account-deletion-readiness": () =>
        jsonResponse({ can_delete: true, reason: null }),
      ...handlers
    },
    path: "/security",
    session: "authenticated"
  });
}

afterEach(() => {
  vi.mocked(createPasskey).mockReset();
  vi.unstubAllGlobals();
});

it("presents the account protections as one navigable security workspace", async () => {
  renderPage();

  expect(await screen.findByRole("heading", { level: 1, name: "Segurança" })).toBeVisible();
  const shortcuts = screen.getByRole("navigation", { name: "Atalhos de segurança" });
  expect(shortcuts).toBeVisible();
  expect(shortcuts.getElementsByTagName("a")).toHaveLength(4);
  expect(screen.getByRole("link", { name: "Recebimento" })).toHaveAttribute("href", "#recebimento");
  expect(screen.getByRole("link", { name: "Acesso" })).toHaveAttribute("href", "#acesso");
  expect(screen.getByRole("link", { name: "Integrações" })).toHaveAttribute("href", "#integracoes");
  expect(screen.getByRole("link", { name: "Conta" })).toHaveAttribute("href", "#conta");
  expect(screen.getByRole("link", { name: "Esqueci minha senha" })).toHaveAttribute("href", "/forgot-password");
  expect(screen.getByText("PIX configurado")).toBeVisible();
  expect(screen.getByText("Aplicativo autenticador ativo")).toBeVisible();
  expect(screen.getByText("Nenhuma chave de acesso")).toBeVisible();
});

it("summarizes multiple registered passkeys with the plural label", async () => {
  renderPage({}, {
    ...summary,
    passkeys: [
      { created_at: "2026-07-17T10:00:00Z", last_used_at: null, name: "Notebook", uuid: "pk-notebook" },
      { created_at: "2026-07-18T10:00:00Z", last_used_at: null, name: "Celular", uuid: "pk-phone" }
    ]
  });

  expect(await screen.findByText("2 chaves de acesso")).toBeVisible();
});

it("exposes password-manager metadata on every security credential", async () => {
  renderPage();

  await screen.findByRole("heading", { name: "Segurança" });
  expect(screen.getByLabelText("Senha atual")).toHaveAttribute("autocomplete", "current-password");
  expect(screen.getByLabelText("Senha atual")).toHaveAttribute("name", "current_password");
  expect(screen.getByLabelText("Nova senha")).toHaveAttribute("autocomplete", "new-password");
  expect(screen.getByLabelText("Nova senha")).toHaveAttribute("name", "new_password");
  expect(screen.getByLabelText("Confirmar nova senha")).toHaveAttribute("autocomplete", "new-password");
  expect(screen.getByLabelText("Confirmar nova senha")).toHaveAttribute("name", "confirm_password");
});

it("ports the security summary and clears authentication after disabling TOTP", async () => {
  const user = userEvent.setup();
  renderPage({ "/api/v1/security/totp/disable": () => new Response(null, { status: 204 }) });

  expect(await screen.findByRole("heading", { name: "Segurança" })).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Desativar TOTP" }));
  await user.type(screen.getByLabelText("Confirme sua senha para desativar"), "password");
  await user.click(screen.getByRole("button", { name: "Confirmar desativação" }));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
});

it("still lands on /login when logout fails after disabling TOTP", async () => {
  const user = userEvent.setup();
  renderPage({
    "/api/v1/auth/logout": () => {
      throw new Error("offline");
    },
    "/api/v1/security/totp/disable": () => new Response(null, { status: 204 })
  });

  expect(await screen.findByRole("heading", { name: "Segurança" })).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Desativar TOTP" }));
  await user.type(screen.getByLabelText("Confirme sua senha para desativar"), "password");
  await user.click(screen.getByRole("button", { name: "Confirmar desativação" }));

  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
});

it("still lands on /login when logout fails after a passkey deletion revokes the session", async () => {
  const user = userEvent.setup();
  const value = { ...summary, passkeys: [{ created_at: "2026-07-17T10:00:00Z", last_used_at: null, name: "Notebook", uuid: "pk-uuid" }] };
  renderPage({
    "/api/v1/auth/logout": () => {
      throw new Error("offline");
    },
    "/api/v1/security/passkeys/pk-uuid": () => new Response(null, { status: 204 })
  }, value);

  await user.click(await screen.findByRole("button", { name: "Remover Notebook" }));
  await user.click(screen.getByRole("button", { name: "Remover passkey" }));

  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
});

it("shows incomplete PIX, enforced MFA, disabled TOTP, and low recovery warnings", async () => {
  const value = {
    ...summary,
    mfa: { organization_enforced: true, setup_required: true },
    profile: { ...summary.profile, pix_key: "", pix_merchant_city: "", pix_merchant_name: "" },
    totp: { enabled: false, recovery_codes_remaining: 0 }
  };
  renderPage({}, value);
  expect(await screen.findByText(/Preencha todos os campos/)).toBeVisible();
  expect(screen.getAllByText(/Sua organização exige/).length).toBeGreaterThan(0);
  expect(screen.getByRole("link", { name: "Configurar TOTP" })).toHaveAttribute("href", "/security/totp/setup");
});

it("updates PIX and changes the password atomically", async () => {
  const user = userEvent.setup();
  renderPage({
    "/api/v1/security/change-password": () => new Response(null, { headers: { "X-Rentivo-Analytics-Event": "rentivo_password_changed" }, status: 204 }),
    "/api/v1/security/pix": (init) => jsonResponse({ profile: { ...summary.profile, pix_key: JSON.parse(String(init?.body)).pix_key } })
  });
  await screen.findByRole("heading", { name: "Segurança" });
  await user.clear(screen.getByLabelText("Chave PIX"));
  await user.type(screen.getByLabelText("Chave PIX"), "nova-chave");
  await user.clear(screen.getByLabelText("Nome do recebedor"));
  await user.type(screen.getByLabelText("Nome do recebedor"), "Novo Nome");
  await user.clear(screen.getByLabelText("Cidade do recebedor"));
  await user.type(screen.getByLabelText("Cidade do recebedor"), "Rio");
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(await screen.findByText("Dados do PIX atualizados.")).toBeVisible();
  await user.type(screen.getByLabelText("Senha atual"), "current");
  await user.type(screen.getByLabelText("Nova senha"), "new-password");
  await user.type(screen.getByLabelText("Confirmar nova senha"), "different");
  await user.click(screen.getByRole("button", { name: "Alterar senha" }));
  expect(await screen.findByText("As senhas não coincidem.")).toBeVisible();
  await user.clear(screen.getByLabelText("Confirmar nova senha"));
  await user.type(screen.getByLabelText("Confirmar nova senha"), "new-password");
  await user.click(screen.getByRole("button", { name: "Alterar senha" }));
  expect(await screen.findByText("Senha alterada com sucesso!")).toBeVisible();
  expect(screen.getByLabelText("Senha atual")).toHaveValue("");
});

it("requires a complete personal PIX configuration and exposes the API limits", async () => {
  const user = userEvent.setup();
  let updates = 0;
  renderPage({
    "/api/v1/security/pix": () => {
      updates += 1;
      return jsonResponse({ profile: summary.profile });
    }
  });
  await screen.findByRole("heading", { name: "Segurança" });

  const key = screen.getByLabelText("Chave PIX");
  const name = screen.getByLabelText("Nome do recebedor");
  const city = screen.getByLabelText("Cidade do recebedor");
  fireEvent.change(name, { target: { value: "😀".repeat(26) } });
  fireEvent.change(city, { target: { value: "😀".repeat(16) } });
  expect(name).toHaveValue("😀".repeat(25));
  expect(city).toHaveValue("😀".repeat(15));
  await user.clear(key);
  await user.clear(name);
  await user.clear(city);
  await user.type(name, "Pessoa");
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(key).toHaveFocus();
  await user.clear(name);
  await user.type(key, "person@example.com");
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));

  expect(await screen.findByText("Informe o nome do recebedor.")).toBeVisible();
  expect(screen.getByText("Informe a cidade do recebedor.")).toBeVisible();
  expect(updates).toBe(0);
  expect(name).toHaveFocus();

  await user.type(name, "Pessoa");
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(city).toHaveFocus();
  expect(updates).toBe(0);
});

it("focuses each incomplete PIX field before calling the API", async () => {
  const user = userEvent.setup();
  let pixPosts = 0;
  renderPage({ "/api/v1/security/pix": () => { pixPosts += 1; return jsonResponse({ profile: summary.profile }); } });
  await screen.findByRole("heading", { name: "Segurança" });

  await user.clear(screen.getByLabelText("Chave PIX"));
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(await screen.findByText("Informe a chave PIX.")).toBeVisible();
  expect(screen.getByLabelText("Chave PIX")).toHaveFocus();
  await user.type(screen.getByLabelText("Chave PIX"), "pix");
  await user.clear(screen.getByLabelText("Nome do recebedor"));
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(await screen.findByText("Informe o nome do recebedor.")).toBeVisible();
  expect(screen.getByLabelText("Nome do recebedor")).toHaveFocus();
  await user.type(screen.getByLabelText("Nome do recebedor"), "User");
  await user.clear(screen.getByLabelText("Cidade do recebedor"));
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(await screen.findByText("Informe a cidade do recebedor.")).toBeVisible();
  expect(screen.getByLabelText("Cidade do recebedor")).toHaveFocus();
  expect(pixPosts).toBe(0);
});

it("links every PIX control to stable hint and validation error semantics", async () => {
  const user = userEvent.setup();
  renderPage();
  await screen.findByRole("heading", { name: "Segurança" });

  const key = screen.getByLabelText("Chave PIX");
  const name = screen.getByLabelText("Nome do recebedor");
  const city = screen.getByLabelText("Cidade do recebedor");
  expect(key).toHaveAttribute("aria-describedby", "pix_key-hint");
  expect(name).toHaveAttribute("aria-describedby", "pix_merchant_name-hint");
  expect(city).toHaveAttribute("aria-describedby", "pix_merchant_city-hint");

  await user.clear(key);
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));

  expect(key).toHaveAttribute("aria-invalid", "true");
  expect(key).toHaveAttribute("aria-describedby", "pix_key-error");
  expect(screen.getByText("Informe a chave PIX.")).toHaveAttribute("id", "pix_key-error");
  expect(screen.getByText("Informe a chave PIX.")).toHaveAttribute("role", "alert");

  await user.type(key, "pix@example.com");
  await user.clear(name);
  await user.clear(city);
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));

  expect(name).toHaveAttribute("aria-describedby", "pix_merchant_name-error");
  expect(city).toHaveAttribute("aria-describedby", "pix_merchant_city-error");
});

it("loads nullable PIX profile values as empty controls", async () => {
  const nullableProfile = {
    email: summary.profile.email,
    pix_key: null,
    pix_merchant_city: null,
    pix_merchant_name: null
  } as unknown as typeof summary.profile;
  renderPage({}, { ...summary, profile: nullableProfile });
  expect(await screen.findByLabelText("Chave PIX")).toHaveValue("");
  expect(screen.getByLabelText("Nome do recebedor")).toHaveValue("");
  expect(screen.getByLabelText("Cidade do recebedor")).toHaveValue("");
});

it("routes regenerated recovery codes to their one-time screen", async () => {
  const user = userEvent.setup();
  renderPage({ "/api/v1/security/recovery-codes/regenerate": () => jsonResponse({ recovery_codes: ["one"] }, 200, { "X-Rentivo-Analytics-Event": "rentivo_recovery_codes_regenerated" }) });
  await user.click(await screen.findByRole("button", { name: "Regenerar códigos de recuperação" }));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/security/recovery-codes"));
});

it("keeps recovery-code regeneration single-flight", async () => {
  let attempts = 0;
  let resolveRequest!: (response: Response) => void;
  const pendingRequest = new Promise<Response>((resolve) => { resolveRequest = resolve; });
  renderPage({
    "/api/v1/security/recovery-codes/regenerate": () => {
      attempts += 1;
      return pendingRequest;
    }
  });
  const button = await screen.findByRole("button", { name: "Regenerar códigos de recuperação" });

  act(() => {
    button.click();
    button.click();
  });

  await waitFor(() => expect(attempts).toBe(1));
  expect(button).toBeDisabled();
  resolveRequest(jsonResponse({ recovery_codes: ["one"] }));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/security/recovery-codes"));
});

it("registers a passkey with typed WebAuthn data", async () => {
  const user = userEvent.setup();
  vi.mocked(createPasskey).mockResolvedValue({
    clientExtensionResults: {}, id: "credential", rawId: "raw", response: { attestationObject: "attestation", clientDataJSON: "client" }, type: "public-key"
  });
  renderPage({
    "/api/v1/security/passkeys/register/begin": () => jsonResponse({ challenge_id: "challenge", options: { challenge: "challenge", excludeCredentials: [], hints: [], pubKeyCredParams: [], rp: { name: "Rentivo" }, user: { displayName: "User", id: "id", name: "user@example.com" } } }),
    "/api/v1/security/passkeys/register/complete": () => jsonResponse({ created_at: "2026-07-17T10:00:00Z", last_used_at: null, name: "Notebook", uuid: "pk-uuid" }, 200, { "X-Rentivo-Analytics-Event": "rentivo_passkey_added" })
  });
  await user.type(await screen.findByLabelText("Nome da passkey"), "Notebook");
  await user.click(screen.getByRole("button", { name: /Adicionar passkey/ }));
  expect(await screen.findByText("Passkey cadastrada.")).toBeVisible();
  expect(screen.getByText("Notebook")).toBeVisible();
  vi.mocked(createPasskey).mockResolvedValueOnce(null);
  await user.click(screen.getByRole("button", { name: /Adicionar passkey/ }));
  await waitFor(() => expect(screen.queryByRole("alert")).not.toBeInTheDocument());
});

it("logs out after deleting a passkey and preserves the session when deletion is rejected", async () => {
  const user = userEvent.setup();
  let deletions = 0;
  const value = { ...summary, passkeys: [{ created_at: "2026-07-17T10:00:00Z", last_used_at: null, name: "Notebook", uuid: "pk-uuid" }] };
  renderPage({
    "/api/v1/security/passkeys/pk-uuid": () => {
      deletions += 1;
      return deletions === 1
        ? problemResponse({ code: "mfa_required_by_organization", detail: "Mantenha um fator ativo.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" })
        : new Response(null, { status: 204 });
    }
  }, value);
  await user.click(await screen.findByRole("button", { name: "Remover Notebook" }));
  await user.click(screen.getByRole("button", { name: "Remover passkey" }));
  expect(await screen.findByText("Mantenha um fator ativo.")).toBeVisible();
  expect(screen.getByTestId("location")).toHaveTextContent("/security");
  await user.click(screen.getByRole("button", { name: "Remover Notebook" }));
  await user.click(screen.getByRole("button", { name: "Remover passkey" }));
  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
});

it("surfaces API and network action failures", async () => {
  const user = userEvent.setup();
  let pixAttempts = 0;
  let passwordAttempts = 0;
  let recoveryAttempts = 0;
  renderPage({
    "/api/v1/security/change-password": () => {
      passwordAttempts += 1;
      if (passwordAttempts === 1) return problemResponse({ code: "password", detail: "Senha atual incorreta.", fields: {}, request_id: "id", status: 400, title: "Inválida", type: "problem" });
      throw new Error("offline");
    },
    "/api/v1/security/pix": () => {
      pixAttempts += 1;
      if (pixAttempts === 1) return problemResponse({ code: "pix", detail: "PIX inválido.", fields: {}, request_id: "id", status: 422, title: "Inválido", type: "problem" });
      throw new Error("offline");
    },
    "/api/v1/security/recovery-codes/regenerate": () => {
      recoveryAttempts += 1;
      if (recoveryAttempts === 1) return problemResponse({ code: "recovery", detail: "Não disponível.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" });
      throw new Error("offline");
    },
    "/api/v1/security/totp/disable": () => problemResponse({ code: "totp", detail: "TOTP protegido.", fields: {}, request_id: "id", status: 409, title: "Conflito", type: "problem" })
  });
  await screen.findByRole("heading", { name: "Segurança" });
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(await screen.findByText("PIX inválido.")).toBeVisible();
  expect(screen.getByLabelText("Chave PIX")).toHaveFocus();
  await user.click(screen.getByRole("button", { name: "Salvar dados PIX" }));
  expect(await screen.findByText("Não foi possível atualizar os dados do PIX.")).toBeVisible();
  await user.type(screen.getByLabelText("Senha atual"), "current");
  await user.type(screen.getByLabelText("Nova senha"), "new");
  await user.type(screen.getByLabelText("Confirmar nova senha"), "new");
  await user.click(screen.getByRole("button", { name: "Alterar senha" }));
  expect(await screen.findByText("Senha atual incorreta.")).toBeVisible();
  expect(screen.getByLabelText("Senha atual")).toHaveFocus();
  await user.click(screen.getByRole("button", { name: "Alterar senha" }));
  expect(await screen.findByText("Não foi possível alterar a senha.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Regenerar códigos de recuperação" }));
  expect(await screen.findByText("Não disponível.")).toBeVisible();
  expect(screen.getByRole("button", { name: "Regenerar códigos de recuperação" })).toHaveFocus();
  await user.click(screen.getByRole("button", { name: "Regenerar códigos de recuperação" }));
  expect(await screen.findByText("Não foi possível regenerar os códigos de recuperação.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Desativar TOTP" }));
  await user.type(screen.getByLabelText("Confirme sua senha para desativar"), "password");
  await user.click(screen.getByRole("button", { name: "Confirmar desativação" }));
  expect(await screen.findByText("TOTP protegido.")).toBeVisible();
  expect(screen.getByLabelText("Confirme sua senha para desativar")).toHaveFocus();
});

it("reveals the delete-account form and deletes the account", async () => {
  const user = userEvent.setup();
  renderPage({
    "/api/v1/security/delete-account": (init) => {
      expect(JSON.parse(String(init?.body))).toEqual({ password: "s3cret" });
      return new Response(null, { headers: { "X-Rentivo-Analytics-Event": "rentivo_account_deleted" }, status: 204 });
    }
  });
  await screen.findByRole("heading", { name: "Segurança" });

  await user.click(screen.getByRole("button", { name: "Excluir conta" }));
  await user.type(screen.getByLabelText("Confirme sua senha para excluir a conta"), "s3cret");
  await user.click(screen.getByRole("button", { name: "Excluir minha conta permanentemente" }));

  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
  expect(window.dataLayer?.at(-1)).toEqual({ event: "rentivo_account_deleted" });
});

it("keeps over-72-byte multibyte passwords local for sensitive actions", async () => {
  const user = userEvent.setup();
  const { fetchMock } = renderPage();
  await screen.findByRole("heading", { name: "Segurança" });
  await user.type(screen.getByLabelText("Senha atual"), "á".repeat(37));
  await user.type(screen.getByLabelText("Nova senha"), "nova-senha");
  await user.type(screen.getByLabelText("Confirmar nova senha"), "nova-senha");
  await user.click(screen.getByRole("button", { name: "Alterar senha" }));
  expect(await screen.findByText("Senha muito longa.")).toBeVisible();

  await user.click(screen.getByRole("button", { name: "Desativar TOTP" }));
  await user.type(screen.getByLabelText("Confirme sua senha para desativar"), "á".repeat(37));
  await user.click(screen.getByRole("button", { name: "Confirmar desativação" }));
  expect(await screen.findByText("Senha muito longa.")).toBeVisible();

  await user.click(screen.getByRole("button", { name: "Excluir conta" }));
  await user.type(screen.getByLabelText("Confirme sua senha para excluir a conta"), "á".repeat(37));
  await user.click(screen.getByRole("button", { name: "Excluir minha conta permanentemente" }));
  expect(await screen.findByText("Senha muito longa.")).toBeVisible();
  expect(fetchMock.mock.calls.some(([url]) => [
    "/api/v1/security/change-password",
    "/api/v1/security/totp/disable",
    "/api/v1/security/delete-account"
  ].includes(String(url)))).toBe(false);
});

it("blocks account deletion from readiness responses and retries readiness failures", async () => {
  const user = userEvent.setup();
  let readinessAttempts = 0;
  const view = renderPage({
    "/api/v1/security/account-deletion-readiness": () => {
      readinessAttempts += 1;
      return readinessAttempts === 1
        ? problemResponse({ code: "offline", detail: "Não foi possível verificar.", fields: {}, request_id: "id", status: 503, title: "Indisponível", type: "problem" })
        : jsonResponse({ can_delete: false, reason: "sole_organization_admin" });
    }
  });

  expect(await screen.findByText("Não foi possível verificar.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Verificar novamente" }));
  expect(await screen.findByText(/transfira a administração/i)).toBeVisible();
  expect(screen.queryByRole("button", { name: "Excluir conta" })).not.toBeInTheDocument();
  view.unmount();

  renderPage({ "/api/v1/security/account-deletion-readiness": () => jsonResponse({ can_delete: false, reason: null }) });
  expect(await screen.findByText("A exclusão da conta não está disponível no momento.")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Excluir conta" })).not.toBeInTheDocument();
});

it("shows the API problem message when deletion fails", async () => {
  const user = userEvent.setup();
  renderPage({
    "/api/v1/security/delete-account": () =>
      problemResponse({
        code: "organization_admin_transfer_required",
        detail: "Transfira a administração ou exclua suas organizações antes de excluir a conta.",
        fields: {},
        request_id: "id",
        status: 409,
        title: "Conflito",
        type: "problem"
      })
  });
  await screen.findByRole("heading", { name: "Segurança" });

  await user.click(screen.getByRole("button", { name: "Excluir conta" }));
  await user.type(screen.getByLabelText("Confirme sua senha para excluir a conta"), "s3cret");
  await user.click(screen.getByRole("button", { name: "Excluir minha conta permanentemente" }));

  expect(await screen.findByText(/Transfira a administração/)).toBeVisible();
});

it("still lands on /login when logout fails after the account is deleted", async () => {
  const user = userEvent.setup();
  renderPage({
    "/api/v1/security/delete-account": () => new Response(null, { status: 204 }),
    "/api/v1/auth/logout": () => {
      throw new Error("offline");
    }
  });
  await screen.findByRole("heading", { name: "Segurança" });

  await user.click(screen.getByRole("button", { name: "Excluir conta" }));
  await user.type(screen.getByLabelText("Confirme sua senha para excluir a conta"), "s3cret");
  await user.click(screen.getByRole("button", { name: "Excluir minha conta permanentemente" }));

  await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/login"));
});

it("shows the fallback message on a network failure during deletion", async () => {
  const user = userEvent.setup();
  renderPage({
    "/api/v1/security/delete-account": () => {
      throw new Error("network");
    }
  });
  await screen.findByRole("heading", { name: "Segurança" });

  await user.click(screen.getByRole("button", { name: "Excluir conta" }));
  await user.type(screen.getByLabelText("Confirme sua senha para excluir a conta"), "x");
  await user.click(screen.getByRole("button", { name: "Excluir minha conta permanentemente" }));

  expect(await screen.findByText("Não foi possível excluir a conta.")).toBeVisible();
});

it("retries a failed security-summary request", async () => {
  const user = userEvent.setup();
  let attempts = 0;
  renderPage({
    "/api/v1/security": () => {
      attempts += 1;
      if (attempts === 1) throw new Error("offline");
      return jsonResponse({ ...summary, totp: { enabled: true, recovery_codes_remaining: 2 } });
    }
  });
  expect(await screen.findByText("Não foi possível carregar as configurações de segurança.")).toBeVisible();
  await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
  expect(await screen.findByText(/Recomendamos regenerar/)).toBeVisible();
  await waitFor(() => expect(screen.getByRole("heading", { name: "Segurança" })).toBeVisible());
});
