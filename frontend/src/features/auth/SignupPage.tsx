import {
  ArrowRight,
  Eye,
  EyeOff,
  FileCheck2,
  LockKeyhole,
  ReceiptText,
  WalletCards
} from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";

import { passwordValidationError } from "../../forms/validators";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { AuthError, GoogleAuthOption, SubmitButton } from "./AuthComponents";
import { postLoginPath, useAuth } from "./AuthProvider";
import { useMobileHandoff } from "./mobileHandoff";
import { Turnstile, type TurnstileHandle } from "./Turnstile";
import "./SignupPage.css";

type SignupRequest = components["schemas"]["SignupRequest"];
type SignupField = "confirmPassword" | "email" | "legalConsent" | "password";
type SignupFieldErrors = Partial<Record<SignupField, string>>;

export function SignupPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  // Read from the URL, not from the sticky handoff marker: a stale state would
  // make LoginPage authorize a session the app is no longer waiting on.
  const mobileState = searchParams.get("mobile_state");
  const mobileLoginPath = mobileState
    ? `/login?mobile_state=${encodeURIComponent(mobileState)}`
    : null;
  const { isHandoff, withHandoff } = useMobileHandoff();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [legalConsent, setLegalConsent] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmation, setShowConfirmation] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState("");
  const [formError, setFormError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<SignupFieldErrors>({});
  const [loading, setLoading] = useState(false);
  const emailRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);
  const confirmationRef = useRef<HTMLInputElement>(null);
  const legalConsentRef = useRef<HTMLInputElement>(null);
  const turnstileRef = useRef<TurnstileHandle>(null);

  const passwordEntered = password.length > 0;
  const passwordsMatch = passwordEntered && confirmPassword.length > 0 && password === confirmPassword;

  useEffect(() => {
    document.title = "Criar Conta - Rentivo";
  }, []);

  useEffect(() => {
    if (auth.status === "authenticated" && auth.bootstrap) {
      navigate(mobileLoginPath ?? postLoginPath(auth.bootstrap), { replace: true });
    }
  }, [auth.bootstrap, auth.status, mobileLoginPath, navigate]);

  function clearFieldError(field: SignupField) {
    setFieldErrors((current) => {
      if (!current[field]) {
        return current;
      }
      const next = { ...current };
      delete next[field];
      return next;
    });
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFormError(null);
    setFieldErrors({});

    const passwordError = passwordValidationError(password);
    if (passwordError) {
      setFieldErrors({ password: passwordError });
      passwordRef.current?.focus();
      return;
    }
    const confirmationError = passwordValidationError(confirmPassword);
    if (confirmationError) {
      setFieldErrors({ confirmPassword: confirmationError });
      confirmationRef.current?.focus();
      return;
    }
    if (password !== confirmPassword) {
      setFieldErrors({ confirmPassword: "As senhas não coincidem." });
      confirmationRef.current?.focus();
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
      navigate(mobileLoginPath ?? postLoginPath(data.bootstrap));
    } catch (caught: unknown) {
      if (
        caught instanceof ApiError &&
        (caught.code === "email_already_registered" || caught.fields.email)
      ) {
        setFieldErrors({ email: caught.fields.email ?? caught.message });
      } else {
        setFormError(
          caught instanceof ApiError
            ? caught.message
            : "Não foi possível concluir a solicitação. Tente novamente."
        );
      }
      emailRef.current?.focus();
      turnstileRef.current?.reset();
    } finally {
      setLoading(false);
    }
  }

  if (auth.configStatus === "loading") {
    return (
      <SignupScaffold isHandoff={isHandoff}>
        <div className="signup-page__loading" role="status">
          <span className="sr-only">Carregando opções de cadastro…</span>
          <span aria-hidden="true" className="signup-page__skeleton signup-page__skeleton--title" />
          <span aria-hidden="true" className="signup-page__skeleton signup-page__skeleton--copy" />
          <span aria-hidden="true" className="signup-page__skeleton" />
          <span aria-hidden="true" className="signup-page__skeleton" />
          <span aria-hidden="true" className="signup-page__skeleton signup-page__skeleton--button" />
        </div>
      </SignupScaffold>
    );
  }

  if (auth.configStatus === "error" || !auth.config) {
    return (
      <SignupScaffold isHandoff={isHandoff}>
        <div className="signup-page__header">
          <h1>Criar Conta</h1>
          <p>Não foi possível preparar o cadastro agora.</p>
        </div>
        <AuthError message="Não foi possível carregar as opções de autenticação. Tente novamente." />
        <button className="btn btn--primary btn--lg" onClick={auth.retryConfig} type="button">
          Tentar novamente
        </button>
      </SignupScaffold>
    );
  }

  return (
    <SignupScaffold isHandoff={isHandoff}>
      <div className="signup-page__header">
        <h1 id="signup-title">Criar Conta</h1>
        <p>Cadastre seu acesso. Você configura imóveis, cobranças e PIX depois.</p>
      </div>
      <AuthError message={formError} />
      <form aria-labelledby="signup-title" className="signup-page__form" onSubmit={handleSubmit}>
        <div className="field">
          <label className="field__label" htmlFor="signup-email">
            E-mail
          </label>
          <input
            aria-describedby={fieldErrors.email ? "signup-email-error" : undefined}
            aria-invalid={fieldErrors.email ? true : undefined}
            autoCapitalize="none"
            autoComplete="email"
            autoFocus
            className="input"
            id="signup-email"
            inputMode="email"
            name="email"
            onChange={(event) => {
              setEmail(event.target.value);
              setFormError(null);
              clearFieldError("email");
            }}
            ref={emailRef}
            required
            spellCheck={false}
            type="email"
            value={email}
          />
          {fieldErrors.email ? (
            <span className="signup-page__field-error" id="signup-email-error" role="alert">
              {fieldErrors.email}
            </span>
          ) : null}
        </div>
        <div className="signup-page__password-grid">
          <div className="field">
            <label className="field__label" htmlFor="signup-password">
              Senha
            </label>
            <div className="signup-page__password-control">
              <input
                aria-describedby={fieldErrors.password ? "signup-password-error" : undefined}
                aria-invalid={fieldErrors.password ? true : undefined}
                autoComplete="new-password"
                className="input"
                id="signup-password"
                name="password"
                onChange={(event) => {
                  setPassword(event.target.value);
                  clearFieldError("password");
                }}
                ref={passwordRef}
                required
                type={showPassword ? "text" : "password"}
                value={password}
              />
              <button
                aria-controls="signup-password"
                aria-label={showPassword ? "Ocultar senha" : "Mostrar senha"}
                aria-pressed={showPassword}
                className="signup-page__password-toggle"
                onClick={() => setShowPassword((visible) => !visible)}
                type="button"
              >
                {showPassword ? <EyeOff aria-hidden="true" size={18} /> : <Eye aria-hidden="true" size={18} />}
              </button>
            </div>
            {fieldErrors.password ? (
              <span className="signup-page__field-error" id="signup-password-error" role="alert">
                {fieldErrors.password}
              </span>
            ) : null}
          </div>
          <div className="field">
            <label className="field__label" htmlFor="confirm-password">
              Confirmar Senha
            </label>
            <div className="signup-page__password-control">
              <input
                aria-describedby={fieldErrors.confirmPassword ? "confirm-password-error" : undefined}
                aria-invalid={fieldErrors.confirmPassword ? true : undefined}
                autoComplete="new-password"
                className="input"
                id="confirm-password"
                name="confirm_password"
                onChange={(event) => {
                  setConfirmPassword(event.target.value);
                  clearFieldError("confirmPassword");
                }}
                ref={confirmationRef}
                required
                type={showConfirmation ? "text" : "password"}
                value={confirmPassword}
              />
              <button
                aria-controls="confirm-password"
                aria-label={showConfirmation ? "Ocultar confirmação da senha" : "Mostrar confirmação da senha"}
                aria-pressed={showConfirmation}
                className="signup-page__password-toggle"
                onClick={() => setShowConfirmation((visible) => !visible)}
                type="button"
              >
                {showConfirmation ? <EyeOff aria-hidden="true" size={18} /> : <Eye aria-hidden="true" size={18} />}
              </button>
            </div>
            {fieldErrors.confirmPassword ? (
              <span className="signup-page__field-error" id="confirm-password-error" role="alert">
                {fieldErrors.confirmPassword}
              </span>
            ) : null}
          </div>
        </div>
        <div aria-live="polite" className="signup-page__password-guidance">
          <span data-met={passwordEntered}>{passwordEntered ? "Senha preenchida" : "Digite sua senha"}</span>
          <span data-met={passwordsMatch}>
            {passwordsMatch
              ? "Senhas iguais"
              : confirmPassword
                ? "As senhas ainda não coincidem"
                : "Repita a mesma senha"}
          </span>
        </div>
        <Turnstile
          enabled={auth.config.feature_flags.turnstile}
          onToken={setTurnstileToken}
          ref={turnstileRef}
          siteKey={auth.config.feature_flags.turnstile_site_key}
        />
        <div className="signup-page__consent">
          <input
            aria-describedby={fieldErrors.legalConsent ? "signup-consent-error" : undefined}
            aria-invalid={fieldErrors.legalConsent ? true : undefined}
            checked={legalConsent}
            className="signup-page__consent-checkbox"
            id="signup-legal-consent"
            name="legal_consent"
            onChange={(event) => {
              setLegalConsent(event.target.checked);
              clearFieldError("legalConsent");
            }}
            onInvalid={(event) => {
              event.preventDefault();
              setFieldErrors({
                legalConsent: "Aceite os Termos de Uso e a Política de Privacidade para criar sua conta."
              });
              legalConsentRef.current?.focus();
            }}
            ref={legalConsentRef}
            required
            type="checkbox"
          />
          <div className="signup-page__consent-copy">
            <label htmlFor="signup-legal-consent">
              Li e aceito os{" "}
              <a href="/terms" rel="noopener noreferrer" target="_blank">Termos de Uso</a>
              {" "}e a{" "}
              <a href="/privacy" rel="noopener noreferrer" target="_blank">Política de Privacidade</a>.
            </label>
            {fieldErrors.legalConsent ? (
              <span className="signup-page__field-error" id="signup-consent-error" role="alert">
                {fieldErrors.legalConsent}
              </span>
            ) : null}
          </div>
        </div>
        <SubmitButton
          className="btn btn--primary btn--block btn--lg signup-page__submit"
          loading={loading}
        >
          {loading ? "Criando conta…" : "Criar Conta"}
          {!loading ? <ArrowRight aria-hidden="true" size={18} /> : null}
        </SubmitButton>
      </form>
      <div className="signup-page__social">
        <GoogleAuthOption enabled={auth.config.feature_flags.google_auth} />
      </div>
      <p className="signup-page__signin">
        Já tem uma conta? <Link to={withHandoff("/login")}>Entrar</Link>
      </p>
    </SignupScaffold>
  );
}

function SignupScaffold({ children, isHandoff }: { children: ReactNode; isHandoff: boolean }) {
  return (
    <section aria-label="Cadastro no Rentivo" className="signup-page">
      {!isHandoff ? (
        <Link aria-label="Ir para a página inicial do Rentivo" className="signup-page__brand" to="/">
          <span aria-hidden="true" className="signup-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </Link>
      ) : (
        <div aria-label="Rentivo" className="signup-page__brand signup-page__brand--static">
          <span aria-hidden="true" className="signup-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </div>
      )}
      <div className="signup-page__shell">
        <aside className="signup-page__context">
          <div>
            <span className="signup-page__eyebrow">Conta Rentivo</span>
            <p className="signup-page__context-title">Sua cobrança começa organizada.</p>
            <p className="signup-page__context-copy">
              Crie o acesso agora. Os detalhes da sua operação ficam para o próximo passo.
            </p>
          </div>
          <ul aria-label="Recursos disponíveis depois do cadastro" className="signup-page__benefits">
            <li>
              <FileCheck2 aria-hidden="true" size={18} />
              <span><strong>Cobranças recorrentes</strong><small>Valores e vencimentos no mesmo acordo.</small></span>
            </li>
            <li>
              <ReceiptText aria-hidden="true" size={18} />
              <span><strong>Fatura em PDF</strong><small>Documento, PIX e envio no mesmo fluxo.</small></span>
            </li>
            <li>
              <WalletCards aria-hidden="true" size={18} />
              <span><strong>Pagamentos visíveis</strong><small>Status e recibos fáceis de acompanhar.</small></span>
            </li>
          </ul>
          <p className="signup-page__security-note">
            <LockKeyhole aria-hidden="true" size={17} />
            Proteja a conta com autenticação em duas etapas depois do cadastro.
          </p>
        </aside>
        <div className="signup-page__auth">{children}</div>
      </div>
      {!isHandoff ? (
        <nav aria-label="Links institucionais" className="signup-page__footer">
          <Link to="/terms">Termos de Uso</Link>
          <Link to="/privacy">Política de Privacidade</Link>
          <Link to="/support">Ajuda</Link>
        </nav>
      ) : null}
    </section>
  );
}
