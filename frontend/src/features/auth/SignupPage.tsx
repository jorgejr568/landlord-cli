import { useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import {
  AuthConfigGate,
  AuthError,
  GoogleAuthOption,
  RentivoTitle,
  StandardAuthPanel,
  SubmitButton
} from "./AuthComponents";
import { postLoginPath, useAuth } from "./AuthProvider";
import { useMobileHandoff } from "./mobileHandoff";
import { Turnstile, type TurnstileHandle } from "./Turnstile";

type SignupRequest = components["schemas"]["SignupRequest"];

export function SignupPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  // Read from the URL, not from the sticky handoff marker: a stale state would
  // make LoginPage authorize a session the app is no longer waiting on.
  const mobileState = searchParams.get("mobile_state");
  const mobileLoginPath = mobileState
    ? `/login?mobile_state=${encodeURIComponent(mobileState)}`
    : "/login";
  const { withHandoff } = useMobileHandoff();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [turnstileToken, setTurnstileToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const emailRef = useRef<HTMLInputElement>(null);
  const turnstileRef = useRef<TurnstileHandle>(null);

  useEffect(() => {
    document.title = "Criar Conta - Rentivo";
  }, []);

  useEffect(() => {
    if (error) {
      emailRef.current?.focus();
    }
  }, [error]);

  useEffect(() => {
    if (auth.status === "authenticated" && auth.bootstrap) {
      navigate(mobileState ? mobileLoginPath : postLoginPath(auth.bootstrap), { replace: true });
    }
  }, [auth.bootstrap, auth.status, mobileLoginPath, mobileState, navigate]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    if (password !== confirmPassword) {
      setError("As senhas não coincidem.");
      return;
    }

    setLoading(true);
    const payload: SignupRequest = {
      confirm_password: confirmPassword,
      credential_transport: "cookie",
      email: email.trim(),
      password,
      turnstile_token: turnstileToken
    };
    try {
      const { data } = await apiRequest(
        apiClient.POST("/api/v1/auth/signup", { body: payload })
      );
      auth.authenticate(data);
      navigate(mobileState ? mobileLoginPath : postLoginPath(data.bootstrap));
    } catch (caught: unknown) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível concluir a solicitação. Tente novamente."
      );
      turnstileRef.current?.reset();
    } finally {
      setLoading(false);
    }
  }

  return (
    <AuthConfigGate>
      {(config) => (
        <StandardAuthPanel>
          <RentivoTitle />
          <AuthError message={error} />
          <form onSubmit={handleSubmit}>
            <div className="field">
              <label className="field-label" htmlFor="signup-email">
                E-mail
              </label>
              <input
                autoFocus
                className="field-input"
                id="signup-email"
                name="email"
                onChange={(event) => setEmail(event.target.value)}
                ref={emailRef}
                required
                type="email"
                value={email}
              />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="signup-password">
                Senha
              </label>
              <input
                className="field-input"
                id="signup-password"
                name="password"
                onChange={(event) => setPassword(event.target.value)}
                required
                type="password"
                value={password}
              />
            </div>
            <div className="field">
              <label className="field-label" htmlFor="confirm-password">
                Confirmar Senha
              </label>
              <input
                className="field-input"
                id="confirm-password"
                name="confirm_password"
                onChange={(event) => setConfirmPassword(event.target.value)}
                required
                type="password"
                value={confirmPassword}
              />
            </div>
            <Turnstile
              enabled={config.feature_flags.turnstile}
              onToken={setTurnstileToken}
              ref={turnstileRef}
              siteKey={config.feature_flags.turnstile_site_key}
            />
            <SubmitButton
              loading={loading}
              style={{ marginTop: "0.5rem", width: "100%" }}
            >
              Criar Conta
            </SubmitButton>
          </form>
          <GoogleAuthOption enabled={config.feature_flags.google_auth} />
          <p style={{ marginTop: "1rem", textAlign: "center" }}>
            Já tem conta? <Link to={withHandoff("/login")}>Entrar</Link>
          </p>
        </StandardAuthPanel>
      )}
    </AuthConfigGate>
  );
}
