import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { AUTH_CONFIG, AUTHENTICATED_RESPONSE, jsonResponse, problemResponse } from "../../test/auth";
import { renderAuth } from "../../test/renderAuth";
import { MobileHandoffProvider } from "./mobileHandoff";
import { SignupPage } from "./SignupPage";

afterEach(() => {
  vi.unstubAllGlobals();
  sessionStorage.clear();
  delete window.dataLayer;
  delete window.turnstile;
  document.head.querySelectorAll("script[data-rentivo-gtm], script[data-rentivo-turnstile]").forEach((script) => script.remove());
});

describe("SignupPage", () => {
  it("preserves the signup form, Google option, Turnstile, focus, and title", async () => {
    renderAuth(<SignupPage />, { path: "/signup" });

    expect(await screen.findByLabelText("E-mail")).toHaveFocus();
    expect(screen.getByRole("heading", { level: 1, name: "Criar Conta" })).toBeVisible();
    expect(screen.getByText("Sua cobrança começa organizada.")).toBeVisible();
    expect(screen.getByText("Sua cobrança começa organizada.").tagName).toBe("P");
    expect(screen.getByLabelText("E-mail")).toHaveAttribute("autocomplete", "email");
    expect(screen.getByLabelText("E-mail")).toHaveAttribute("inputmode", "email");
    expect(screen.getByLabelText("Senha")).toHaveClass("input");
    expect(screen.getByLabelText("Senha")).toHaveAttribute("autocomplete", "new-password");
    expect(screen.getByLabelText("Confirmar Senha")).toHaveAttribute("type", "password");
    expect(screen.getByLabelText("Confirmar Senha")).toHaveAttribute(
      "autocomplete",
      "new-password"
    );
    expect(screen.getByRole("button", { name: "Criar Conta" })).toBeVisible();
    expect(screen.getByRole("link", { name: "Continuar com Google" })).toBeVisible();
    expect(screen.getByRole("link", { name: "Termos de Uso" })).toHaveAttribute(
      "href",
      "/terms"
    );
    expect(screen.getByRole("link", { name: "Política de Privacidade" })).toHaveAttribute(
      "href",
      "/privacy"
    );
    expect(screen.getByTestId("turnstile")).toBeVisible();
    expect(document.title).toBe("Criar Conta - Rentivo");
  });

  it("shows password guidance and lets each secret be reviewed", async () => {
    const user = userEvent.setup();
    renderAuth(<SignupPage />, { path: "/signup" });

    const password = await screen.findByLabelText("Senha");
    const confirmation = screen.getByLabelText("Confirmar Senha");
    await user.type(password, "correct-password");

    expect(screen.getByText("Senha preenchida")).toBeVisible();
    expect(screen.getByText("Repita a mesma senha")).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Mostrar senha" }));
    expect(password).toHaveAttribute("type", "text");
    expect(screen.getByRole("button", { name: "Ocultar senha" })).toHaveAttribute(
      "aria-pressed",
      "true"
    );

    await user.type(confirmation, "correct-password");
    expect(screen.getByText("Senhas iguais")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Mostrar confirmação da senha" }));
    expect(confirmation).toHaveAttribute("type", "text");
  });

  it("rejects mismatched passwords before calling the API", async () => {
    const user = userEvent.setup();
    const { fetchMock } = renderAuth(<SignupPage />, { path: "/signup" });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "password-one");
    await user.type(screen.getByLabelText("Confirmar Senha"), "password-two");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(screen.getByRole("alert")).toHaveTextContent("As senhas não coincidem.");
    expect(screen.getByLabelText("Confirmar Senha")).toHaveFocus();
    expect(screen.getByLabelText("Confirmar Senha")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Confirmar Senha")).toHaveAccessibleDescription(
      "As senhas não coincidem."
    );
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/v1/auth/signup")).toBe(false);
  });

  it("rejects an invalid confirmation before calling the signup API", async () => {
    const user = userEvent.setup();
    const { fetchMock } = renderAuth(<SignupPage />, { path: "/signup" });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "á".repeat(37));
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(screen.getByRole("alert")).toHaveTextContent("Senha muito longa.");
    expect(screen.getByLabelText("Confirmar Senha")).toHaveFocus();
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/v1/auth/signup")).toBe(false);
  });

  it("keeps an over-72-byte multibyte password local", async () => {
    const user = userEvent.setup();
    const { fetchMock } = renderAuth(<SignupPage />, { path: "/signup" });
    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "á".repeat(37));
    await user.type(screen.getByLabelText("Confirmar Senha"), "á".repeat(37));
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(screen.getByRole("alert")).toHaveTextContent("Senha muito longa.");
    expect(screen.getByLabelText("Senha")).toHaveFocus();
    expect(screen.getByLabelText("Senha")).toHaveAttribute("aria-invalid", "true");
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/v1/auth/signup")).toBe(false);
  });

  it("submits the generated signup contract and authenticates", async () => {
    const user = userEvent.setup();
    renderAuth(<SignupPage />, {
      handlers: {
        "/api/v1/auth/signup": (init) => {
          expect(JSON.parse(String(init?.body))).toEqual({
            confirm_password: "correct-password",
            credential_transport: "cookie",
            email: "user@example.com",
            password: "correct-password",
            turnstile_token: ""
          });
          return jsonResponse(AUTHENTICATED_RESPONSE);
        }
      },
      path: "/signup"
    });

    await user.type(await screen.findByLabelText("E-mail"), " user@example.com ");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/"));
  });

  it("returns to the mobile authorization page after signing up inside the app", async () => {
    const user = userEvent.setup();
    renderAuth(<SignupPage />, {
      handlers: {
        "/api/v1/auth/signup": () => jsonResponse(AUTHENTICATED_RESPONSE)
      },
      path: "/signup?mobile_state=native-state"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    await waitFor(() =>
      expect(screen.getByTestId("location")).toHaveTextContent(
        "/login?mobile_state=native-state"
      )
    );
    expect(screen.getByTestId("location")).not.toHaveTextContent("/billings");
  });

  it("uses app-safe chrome throughout a mobile signup handoff", async () => {
    renderAuth(
      <MobileHandoffProvider>
        <SignupPage />
      </MobileHandoffProvider>,
      { path: "/signup?mobile_state=native-state" }
    );

    expect(await screen.findByRole("heading", { name: "Criar Conta" })).toBeVisible();
    expect(screen.getByLabelText("Rentivo")).toHaveClass("signup-page__brand--static");
    expect(screen.queryByRole("link", { name: "Ir para a página inicial do Rentivo" }))
      .not.toBeInTheDocument();
    expect(screen.queryByRole("navigation", { name: "Links institucionais" }))
      .not.toBeInTheDocument();
    expect(screen.queryByRole("link", { name: "Continuar com Google" }))
      .not.toBeInTheDocument();
  });

  it("returns an existing session to the mobile authorization page", async () => {
    renderAuth(<SignupPage />, {
      path: "/signup?mobile_state=native-state",
      session: "authenticated"
    });

    await waitFor(() =>
      expect(screen.getByTestId("location")).toHaveTextContent(
        "/login?mobile_state=native-state"
      )
    );
    expect(screen.getByTestId("location")).not.toHaveTextContent("/billings");
  });

  it("sends an existing web session to the dashboard", async () => {
    renderAuth(<SignupPage />, { path: "/signup", session: "authenticated" });

    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/"));
  });

  it("shows duplicate-email errors, restores focus, and resets Turnstile", async () => {
    const user = userEvent.setup();
    const reset = vi.fn();
    window.turnstile = { render: vi.fn().mockReturnValue("widget"), reset };
    renderAuth(<SignupPage />, {
      handlers: {
        "/api/v1/auth/signup": () =>
          problemResponse({
            code: "email_already_registered",
            detail: "E-mail já cadastrado.",
            fields: {},
            request_id: "request-id",
            status: 400,
            title: "Requisição inválida",
            type: "https://rentivo.com.br/problems/email_already_registered"
          })
      },
      path: "/signup"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("E-mail já cadastrado.");
    expect(screen.getByLabelText("E-mail")).toHaveFocus();
    expect(screen.getByLabelText("E-mail")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("E-mail")).toHaveAccessibleDescription(
      "E-mail já cadastrado."
    );
    expect(reset).toHaveBeenCalledWith("widget");

    await user.type(screen.getByLabelText("E-mail"), ".br");
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("uses a field-level email error even when the API code is generic", async () => {
    const user = userEvent.setup();
    renderAuth(<SignupPage />, {
      handlers: {
        "/api/v1/auth/signup": () =>
          problemResponse({
            code: "validation_failed",
            detail: "Revise os campos.",
            fields: { email: "Use um endereço de e-mail válido." },
            request_id: "request-id",
            status: 422,
            title: "Dados inválidos",
            type: "https://rentivo.com.br/problems/validation_failed"
          })
      },
      path: "/signup"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Use um endereço de e-mail válido."
    );
    expect(screen.getByLabelText("E-mail")).toHaveFocus();
  });

  it("shows a form-level API error that is unrelated to the email field", async () => {
    const user = userEvent.setup();
    renderAuth(<SignupPage />, {
      handlers: {
        "/api/v1/auth/signup": () =>
          problemResponse({
            code: "turnstile_failed",
            detail: "Verificação de segurança falhou. Tente novamente.",
            fields: {},
            request_id: "request-id",
            status: 400,
            title: "Requisição inválida",
            type: "https://rentivo.com.br/problems/turnstile_failed"
          })
      },
      path: "/signup"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Verificação de segurança falhou. Tente novamente."
    );
  });

  it("recovers when signup configuration becomes available on retry", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    renderAuth(<SignupPage />, {
      configHandler: () => {
        attempts += 1;
        return attempts === 1
          ? new Response("unavailable", { status: 503 })
          : jsonResponse(AUTH_CONFIG);
      },
      path: "/signup"
    });

    expect(await screen.findByText("Não foi possível preparar o cadastro agora.")).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByLabelText("E-mail")).toBeVisible();
    expect(attempts).toBe(2);
  });

  it("shows the generic request error when no API response is available", async () => {
    const user = userEvent.setup();
    renderAuth(<SignupPage />, {
      handlers: {
        "/api/v1/auth/signup": () => {
          throw new TypeError("network unavailable");
        }
      },
      path: "/signup"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.type(screen.getByLabelText("Senha"), "correct-password");
    await user.type(screen.getByLabelText("Confirmar Senha"), "correct-password");
    await user.click(screen.getByRole("button", { name: "Criar Conta" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Não foi possível concluir a solicitação. Tente novamente."
    );
  });
});
