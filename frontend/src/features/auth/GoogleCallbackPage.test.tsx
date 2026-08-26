import { screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { AUTHENTICATED_RESPONSE, jsonResponse, problemResponse } from "../../test/auth";
import { renderAuth } from "../../test/renderAuth";
import { loadMfaChallenge } from "./authStorage";
import { GoogleCallbackPage } from "./GoogleCallbackPage";
import { MobileHandoffProvider } from "./mobileHandoff";

afterEach(() => {
  vi.unstubAllGlobals();
  sessionStorage.clear();
  delete window.dataLayer;
  document.head.querySelectorAll("script[data-rentivo-gtm]").forEach((script) => script.remove());
});

describe("GoogleCallbackPage", () => {
  it("forwards the callback query as JSON and completes authentication", async () => {
    let callbackCalls = 0;
    renderAuth(<GoogleCallbackPage />, {
      handlers: {
        "/api/v1/auth/google/callback?code=auth-code&state=oauth-state": (init) => {
          callbackCalls += 1;
          expect(new Headers(init?.headers).get("Accept")).toBe("application/json");
          expect(init?.credentials).toBe("same-origin");
          return jsonResponse(AUTHENTICATED_RESPONSE);
        }
      },
      path: "/auth/google/callback?code=auth-code&state=oauth-state"
    });

    const progressHeading = screen.getByRole("heading", { name: "Confirmando seu acesso" });
    expect(progressHeading.closest('[role="status"]')).toHaveAttribute("aria-live", "polite");
    expect(screen.getByRole("list", { name: "Progresso do acesso" })).toHaveTextContent(
      "GoogleVerificaçãoRentivo"
    );
    expect(await screen.findByRole("heading", { name: "Acesso confirmado" })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByTestId("location")).toHaveTextContent("/billings/"));
    expect(callbackCalls).toBe(1);
    expect(document.title).toBe("Acesso confirmado - Rentivo");
  });

  it("stores the returned MFA challenge and opens verification", async () => {
    renderAuth(<GoogleCallbackPage />, {
      handlers: {
        "/api/v1/auth/google/callback?code=auth-code&state=oauth-state": () =>
          jsonResponse(
            {
              challenge_id: "google/challenge",
              methods: ["totp", "passkey"],
              status: "mfa_required"
            },
            202
          )
      },
      path: "/auth/google/callback?code=auth-code&state=oauth-state"
    });

    await waitFor(() =>
      expect(screen.getByTestId("location")).toHaveTextContent(
        "/mfa-verify?challenge=google%2Fchallenge"
      )
    );
    expect(loadMfaChallenge("google/challenge")).toEqual({
      challengeId: "google/challenge",
      methods: ["totp", "passkey"]
    });
  });

  it("returns callback failures to the legacy login error URL", async () => {
    renderAuth(<GoogleCallbackPage />, {
      handlers: {
        "/api/v1/auth/google/callback?error=access_denied&state=oauth-state": () =>
          problemResponse({
            code: "google_auth_failed",
            detail: "Não foi possível entrar com o Google. Tente novamente.",
            fields: {},
            request_id: "request-id",
            status: 401,
            title: "Não autenticado",
            type: "https://rentivo.com.br/problems/google_auth_failed"
          })
      },
      path: "/auth/google/callback?error=access_denied&state=oauth-state"
    });

    await waitFor(() =>
      expect(screen.getByTestId("location")).toHaveTextContent("/login?error=google_auth_failed")
    );
  });

  it("uses the same failure path for an unavailable callback request", async () => {
    renderAuth(<GoogleCallbackPage />, {
      handlers: {
        "/api/v1/auth/google/callback?code=auth-code&state=oauth-state": () => {
          throw new TypeError("network unavailable");
        }
      },
      path: "/auth/google/callback?code=auth-code&state=oauth-state"
    });

    await waitFor(() =>
      expect(screen.getByTestId("location")).toHaveTextContent("/login?error=google_auth_failed")
    );
  });

  it("ignores a callback response that arrives after the handoff page closes", async () => {
    let resolveCallback!: (response: Response) => void;
    const callback = new Promise<Response>((resolve) => {
      resolveCallback = resolve;
    });
    const view = renderAuth(<GoogleCallbackPage />, {
      handlers: {
        "/api/v1/auth/google/callback?code=auth-code&state=oauth-state": () => callback
      },
      path: "/auth/google/callback?code=auth-code&state=oauth-state"
    });

    expect(screen.getByRole("heading", { name: "Confirmando seu acesso" })).toBeVisible();
    view.unmount();
    resolveCallback(jsonResponse(AUTHENTICATED_RESPONSE));
    await callback;

    expect(sessionStorage.getItem("rentivo.auth.mfa_challenge")).toBeNull();
  });

  it("ignores a callback failure that arrives after the handoff page closes", async () => {
    let rejectCallback!: (error: Error) => void;
    const callback = new Promise<Response>((_resolve, reject) => {
      rejectCallback = reject;
    });
    const view = renderAuth(<GoogleCallbackPage />, {
      handlers: {
        "/api/v1/auth/google/callback?code=auth-code&state=oauth-state": () => callback
      },
      path: "/auth/google/callback?code=auth-code&state=oauth-state"
    });

    expect(screen.getByRole("heading", { name: "Confirmando seu acesso" })).toBeVisible();
    view.unmount();
    rejectCallback(new TypeError("network unavailable"));
    await callback.catch(() => undefined);

    expect(sessionStorage.getItem("rentivo.auth.mfa_challenge")).toBeNull();
  });

  it("does not send an incomplete callback and gives the user safe recovery actions", () => {
    const { fetchMock } = renderAuth(<GoogleCallbackPage />, {
      path: "/auth/google/callback?code=auth-code"
    });

    expect(screen.getByRole("heading", { name: "Este retorno não é válido" })).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "Inicie o acesso com Google novamente para criar uma conexão segura."
    );
    expect(screen.getByRole("alert")).toHaveFocus();
    expect(screen.getByRole("link", { name: "Tentar com Google novamente" })).toHaveAttribute(
      "href",
      "/api/v1/auth/google/start"
    );
    expect(screen.getByRole("link", { name: "Voltar para entrar" })).toHaveAttribute(
      "href",
      "/login?error=google_auth_failed"
    );
    expect(
      fetchMock.mock.calls.some(([input]) => String(input).startsWith("/api/v1/auth/google/callback"))
    ).toBe(false);
  });

  it("keeps Google recovery hidden and threads return state inside the mobile handoff", () => {
    renderAuth(
      <MobileHandoffProvider>
        <GoogleCallbackPage />
      </MobileHandoffProvider>,
      { path: "/auth/google/callback?mobile_state=native%2Fstate" }
    );

    expect(
      screen.queryByRole("link", { name: "Tentar com Google novamente" })
    ).not.toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Voltar para entrar" })).toHaveAttribute(
      "href",
      "/login?error=google_auth_failed&mobile_state=native%2Fstate"
    );
  });
});
