import {
  ArrowLeft,
  ArrowRight,
  Check,
  Circle,
  Clock3,
  Eye,
  EyeOff,
  KeyRound,
  LockKeyhole,
  ShieldCheck
} from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";

import { passwordValidationError } from "../../forms/validators";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { AuthError, SubmitButton } from "./AuthComponents";
import { pushAnalyticsFromResponse } from "./analytics";
import { setAuthFlash } from "./authStorage";
import "./ResetPasswordPage.css";

type PasswordResetRequest = components["schemas"]["PasswordResetRequest"];
type ResetField = "confirmPassword" | "password";
type ResetFieldErrors = Partial<Record<ResetField, string>>;

const INVALID_LINK = "Link inválido ou expirado. Solicite uma nova redefinição.";
const RESET_SUCCESS = "Senha redefinida com sucesso. Faça login com a nova senha.";

export function ResetPasswordPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const token = searchParams.get("token") ?? "";
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmation, setShowConfirmation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<ResetFieldErrors>({});
  const [invalid, setInvalid] = useState(!token);
  const [loading, setLoading] = useState(false);
  const passwordRef = useRef<HTMLInputElement>(null);
  const confirmationRef = useRef<HTMLInputElement>(null);

  const passwordBytes = new TextEncoder().encode(password).length;
  const hasPassword = passwordBytes > 0;
  const withinLimit = hasPassword && passwordBytes <= 72;
  const passwordsMatch =
    withinLimit && confirmPassword.length > 0 && password === confirmPassword;

  useEffect(() => {
    document.title = "Redefinir senha - Rentivo";
  }, []);

  useEffect(() => {
    if (
      !invalid &&
      (!window.matchMedia || window.matchMedia("(min-width: 821px)").matches)
    ) {
      passwordRef.current?.focus();
    }
  }, [invalid]);

  function clearFieldError(field: ResetField) {
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
    setError(null);
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
    const payload: PasswordResetRequest = {
      confirm_password: confirmPassword,
      password,
      token
    };
    try {
      const { response } = await apiRequest(
        apiClient.POST("/api/v1/auth/password/reset", { body: payload })
      );
      pushAnalyticsFromResponse(response);
      setAuthFlash(RESET_SUCCESS);
      navigate("/login", { replace: true });
    } catch (caught: unknown) {
      if (caught instanceof ApiError && caught.code === "invalid_or_expired_reset_token") {
        setInvalid(true);
      } else {
        setError(
          caught instanceof ApiError
            ? caught.message
            : "Não foi possível concluir a solicitação. Tente novamente."
        );
        passwordRef.current?.focus();
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <ResetPasswordScaffold>
      {invalid ? (
        <InvalidResetLink />
      ) : (
        <>
          <header className="reset-page__header">
            <span aria-hidden="true" className="reset-page__header-mark">
              <KeyRound size={24} />
            </span>
            <h1 id="reset-password-title">Crie uma nova senha</h1>
            <p>Escolha a senha que você usará no próximo acesso ao Rentivo.</p>
          </header>

          <AuthError message={error} />

          <form
            aria-labelledby="reset-password-title"
            className="reset-page__form"
            onSubmit={handleSubmit}
          >
            <div className="field">
              <label className="field__label" htmlFor="new-password">
                Nova senha
              </label>
              <div className="reset-page__password-control">
                <input
                  aria-describedby={
                    fieldErrors.password
                      ? "new-password-requirements new-password-error"
                      : "new-password-requirements"
                  }
                  aria-invalid={fieldErrors.password ? true : undefined}
                  autoCapitalize="none"
                  autoComplete="new-password"
                  autoCorrect="off"
                  className="input"
                  id="new-password"
                  maxLength={72}
                  name="password"
                  onChange={(event) => {
                    setPassword(event.target.value);
                    setError(null);
                    clearFieldError("password");
                  }}
                  ref={passwordRef}
                  required
                  type={showPassword ? "text" : "password"}
                  value={password}
                />
                <button
                  aria-controls="new-password"
                  aria-label={showPassword ? "Ocultar nova senha" : "Mostrar nova senha"}
                  aria-pressed={showPassword}
                  className="reset-page__password-toggle"
                  onClick={() => setShowPassword((visible) => !visible)}
                  type="button"
                >
                  {showPassword ? (
                    <EyeOff aria-hidden="true" size={19} />
                  ) : (
                    <Eye aria-hidden="true" size={19} />
                  )}
                </button>
              </div>
              {fieldErrors.password ? (
                <span className="reset-page__field-error" id="new-password-error" role="alert">
                  {fieldErrors.password}
                </span>
              ) : null}
            </div>

            <ul
              aria-label="Requisitos da senha"
              className="reset-page__requirements"
              id="new-password-requirements"
            >
              <PasswordRequirement met={hasPassword}>Senha preenchida</PasswordRequirement>
              <PasswordRequirement met={withinLimit}>
                Até 72&nbsp;bytes de texto
              </PasswordRequirement>
            </ul>

            <div className="field">
              <label className="field__label" htmlFor="confirm-new-password">
                Confirmar nova senha
              </label>
              <div className="reset-page__password-control">
                <input
                  aria-describedby={
                    fieldErrors.confirmPassword
                      ? "password-match-status confirm-new-password-error"
                      : "password-match-status"
                  }
                  aria-invalid={fieldErrors.confirmPassword ? true : undefined}
                  autoCapitalize="none"
                  autoComplete="new-password"
                  autoCorrect="off"
                  className="input"
                  id="confirm-new-password"
                  maxLength={72}
                  name="confirm_password"
                  onChange={(event) => {
                    setConfirmPassword(event.target.value);
                    setError(null);
                    clearFieldError("confirmPassword");
                  }}
                  ref={confirmationRef}
                  required
                  type={showConfirmation ? "text" : "password"}
                  value={confirmPassword}
                />
                <button
                  aria-controls="confirm-new-password"
                  aria-label={
                    showConfirmation
                      ? "Ocultar confirmação da senha"
                      : "Mostrar confirmação da senha"
                  }
                  aria-pressed={showConfirmation}
                  className="reset-page__password-toggle"
                  onClick={() => setShowConfirmation((visible) => !visible)}
                  type="button"
                >
                  {showConfirmation ? (
                    <EyeOff aria-hidden="true" size={19} />
                  ) : (
                    <Eye aria-hidden="true" size={19} />
                  )}
                </button>
              </div>
              {fieldErrors.confirmPassword ? (
                <span
                  className="reset-page__field-error"
                  id="confirm-new-password-error"
                  role="alert"
                >
                  {fieldErrors.confirmPassword}
                </span>
              ) : null}
            </div>

            <p
              aria-label="Estado das senhas"
              aria-live="polite"
              className="reset-page__match-status"
              data-matched={passwordsMatch}
              id="password-match-status"
              role="status"
            >
              {passwordsMatch ? (
                <Check aria-hidden="true" size={17} />
              ) : (
                <Circle aria-hidden="true" size={15} />
              )}
              {passwordsMatch ? "As senhas coincidem." : "As senhas ainda não coincidem."}
            </p>

            <SubmitButton
              className="btn btn--primary btn--lg reset-page__submit"
              loading={loading}
            >
              {loading ? "Redefinindo senha…" : "Redefinir senha"}
              {!loading ? <ArrowRight aria-hidden="true" size={18} /> : null}
            </SubmitButton>
          </form>
        </>
      )}
    </ResetPasswordScaffold>
  );
}

function PasswordRequirement({ children, met }: { children: ReactNode; met: boolean }) {
  return (
    <li data-met={met}>
      {met ? (
        <Check aria-hidden="true" size={16} />
      ) : (
        <Circle aria-hidden="true" size={14} />
      )}
      <span>{children}</span>
    </li>
  );
}

function InvalidResetLink() {
  return (
    <div className="reset-page__invalid">
      <span aria-hidden="true" className="reset-page__invalid-mark">
        <Clock3 size={27} />
      </span>
      <header className="reset-page__header reset-page__header--invalid">
        <h1>Este link não pode mais ser usado</h1>
        <p>Solicite outro link para concluir a troca com segurança.</p>
      </header>
      <div className="reset-page__invalid-message" role="alert">
        <strong>O acesso protegido pelo link terminou.</strong>
        <span>{INVALID_LINK}</span>
      </div>
      <div className="reset-page__invalid-actions">
        <Link className="btn btn--primary btn--lg" to="/forgot-password">
          Solicitar outro link
          <ArrowRight aria-hidden="true" size={18} />
        </Link>
        <Link className="reset-page__back-link" to="/login">
          <ArrowLeft aria-hidden="true" size={17} />
          Voltar para entrar
        </Link>
      </div>
    </div>
  );
}

function ResetPasswordScaffold({ children }: { children: ReactNode }) {
  return (
    <section aria-label="Redefinição de senha" className="reset-page">
      <Link aria-label="Ir para a página inicial do Rentivo" className="reset-page__brand" to="/">
        <span aria-hidden="true" className="reset-page__brand-mark">
          R
        </span>
        <span translate="no">
          rent<em>ivo</em>
        </span>
      </Link>

      <div className="reset-page__shell">
        <aside aria-label="Proteção da conta" className="reset-page__context">
          <div>
            <span className="reset-page__eyebrow">Acesso seguro</span>
            <h2>Troque sua senha sem perder o acesso às cobranças.</h2>
            <p>O link recebido confirma o pedido e autoriza uma única troca de senha.</p>
          </div>
          <ul className="reset-page__protections">
            <li>
              <ShieldCheck aria-hidden="true" size={19} />
              <span>
                <strong>Uso único</strong>
                <small>Depois da redefinição, o link deixa de funcionar.</small>
              </span>
            </li>
            <li>
              <Clock3 aria-hidden="true" size={19} />
              <span>
                <strong>Prazo limitado</strong>
                <small>Links vencidos devem ser solicitados novamente.</small>
              </span>
            </li>
            <li>
              <KeyRound aria-hidden="true" size={19} />
              <span>
                <strong>Acesso renovado</strong>
                <small>A nova senha passa a valer no próximo login.</small>
              </span>
            </li>
          </ul>
          <p className="reset-page__security-note">
            <LockKeyhole aria-hidden="true" size={17} />
            Nunca compartilhe este link ou sua senha por mensagem.
          </p>
        </aside>

        <div className="reset-page__auth">{children}</div>
      </div>

      <nav aria-label="Links institucionais" className="reset-page__footer">
        <Link to="/privacy">Privacidade</Link>
        <Link to="/terms">Termos</Link>
        <Link to="/support">Ajuda</Link>
      </nav>
    </section>
  );
}
