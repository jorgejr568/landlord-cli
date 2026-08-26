import { fireEvent, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import { AUTH_CONFIG, jsonResponse, problemResponse } from "../../test/auth";
import { renderAuth } from "../../test/renderAuth";
import { ForgotPasswordPage } from "./ForgotPasswordPage";
import { MobileHandoffProvider } from "./mobileHandoff";

afterEach(() => {
  vi.unstubAllGlobals();
  sessionStorage.clear();
  delete window.dataLayer;
  delete window.turnstile;
  document.head.querySelectorAll("script[data-rentivo-gtm], script[data-rentivo-turnstile]").forEach((script) => script.remove());
});

describe("ForgotPasswordPage", () => {
  it("presents one accessible recovery workspace with privacy-safe guidance", async () => {
    renderAuth(<ForgotPasswordPage />, { path: "/forgot-password" });

    expect(
      await screen.findByText(
        "Digite o e-mail usado no Rentivo. Se houver uma conta, enviaremos um link seguro."
      )
    ).toBeVisible();
    expect(screen.getByRole("heading", { level: 1, name: "Recupere seu acesso" })).toBeVisible();
    expect(screen.getByRole("heading", { level: 2, name: "O que acontece agora" })).toBeVisible();
    const email = screen.getByLabelText("E-mail");
    await waitFor(() => expect(email).toHaveFocus());
    expect(email).toHaveAttribute("autocomplete", "email");
    expect(email).toHaveAttribute("inputmode", "email");
    expect(email).toHaveAttribute("spellcheck", "false");
    expect(screen.getByRole("button", { name: "Enviar link" })).toBeVisible();
    expect(screen.getByTestId("turnstile")).toBeVisible();
    expect(screen.getByRole("link", { name: "Voltar para o login" })).toHaveAttribute(
      "href",
      "/login"
    );
    expect(document.title).toBe("Esqueci minha senha - Rentivo");
  });

  it("does not open the keyboard by stealing focus on a narrow screen", async () => {
    vi.stubGlobal("matchMedia", vi.fn().mockReturnValue({ matches: true }));

    renderAuth(<ForgotPasswordPage />, { path: "/forgot-password" });

    const email = await screen.findByLabelText("E-mail");
    expect(email).not.toHaveFocus();
  });

  it("uses app-safe chrome throughout a mobile recovery handoff", async () => {
    renderAuth(
      <MobileHandoffProvider>
        <ForgotPasswordPage />
      </MobileHandoffProvider>,
      { path: "/forgot-password?mobile_state=native-state" }
    );

    expect(await screen.findByRole("heading", { name: "Recupere seu acesso" })).toBeVisible();
    expect(document.querySelector(".forgot-password-page__brand--static")).toBeVisible();
    expect(screen.queryByRole("link", { name: "Ir para a página inicial do Rentivo" }))
      .not.toBeInTheDocument();
    expect(screen.queryByRole("navigation", { name: "Links institucionais" }))
      .not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Voltar para o login" })).toHaveAttribute(
      "href",
      "/login?mobile_state=native-state"
    );
  });

  it("announces the pending request and prevents a duplicate submission", async () => {
    const user = userEvent.setup();
    let resolveRequest!: (response: Response) => void;
    const pendingRequest = new Promise<Response>((resolve) => {
      resolveRequest = resolve;
    });
    renderAuth(<ForgotPasswordPage />, {
      handlers: {
        "/api/v1/auth/password/forgot": () => pendingRequest
      },
      path: "/forgot-password"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.click(screen.getByRole("button", { name: "Enviar link" }));

    const submit = screen.getByRole("button", { name: "Enviando link…" });
    expect(submit).toBeDisabled();
    expect(submit).toHaveAttribute("aria-busy", "true");
    fireEvent.submit(submit.closest("form")!);

    resolveRequest(
      jsonResponse(
        {
          analytics_events: [],
          status: "accepted"
        },
        202
      )
    );
    expect(await screen.findByRole("heading", { name: "Confira sua caixa de entrada" })).toBeVisible();
  });

  it("recovers when authentication configuration becomes available on retry", async () => {
    const user = userEvent.setup();
    let attempts = 0;
    renderAuth(<ForgotPasswordPage />, {
      configHandler: () => {
        attempts += 1;
        return attempts === 1
          ? new Response("unavailable", { status: 503 })
          : jsonResponse(AUTH_CONFIG);
      },
      path: "/forgot-password"
    });

    expect(await screen.findByRole("heading", { name: "Recuperação indisponível" })).toBeVisible();
    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));

    expect(await screen.findByRole("heading", { name: "Recupere seu acesso" })).toBeVisible();
    expect(attempts).toBe(2);
  });

  it("uses the generated contract and shows the same non-enumerating success state", async () => {
    const user = userEvent.setup();
    renderAuth(<ForgotPasswordPage />, {
      handlers: {
        "/api/v1/auth/password/forgot": (init) => {
          expect(JSON.parse(String(init?.body))).toEqual({
            email: "user@example.com",
            turnstile_token: ""
          });
          return jsonResponse(
            {
              analytics_events: [
                { event: "rentivo_password_reset_requested", reason: null, via: null }
              ],
              status: "accepted"
            },
            202
          );
        }
      },
      path: "/forgot-password"
    });

    await user.type(await screen.findByLabelText("E-mail"), " USER@EXAMPLE.COM ");
    await user.click(screen.getByRole("button", { name: "Enviar link" }));

    expect(
      await screen.findByText(
        "Se houver uma conta com esse e-mail, você receberá as instruções em instantes."
      )
    ).toHaveAttribute("role", "status");
    expect(screen.getByRole("heading", { name: "Confira sua caixa de entrada" })).toHaveFocus();
    expect(screen.queryByRole("button", { name: "Enviar link" })).not.toBeInTheDocument();
    expect(window.dataLayer?.at(-1)).toEqual({
      event: "rentivo_password_reset_requested",
      reason: null,
      via: null
    });
  });

  it("lets the user restart recovery with an empty focused email field", async () => {
    const user = userEvent.setup();
    renderAuth(<ForgotPasswordPage />, {
      handlers: {
        "/api/v1/auth/password/forgot": () =>
          jsonResponse({ analytics_events: [], status: "accepted" }, 202)
      },
      path: "/forgot-password"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.click(screen.getByRole("button", { name: "Enviar link" }));
    await user.click(await screen.findByRole("button", { name: "Usar outro e-mail" }));

    expect(screen.getByLabelText("E-mail")).toHaveValue("");
    expect(screen.getByLabelText("E-mail")).toHaveFocus();
  });

  it("shows security errors, restores focus, and resets Turnstile", async () => {
    const user = userEvent.setup();
    const reset = vi.fn();
    window.turnstile = { render: vi.fn().mockReturnValue("widget"), reset };
    renderAuth(<ForgotPasswordPage />, {
      handlers: {
        "/api/v1/auth/password/forgot": () =>
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
      path: "/forgot-password"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.click(screen.getByRole("button", { name: "Enviar link" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Verificação de segurança falhou. Tente novamente."
    );
    expect(screen.getByLabelText("E-mail")).toHaveFocus();
    expect(screen.getByLabelText("E-mail")).toHaveAttribute("aria-invalid", "true");
    expect(reset).toHaveBeenCalledWith("widget");
  });

  it("uses the generic message when the request fails before an API response", async () => {
    const user = userEvent.setup();
    renderAuth(<ForgotPasswordPage />, {
      handlers: {
        "/api/v1/auth/password/forgot": () => {
          throw new TypeError("network unavailable");
        }
      },
      path: "/forgot-password"
    });

    await user.type(await screen.findByLabelText("E-mail"), "user@example.com");
    await user.click(screen.getByRole("button", { name: "Enviar link" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Não foi possível concluir a solicitação. Tente novamente."
    );
  });

  it("redirects an existing authenticated session", async () => {
    renderAuth(<ForgotPasswordPage />, {
      path: "/forgot-password",
      session: "authenticated"
    });

    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/"));
  });
});
