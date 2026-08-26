import {
  ArrowLeft,
  ArrowRight,
  Check,
  KeyRound,
  Mail,
  ShieldCheck
} from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useNavigate } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { AuthError, SubmitButton } from "./AuthComponents";
import { postLoginPath, useAuth } from "./AuthProvider";
import { pushAnalyticsEvent } from "./analytics";
import { useMobileHandoff } from "./mobileHandoff";
import { Turnstile, type TurnstileHandle } from "./Turnstile";
import "./ForgotPasswordPage.css";

type PasswordForgotRequest = components["schemas"]["PasswordForgotRequest"];

export function ForgotPasswordPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const { isHandoff, withHandoff } = useMobileHandoff();
  const [email, setEmail] = useState("");
  const [turnstileToken, setTurnstileToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [sent, setSent] = useState(false);
  const emailRef = useRef<HTMLInputElement>(null);
  const successHeadingRef = useRef<HTMLHeadingElement>(null);
  const turnstileRef = useRef<TurnstileHandle>(null);

  useEffect(() => {
    document.title = "Esqueci minha senha - Rentivo";
  }, []);

  useEffect(() => {
    if (error) {
      emailRef.current?.focus();
    }
  }, [error]);

  useEffect(() => {
    if (sent) {
      successHeadingRef.current?.focus();
    }
  }, [sent]);

  useEffect(() => {
    if (
      auth.configStatus !== "ready" ||
      sent ||
      window.matchMedia?.("(max-width: 760px)").matches
    ) {
      return;
    }
    emailRef.current?.focus();
  }, [auth.configStatus, sent]);

  useEffect(() => {
    if (auth.status === "authenticated" && auth.bootstrap) {
      navigate(postLoginPath(auth.bootstrap), { replace: true });
    }
  }, [auth.bootstrap, auth.status, navigate]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading) {
      return;
    }
    setError(null);
    setLoading(true);
    const payload: PasswordForgotRequest = {
      email: email.trim().toLowerCase(),
      turnstile_token: turnstileToken
    };
    try {
      const { data } = await apiRequest(
        apiClient.POST("/api/v1/auth/password/forgot", { body: payload })
      );
      data.analytics_events.forEach((analyticsEvent) =>
        pushAnalyticsEvent({ ...analyticsEvent })
      );
      setSent(true);
    } catch (caught: unknown) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : "Não foi possível concluir a solicitação. Tente novamente."
      );
      setTurnstileToken("");
      turnstileRef.current?.reset();
    } finally {
      setLoading(false);
    }
  }

  function restartRecovery() {
    setEmail("");
    setError(null);
    setSent(false);
    setTurnstileToken("");
    turnstileRef.current?.reset();
    window.requestAnimationFrame(() => emailRef.current?.focus());
  }

  if (auth.configStatus === "loading") {
    return (
      <ForgotPasswordScaffold isHandoff={isHandoff}>
        <div className="forgot-password-page__loading" role="status">
          <span className="sr-only">Carregando recuperação de senha…</span>
          <span aria-hidden="true" className="forgot-password-page__skeleton forgot-password-page__skeleton--title" />
          <span aria-hidden="true" className="forgot-password-page__skeleton forgot-password-page__skeleton--copy" />
          <span aria-hidden="true" className="forgot-password-page__skeleton" />
          <span aria-hidden="true" className="forgot-password-page__skeleton forgot-password-page__skeleton--button" />
        </div>
      </ForgotPasswordScaffold>
    );
  }

  if (auth.configStatus === "error" || !auth.config) {
    return (
      <ForgotPasswordScaffold isHandoff={isHandoff}>
        <header className="forgot-password-page__header">
          <h1>Recuperação indisponível</h1>
          <p>Não foi possível preparar esta etapa agora.</p>
        </header>
        <AuthError message="Não foi possível carregar as opções de autenticação. Tente novamente." />
        <button className="btn btn--primary btn--lg" onClick={auth.retryConfig} type="button">
          Tentar novamente
        </button>
      </ForgotPasswordScaffold>
    );
  }

  return (
    <ForgotPasswordScaffold isHandoff={isHandoff}>
      {sent ? (
        <div className="forgot-password-page__success">
          <span aria-hidden="true" className="forgot-password-page__success-mark">
            <Check size={27} strokeWidth={2.4} />
          </span>
          <h1 ref={successHeadingRef} tabIndex={-1}>Confira sua caixa de entrada</h1>
          <p role="status">
            Se houver uma conta com esse e-mail, você receberá as instruções em instantes.
          </p>
          <p className="forgot-password-page__success-note">
            O link pode ser usado uma vez. Se ele expirar, solicite outro por aqui.
          </p>
          <div className="forgot-password-page__success-actions">
            <Link className="btn btn--primary btn--lg" to={withHandoff("/login")}>
              Voltar para o login
              <ArrowRight aria-hidden="true" size={18} />
            </Link>
            <button className="btn btn--ghost" onClick={restartRecovery} type="button">
              Usar outro e-mail
            </button>
          </div>
        </div>
      ) : (
        <>
          <Link className="forgot-password-page__back" to={withHandoff("/login")}>
            <ArrowLeft aria-hidden="true" size={17} />
            Voltar para o login
          </Link>
          <header className="forgot-password-page__header">
            <span aria-hidden="true" className="forgot-password-page__form-mark">
              <KeyRound size={23} strokeWidth={2.2} />
            </span>
            <h1 id="forgot-password-title">Recupere seu acesso</h1>
            <p>Digite o e-mail usado no Rentivo. Se houver uma conta, enviaremos um link seguro.</p>
          </header>
          <form
            aria-labelledby="forgot-password-title"
            className="forgot-password-page__form"
            onSubmit={handleSubmit}
          >
            <div className="field">
              <label className="field__label" htmlFor="forgot-email">
                E-mail
              </label>
              <input
                aria-describedby={error ? "forgot-email-error" : "forgot-email-hint"}
                aria-invalid={error ? true : undefined}
                autoCapitalize="none"
                autoComplete="email"
                className="input"
                enterKeyHint="send"
                id="forgot-email"
                inputMode="email"
                name="email"
                onChange={(event) => {
                  setEmail(event.target.value);
                  setError(null);
                }}
                ref={emailRef}
                required
                spellCheck={false}
                type="email"
                value={email}
              />
              {error ? (
                <span className="forgot-password-page__field-error" id="forgot-email-error" role="alert">
                  {error}
                </span>
              ) : (
                <span className="forgot-password-page__field-hint" id="forgot-email-hint">
                  Use o mesmo endereço que você informa ao entrar.
                </span>
              )}
            </div>
            <Turnstile
              enabled={auth.config.feature_flags.turnstile}
              onToken={setTurnstileToken}
              ref={turnstileRef}
              siteKey={auth.config.feature_flags.turnstile_site_key}
            />
            <SubmitButton
              className="btn btn--primary btn--block btn--lg forgot-password-page__submit"
              loading={loading}
            >
              {loading ? "Enviando link…" : "Enviar link"}
              {!loading ? <ArrowRight aria-hidden="true" size={18} /> : null}
            </SubmitButton>
          </form>
        </>
      )}
    </ForgotPasswordScaffold>
  );
}

function ForgotPasswordScaffold({ children, isHandoff }: { children: ReactNode; isHandoff: boolean }) {
  return (
    <section aria-label="Recuperação de senha" className="forgot-password-page">
      {!isHandoff ? (
        <Link aria-label="Ir para a página inicial do Rentivo" className="forgot-password-page__brand" to="/">
          <span aria-hidden="true" className="forgot-password-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </Link>
      ) : (
        <div aria-label="Rentivo" className="forgot-password-page__brand forgot-password-page__brand--static">
          <span aria-hidden="true" className="forgot-password-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </div>
      )}
      <div className="forgot-password-page__shell">
        <div className="forgot-password-page__auth">{children}</div>
        <aside aria-labelledby="forgot-password-context-title" className="forgot-password-page__context">
          <div className="forgot-password-page__context-header">
            <ShieldCheck aria-hidden="true" size={22} />
            <h2 id="forgot-password-context-title">O que acontece agora</h2>
          </div>
          <ol className="forgot-password-page__flow">
            <li>
              <Mail aria-hidden="true" size={18} />
              <span><strong>Procure pelo e-mail</strong><small>Enviaremos as instruções se houver uma conta.</small></span>
            </li>
            <li>
              <KeyRound aria-hidden="true" size={18} />
              <span><strong>Abra o link seguro</strong><small>O acesso é temporário e funciona uma vez.</small></span>
            </li>
            <li>
              <Check aria-hidden="true" size={18} />
              <span><strong>Defina a nova senha</strong><small>Depois disso, entre normalmente no Rentivo.</small></span>
            </li>
          </ol>
          <p className="forgot-password-page__privacy-note">
            A resposta é sempre igual para não revelar se um e-mail está cadastrado.
          </p>
        </aside>
      </div>
      {!isHandoff ? (
        <nav aria-label="Links institucionais" className="forgot-password-page__footer">
          <Link to="/terms">Termos de Uso</Link>
          <Link to="/privacy">Política de Privacidade</Link>
          <Link to="/support">Ajuda</Link>
        </nav>
      ) : null}
    </section>
  );
}
