import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";

import { AUTH_CONFIG } from "../../test/auth";

const { useAuthMock } = vi.hoisted(() => ({ useAuthMock: vi.fn() }));

vi.mock("./AuthProvider", () => ({
  useAuth: () => useAuthMock()
}));

import {
  AuthConfigGate,
  AuthError,
  GoogleAuthLink,
  GoogleAuthOption,
  LoginAuthHeader,
  RentivoTitle,
  StandardAuthPanel,
  SubmitButton
} from "./AuthComponents";
import { MobileHandoffProvider } from "./mobileHandoff";

afterEach(() => {
  sessionStorage.clear();
  useAuthMock.mockReset();
});

describe("authentication components", () => {
  it("preserves the standard legacy panel and Rentivo title", () => {
    render(
      <StandardAuthPanel>
        <RentivoTitle />
        <p>Conteúdo</p>
      </StandardAuthPanel>
    );

    // jsdom resolves rem against the 16px root font size, so 2rem computes to 32px.
    expect(screen.getByText("Conteúdo").closest(".panel-body")).toHaveStyle({
      padding: "32px"
    });
    expect(screen.getByRole("heading", { name: /Ren\s*tivo/ })).toHaveClass("login-title");
  });

  it("preserves the dedicated login header", () => {
    render(<LoginAuthHeader />);

    expect(screen.getByText("R")).toHaveClass("auth-mark");
    expect(screen.getByRole("heading", { name: /Entrar no rent\s*ivo/ })).toBeVisible();
    expect(screen.getByText("Bem-vindo de volta.")).toBeVisible();
  });

  it("renders errors only when present", () => {
    const view = render(<AuthError message={null} />);
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();

    view.rerender(<AuthError message="E-mail ou senha inválidos." />);
    expect(screen.getByRole("alert")).toHaveTextContent("E-mail ou senha inválidos.");
  });

  it("keeps submit labels stable while exposing loading state", () => {
    const view = render(<SubmitButton loading={false}>Entrar</SubmitButton>);
    expect(screen.getByRole("button", { name: "Entrar" })).toBeEnabled();

    view.rerender(<SubmitButton loading>Entrar</SubmitButton>);
    expect(screen.getByRole("button", { name: "Entrar" })).toBeDisabled();
    expect(screen.getByRole("button")).toHaveAttribute("aria-busy", "true");
  });

  it("uses the Google API start endpoint and legacy button copy", () => {
    render(<GoogleAuthLink />);

    expect(screen.getByRole("link", { name: "Continuar com Google" })).toHaveAttribute(
      "href",
      "/api/v1/auth/google/start"
    );
    expect(document.querySelector(".google-icon")).toBeInTheDocument();
  });

  it("shows the Google option with its separator when the flag is on", () => {
    render(
      <MemoryRouter initialEntries={["/login"]}>
        <MobileHandoffProvider>
          <GoogleAuthOption enabled />
        </MobileHandoffProvider>
      </MemoryRouter>
    );

    expect(screen.getByRole("link", { name: "Continuar com Google" })).toBeVisible();
    expect(screen.getByText("ou")).toBeVisible();
  });

  it("hides the Google option, separator included, when the flag is off", () => {
    render(
      <MemoryRouter initialEntries={["/login"]}>
        <MobileHandoffProvider>
          <GoogleAuthOption enabled={false} />
        </MobileHandoffProvider>
      </MemoryRouter>
    );

    expect(screen.queryByRole("link", { name: "Continuar com Google" })).not.toBeInTheDocument();
    expect(screen.queryByText("ou")).not.toBeInTheDocument();
  });

  it("hides the Google option inside the iOS handoff even when the flag is on", () => {
    // App Store guideline 4.8: a third-party login service reachable from
    // inside the app requires an equivalent alternative. Rentivo offers none,
    // so the app must expose only its own email and password login.
    render(
      <MemoryRouter initialEntries={["/login?mobile_state=native-state"]}>
        <MobileHandoffProvider>
          <GoogleAuthOption enabled />
        </MobileHandoffProvider>
      </MemoryRouter>
    );

    expect(screen.queryByRole("link", { name: "Continuar com Google" })).not.toBeInTheDocument();
    expect(screen.queryByText("ou")).not.toBeInTheDocument();
  });

  it("keeps authentication forms out of the tree while configuration is loading", () => {
    useAuthMock.mockReturnValue({
      config: null,
      configStatus: "loading",
      retryConfig: vi.fn()
    });

    render(<AuthConfigGate>{() => <p>Formulário de acesso</p>}</AuthConfigGate>);

    expect(screen.getByRole("status")).toHaveTextContent("Carregando…");
    expect(screen.queryByText("Formulário de acesso")).not.toBeInTheDocument();
  });

  it("lets the user retry when authentication configuration fails", async () => {
    const retryConfig = vi.fn();
    useAuthMock.mockReturnValue({ config: null, configStatus: "error", retryConfig });
    const user = userEvent.setup();

    render(<AuthConfigGate>{() => <p>Formulário de acesso</p>}</AuthConfigGate>);

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Não foi possível carregar as opções de autenticação. Tente novamente."
    );
    await user.click(screen.getByRole("button", { name: "Tentar novamente" }));
    expect(retryConfig).toHaveBeenCalledOnce();
  });

  it("renders the form with the server configuration when it is ready", () => {
    useAuthMock.mockReturnValue({
      config: AUTH_CONFIG,
      configStatus: "ready",
      retryConfig: vi.fn()
    });

    render(
      <AuthConfigGate>
        {(config) => <p>{config.feature_flags.google_auth ? "Google disponível" : "Só e-mail"}</p>}
      </AuthConfigGate>
    );

    expect(screen.getByText("Google disponível")).toBeVisible();
  });
});
