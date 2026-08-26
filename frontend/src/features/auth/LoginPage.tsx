import {
  ArrowRight,
  Check,
  Eye,
  EyeOff,
  FileCheck2,
  LockKeyhole,
  ReceiptText,
  WalletCards
} from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { passwordValidationError } from "../../forms/validators";
import {
  AuthError,
  GoogleAuthOption,
  SubmitButton
} from "./AuthComponents";
import { postLoginPath, useAuth } from "./AuthProvider";
import { pushAnalyticsFromResponse } from "./analytics";
import { saveMfaChallenge, takeAuthFlash } from "./authStorage";
import { openMobileAuthorizationCallback } from "./mobileAuthorization";
import { useMobileHandoff } from "./mobileHandoff";
import { Turnstile, type TurnstileHandle } from "./Turnstile";
import "./LoginPage.css";

type LoginRequest = components["schemas"]["LoginRequest"];

const GOOGLE_ERROR = "Não foi possível entrar com o Google. Tente novamente.";

export function LoginPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  // Read from the URL, not from the sticky handoff marker: this value drives
  // the mobile authorization request, and a stale state would authorize a
  // session the app is no longer waiting on.
  const mobileState = searchParams.get("mobile_state");
  const { isHandoff, withHandoff } = useMobileHandoff();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState("");
  const [error, setError] = useState<string | null>(() =>
    searchParams.get("error") === "google_auth_failed" ? GOOGLE_ERROR : null
  );
  const [flash] = useState(takeAuthFlash);
  const [loading, setLoading] = useState(false);
  const [mobileCallbackURL, setMobileCallbackURL] = useState<string | null>(null);
  const emailRef = useRef<HTMLInputElement>(null);
  const turnstileRef = useRef<TurnstileHandle>(null);
  const mobileAuthorizationStarted = useRef(false);
  const mobileCallbackOpened = useRef(false);

  const completeMobileAuthorization = useCallback(async (state: string) => {
    const { data: authorization } = await apiRequest(
      apiClient.POST("/api/v1/auth/mobile/authorize", { body: { state } })
    );
    setMobileCallbackURL(
      `rentivo://auth/callback?code=${encodeURIComponent(authorization.authorization_code)}&state=${encodeURIComponent(authorization.state)}`
    );
  }, []);

  const openMobileCallback = useCallback(() => {
    if (!mobileCallbackURL || mobileCallbackOpened.current) {
      return;
    }
    mobileCallbackOpened.current = true;
    openMobileAuthorizationCallback(mobileCallbackURL);
  }, [mobileCallbackURL]);

  useEffect(() => {
    document.title = mobileCallbackURL ? "Voltar para o app - Rentivo" : "Entrar - Rentivo";
  }, [mobileCallbackURL]);

  useEffect(() => {
    if (error) {
      emailRef.current?.focus();
    }
  }, [error]);

  useEffect(() => {
    if (!mobileState && auth.status === "authenticated" && auth.bootstrap) {
      navigate(postLoginPath(auth.bootstrap), { replace: true });
    }
  }, [auth.bootstrap, auth.status, mobileState, navigate]);

  useEffect(() => {
    if (!mobileState || auth.status !== "authenticated" || mobileAuthorizationStarted.current) {
      return;
    }
    mobileAuthorizationStarted.current = true;
    void completeMobileAuthorization(mobileState).catch(() => {
      setError("Não foi possível concluir a autorização no aplicativo. Tente novamente.");
    });
  }, [auth.status, completeMobileAuthorization, mobileState]);

  useEffect(() => {
    if (!mobileCallbackURL) {
      return;
    }
    const timer = window.setTimeout(openMobileCallback, 1_000);
    return () => window.clearTimeout(timer);
  }, [mobileCallbackURL, openMobileCallback]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    const passwordError = passwordValidationError(password);
    if (passwordError) {
      setError(passwordError);
      return;
    }
    setLoading(true);
    const payload: LoginRequest = {
      credential_transport: "cookie",
      email: email.trim(),
      password,
      turnstile_token: turnstileToken
    };
    try {
      const { data } = await apiRequest(
        apiClient.POST("/api/v1/auth/login", { body: payload })
      );
      if (data.status === "mfa_required") {
        saveMfaChallenge({ challengeId: data.challenge_id, methods: data.methods });
        const mfaParams = new URLSearchParams({ challenge: data.challenge_id });
        if (mobileState) {
          mfaParams.set("mobile_state", mobileState);
        }
        navigate(`/mfa-verify?${mfaParams.toString()}`);
        return;
      }
      if (mobileState) {
        await completeMobileAuthorization(mobileState);
        return;
      }
      auth.authenticate(data);
      navigate(postLoginPath(data.bootstrap));
    } catch (caught: unknown) {
      if (caught instanceof ApiError) {
        pushAnalyticsFromResponse(caught.response);
        setError(caught.message);
      } else {
        setError("Não foi possível concluir a solicitação. Tente novamente.");
      }
      turnstileRef.current?.reset();
    } finally {
      setLoading(false);
    }
  }

  if (mobileCallbackURL) {
    return (
      <LoginScaffold isHandoff={isHandoff}>
        <MobileAuthorizationStatus onReturnToApp={openMobileCallback} />
      </LoginScaffold>
    );
  }

  if (auth.configStatus === "loading") {
    return (
      <LoginScaffold isHandoff={isHandoff}>
        <div className="login-page__loading" role="status">
          <span className="sr-only">Carregando opções de acesso…</span>
          <span aria-hidden="true" className="login-page__skeleton login-page__skeleton--title" />
          <span aria-hidden="true" className="login-page__skeleton login-page__skeleton--copy" />
          <span aria-hidden="true" className="login-page__skeleton login-page__skeleton--field" />
          <span aria-hidden="true" className="login-page__skeleton login-page__skeleton--field" />
          <span aria-hidden="true" className="login-page__skeleton login-page__skeleton--button" />
        </div>
      </LoginScaffold>
    );
  }

  if (auth.configStatus === "error" || !auth.config) {
    return (
      <LoginScaffold isHandoff={isHandoff}>
        <div className="login-page__header">
          <h1>Entrar</h1>
          <p>Não foi possível preparar esta tela agora.</p>
        </div>
        <AuthError message="Não foi possível carregar as opções de autenticação. Tente novamente." />
        <button className="btn btn--primary btn--lg" onClick={auth.retryConfig} type="button">
          Tentar novamente
        </button>
      </LoginScaffold>
    );
  }

  return (
    <LoginScaffold isHandoff={isHandoff}>
      <div className="login-page__header">
        <h1 id="login-title">Entrar</h1>
        <p>Acesse cobranças, faturas e pagamentos de um só lugar.</p>
      </div>
      {flash ? (
        <div className="toast toast--success login-page__feedback" role="status">
          {flash}
        </div>
      ) : null}
      <AuthError message={error} />
      <form aria-labelledby="login-title" className="login-page__form" onSubmit={handleSubmit}>
        <div className="field">
          <label className="field__label" htmlFor="email">
            E-mail
          </label>
          <input
            autoCapitalize="none"
            autoComplete="email"
            autoFocus
            className="input"
            id="email"
            inputMode="email"
            name="email"
            onChange={(event) => setEmail(event.target.value)}
            ref={emailRef}
            required
            spellCheck={false}
            type="email"
            value={email}
          />
        </div>
        <div className="field">
          <label className="field__label" htmlFor="password">
            Senha
          </label>
          <div className="login-page__password">
            <input
              autoComplete="current-password"
              className="input"
              id="password"
              name="password"
              onChange={(event) => setPassword(event.target.value)}
              required
              type={showPassword ? "text" : "password"}
              value={password}
            />
            <button
              aria-controls="password"
              aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
              aria-pressed={showPassword}
              className="login-page__password-toggle"
              onClick={() => setShowPassword((visible) => !visible)}
              type="button"
            >
              {showPassword ? <EyeOff aria-hidden="true" size={18} /> : <Eye aria-hidden="true" size={18} />}
            </button>
          </div>
          <Link className="login-page__forgot" to={withHandoff("/forgot-password")}>
            Esqueceu sua senha?
          </Link>
        </div>
        <Turnstile
          enabled={auth.config.feature_flags.turnstile}
          onToken={setTurnstileToken}
          ref={turnstileRef}
          siteKey={auth.config.feature_flags.turnstile_site_key}
        />
        <SubmitButton
          className="btn btn--primary btn--block btn--lg login-page__submit"
          loading={loading}
        >
          {loading ? "Entrando…" : "Entrar"}
          {!loading ? <ArrowRight aria-hidden="true" size={18} /> : null}
        </SubmitButton>
      </form>
      <div className="login-page__social">
        <GoogleAuthOption enabled={auth.config.feature_flags.google_auth} />
      </div>
      <p className="login-page__signup">
        Ainda não usa o Rentivo? <Link to={withHandoff("/signup")}>Criar conta</Link>
      </p>
    </LoginScaffold>
  );
}

function MobileAuthorizationStatus({ onReturnToApp }: { onReturnToApp: () => void }) {
  return (
    <div className="login-page__complete">
      <span aria-hidden="true" className="login-page__complete-mark"><Check size={28} /></span>
      <h1>Tudo pronto</h1>
      <p>
        Você já pode continuar no app Rentivo. Esta página voltará ao aplicativo automaticamente.
      </p>
      <button className="btn btn--primary btn--block btn--lg" onClick={onReturnToApp} type="button">
        Voltar para o app agora
      </button>
    </div>
  );
}

function LoginScaffold({ children, isHandoff }: { children: ReactNode; isHandoff: boolean }) {
  return (
    <section aria-label="Acesso ao Rentivo" className="login-page">
      {!isHandoff ? (
        <Link aria-label="Ir para a página inicial do Rentivo" className="login-page__brand" to="/">
          <span aria-hidden="true" className="login-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </Link>
      ) : (
        <div aria-label="Rentivo" className="login-page__brand login-page__brand--static">
          <span aria-hidden="true" className="login-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </div>
      )}
      <div className="login-page__shell">
        <div className="login-page__auth">{children}</div>
        <aside className="login-page__context">
          <div>
            <span className="login-page__eyebrow">Gestão de cobranças</span>
            <h2>Do acordo ao recebido, sem perder o fio.</h2>
            <p>Organize cobranças, gere faturas em PDF e acompanhe pagamentos com clareza.</p>
          </div>
          <ol aria-label="Fluxo de cobrança no Rentivo" className="login-page__flow">
            <li>
              <FileCheck2 aria-hidden="true" size={19} />
              <span><strong>Cobrança configurada</strong><small>Valores, vencimentos e destinatários em ordem.</small></span>
            </li>
            <li>
              <ReceiptText aria-hidden="true" size={19} />
              <span><strong>Fatura pronta</strong><small>PDF e PIX no mesmo fluxo.</small></span>
            </li>
            <li>
              <WalletCards aria-hidden="true" size={19} />
              <span><strong>Pagamento acompanhado</strong><small>Status e recibos fáceis de consultar.</small></span>
            </li>
          </ol>
          <p className="login-page__security-note">
            <LockKeyhole aria-hidden="true" size={17} />
            Autenticação em duas etapas disponível para reforçar o acesso.
          </p>
        </aside>
      </div>
      {!isHandoff ? (
        <nav aria-label="Links institucionais" className="login-page__footer">
          <Link to="/privacy">Privacidade</Link>
          <Link to="/terms">Termos</Link>
          <Link to="/support">Ajuda</Link>
        </nav>
      ) : null}
    </section>
  );
}
