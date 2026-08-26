import {
  ArrowRight,
  Check,
  Fingerprint,
  KeyRound,
  LoaderCircle,
  LockKeyhole,
  ShieldCheck,
  Smartphone
} from "lucide-react";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { AuthError, SubmitButton } from "./AuthComponents";
import { postLoginPath, useAuth } from "./AuthProvider";
import { pushAnalyticsEvent, pushAnalyticsFromResponse } from "./analytics";
import { loadMfaChallenge } from "./authStorage";
import { authenticateWithPasskey } from "./webauthn";
import "./MfaVerifyPage.css";

type AuthenticatedResponse = components["schemas"]["AuthenticatedResponse"];
type MfaCodeVerifyRequest = components["schemas"]["MFACodeVerifyRequest"];
type PasskeyAuthBeginRequest = components["schemas"]["PasskeyAuthBeginRequest"];
type PasskeyAuthCompleteRequest = components["schemas"]["PasskeyAuthCompleteRequest"];
type VerificationMethod = "passkey" | "recovery" | "totp";

function isVerificationMethod(method: string): method is VerificationMethod {
  return method === "passkey" || method === "recovery" || method === "totp";
}

const INVALID_CODE = "Código inválido. Tente novamente.";
const RATE_LIMITED = "Muitas tentativas. Aguarde alguns minutos.";
const PASSKEY_ERROR = "Erro na autenticação com passkey. Tente novamente.";

export function MfaVerifyPage() {
  const auth = useAuth();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const challengeId = searchParams.get("challenge") ?? "";
  const mobileState = searchParams.get("mobile_state");
  const mobileLoginPath = mobileState
    ? `/login?mobile_state=${encodeURIComponent(mobileState)}`
    : "/login";
  const [challenge] = useState(() => loadMfaChallenge(challengeId));
  const [activeMethod, setActiveMethod] = useState<VerificationMethod>(() => {
    if (challenge?.methods.includes("totp")) return "totp";
    if (challenge?.methods.includes("passkey")) return "passkey";
    return "recovery";
  });
  const [code, setCode] = useState("");
  const [recoveryCode, setRecoveryCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loadingMethod, setLoadingMethod] = useState<VerificationMethod | null>(null);
  const [focusMethod, setFocusMethod] = useState<VerificationMethod>("totp");
  const codeRef = useRef<HTMLInputElement>(null);
  const recoveryRef = useRef<HTMLInputElement>(null);
  const passkeyRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    document.title = "Verificação MFA - Rentivo";
  }, []);

  useEffect(() => {
    if (!challenge) {
      navigate(mobileLoginPath, { replace: true });
    }
  }, [challenge, mobileLoginPath, navigate]);

  useEffect(() => {
    if (!error) {
      return;
    }
    if (focusMethod === "recovery") {
      recoveryRef.current?.focus();
    } else if (focusMethod === "passkey") {
      passkeyRef.current?.focus();
    } else {
      codeRef.current?.focus();
    }
  }, [error, focusMethod]);

  useEffect(() => {
    if (activeMethod === "recovery") {
      recoveryRef.current?.focus();
    } else if (activeMethod === "passkey") {
      passkeyRef.current?.focus();
    } else {
      codeRef.current?.focus();
    }
  }, [activeMethod]);

  if (!challenge) {
    return (
      <section
        aria-label="Verificação de segurança"
        className="mfa-page mfa-page--redirecting"
      >
        <div className="mfa-page__redirect" role="status">
          <LoaderCircle aria-hidden="true" size={20} />
          <span>Sessão de verificação encerrada. Redirecionando…</span>
        </div>
      </section>
    );
  }

  const activeChallenge = challenge;
  const methods = new Set(activeChallenge.methods.filter(isVerificationMethod));

  function selectMethod(method: VerificationMethod) {
    if (loadingMethod !== null || method === activeMethod) return;
    setError(null);
    setFocusMethod(method);
    setActiveMethod(method);
  }

  function completeAuthentication(response: AuthenticatedResponse) {
    auth.authenticate(response);
    navigate(mobileState ? mobileLoginPath : postLoginPath(response.bootstrap));
  }

  function handleVerificationError(caught: unknown, method: VerificationMethod) {
    setFocusMethod(method);
    if (caught instanceof ApiError) {
      pushAnalyticsFromResponse(caught.response);
      if (caught.code === "invalid_mfa_code") {
        pushAnalyticsEvent({ event: "rentivo_mfa_verify_failed" });
        setError(INVALID_CODE);
      } else if (caught.code === "mfa_rate_limited") {
        setError(RATE_LIMITED);
      } else {
        setError(caught.message);
      }
      return;
    }
    setError("Não foi possível concluir a solicitação. Tente novamente.");
  }

  async function verifyCode(
    event: FormEvent<HTMLFormElement>,
    method: "recovery" | "totp"
  ) {
    event.preventDefault();
    setError(null);
    setLoadingMethod(method);
    const payload: MfaCodeVerifyRequest = {
      challenge_id: activeChallenge.challengeId,
      code: (method === "recovery" ? recoveryCode : code).trim(),
      credential_transport: "cookie"
    };
    try {
      const request = method === "recovery"
        ? apiClient.POST("/api/v1/auth/mfa/recovery/verify", { body: payload })
        : apiClient.POST("/api/v1/auth/mfa/totp/verify", { body: payload });
      const { data, response } = await apiRequest(
        request
      );
      pushAnalyticsFromResponse(response);
      completeAuthentication(data);
    } catch (caught: unknown) {
      handleVerificationError(caught, method);
    } finally {
      setLoadingMethod(null);
    }
  }

  async function verifyPasskey() {
    setError(null);
    setLoadingMethod("passkey");
    try {
      const beginPayload: PasskeyAuthBeginRequest = {
        challenge_id: activeChallenge.challengeId,
        credential_transport: "cookie"
      };
      const { data: options } = await apiRequest(
        apiClient.POST("/api/v1/auth/mfa/passkeys/begin", { body: beginPayload })
      );
      const credential = await authenticateWithPasskey(options);
      if (!credential) {
        return;
      }
      const completePayload: PasskeyAuthCompleteRequest = {
        challenge_id: activeChallenge.challengeId,
        credential,
        credential_transport: "cookie"
      };
      const { data, response } = await apiRequest(
        apiClient.POST("/api/v1/auth/mfa/passkeys/complete", { body: completePayload })
      );
      pushAnalyticsFromResponse(response);
      completeAuthentication(data);
    } catch (caught: unknown) {
      if (caught instanceof Error && caught.name === "NotAllowedError") {
        return;
      }
      if (caught instanceof ApiError) {
        handleVerificationError(caught, "passkey");
      } else {
        setFocusMethod("passkey");
        setError(PASSKEY_ERROR);
      }
    } finally {
      setLoadingMethod(null);
    }
  }

  return (
    <section aria-label="Verificação de segurança" className="mfa-page">
      <div aria-label="Rentivo" className="mfa-page__brand" translate="no">
        <span aria-hidden="true" className="mfa-page__brand-mark">R</span>
        <span>rent<em>ivo</em></span>
      </div>

      <div className="mfa-page__shell">
        <aside className="mfa-page__context">
          <div>
            <span className="mfa-page__eyebrow">Acesso protegido</span>
            <p className="mfa-page__context-title">Uma confirmação antes de continuar.</p>
            <p>Esta etapa protege seus imóveis, cobranças e dados de recebimento.</p>
          </div>

          <ol aria-label="Progresso do acesso" className="mfa-page__progress">
            <li className="is-complete">
              <span aria-hidden="true"><Check size={16} /></span>
              <div><strong>Senha confirmada</strong><small>Primeira etapa concluída</small></div>
            </li>
            <li aria-current="step" className="is-current">
              <span aria-hidden="true"><ShieldCheck size={17} /></span>
              <div><strong>Verificação em andamento</strong><small>Confirme um método seguro</small></div>
            </li>
            <li>
              <span aria-hidden="true"><ArrowRight size={16} /></span>
              <div><strong>Acesso liberado</strong><small>Você volta ao seu painel</small></div>
            </li>
          </ol>

          <p className="mfa-page__privacy">
            <LockKeyhole aria-hidden="true" size={16} />
            O código é usado somente para confirmar este acesso.
          </p>
        </aside>

        <div className="mfa-page__verification">
          <header className="mfa-page__header">
            <h1>Verificação MFA</h1>
            <p>Escolha uma opção disponível para confirmar que é você.</p>
          </header>

          {methods.size > 0 ? <div aria-label="Método de verificação" className="mfa-page__methods" role="group">
            {methods.has("totp") ? (
              <button
                aria-pressed={activeMethod === "totp"}
                disabled={loadingMethod !== null}
                onClick={() => selectMethod("totp")}
                type="button"
              >
                <Smartphone aria-hidden="true" size={18} />
                <span>Aplicativo autenticador</span>
              </button>
            ) : null}
            {methods.has("passkey") ? (
              <button
                aria-pressed={activeMethod === "passkey"}
                disabled={loadingMethod !== null}
                onClick={() => selectMethod("passkey")}
                type="button"
              >
                <Fingerprint aria-hidden="true" size={18} />
                <span>Passkey</span>
              </button>
            ) : null}
            {methods.has("recovery") ? (
              <button
                aria-pressed={activeMethod === "recovery"}
                disabled={loadingMethod !== null}
                onClick={() => selectMethod("recovery")}
                type="button"
              >
                <KeyRound aria-hidden="true" size={18} />
                <span>Usar código de recuperação</span>
              </button>
            ) : null}
          </div> : null}

          <div aria-live="polite" className="mfa-page__feedback">
            <AuthError message={error} />
          </div>

          {methods.size === 0 ? (
            <div className="mfa-page__method-panel mfa-page__method-panel--empty">
              <span aria-hidden="true" className="mfa-page__empty-icon"><LockKeyhole size={22} /></span>
              <h2>Nenhum método disponível</h2>
              <p>Entre novamente para iniciar uma nova verificação.</p>
            </div>
          ) : <div className="mfa-page__method-panel" key={activeMethod}>
            {activeMethod === "totp" && methods.has("totp") ? (
              <>
                <div className="mfa-page__method-heading">
                  <span aria-hidden="true"><Smartphone size={20} /></span>
                  <div>
                    <h2>Código do autenticador</h2>
                    <p>Abra seu aplicativo e digite o código atual de 6 dígitos.</p>
                  </div>
                </div>
                <form className="mfa-page__form" id="totp-form" onSubmit={(event) => void verifyCode(event, "totp")}>
                  <div className="field">
                    <div className="mfa-page__label-row">
                      <label className="field-label" htmlFor="code">Código de autenticação</label>
                      <span className="mfa-page__count">{Math.min(code.length, 6)} de 6 dígitos</span>
                    </div>
                    <input
                      aria-describedby="code-help"
                      autoComplete="one-time-code"
                      autoFocus
                      className="field-input mfa-page__code-input"
                      id="code"
                      inputMode="numeric"
                      name="code"
                      onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, 6))}
                      pattern="[0-9]*"
                      placeholder="000000"
                      ref={codeRef}
                      required
                      spellCheck={false}
                      type="text"
                      value={code}
                    />
                    <small className="mfa-page__field-help" id="code-help">O código muda a cada poucos segundos. Você pode colar aqui.</small>
                  </div>
                  <SubmitButton
                    className="btn btn--primary mfa-page__submit"
                    disabled={loadingMethod !== null}
                    loading={loadingMethod === "totp"}
                  >
                    {loadingMethod === "totp" ? "Verificando…" : "Verificar"}
                    {loadingMethod !== "totp" ? <ArrowRight aria-hidden="true" size={17} /> : null}
                  </SubmitButton>
                </form>
              </>
            ) : null}

            {activeMethod === "passkey" && methods.has("passkey") ? (
              <>
                <div className="mfa-page__method-heading">
                  <span aria-hidden="true"><Fingerprint size={21} /></span>
                  <div>
                    <h2>Use sua passkey</h2>
                    <p>Confirme com biometria, PIN ou a chave de segurança deste dispositivo.</p>
                  </div>
                </div>
                <button
                  aria-busy={loadingMethod === "passkey"}
                  className="btn btn--primary mfa-page__submit"
                  disabled={loadingMethod !== null}
                  onClick={() => void verifyPasskey()}
                  ref={passkeyRef}
                  type="button"
                >
                  {loadingMethod === "passkey" ? <LoaderCircle aria-hidden="true" size={17} /> : <Fingerprint aria-hidden="true" size={18} />}
                  {loadingMethod === "passkey" ? "Aguardando confirmação…" : "Usar Passkey"}
                </button>
                <p className="mfa-page__field-help">Seu navegador abrirá a confirmação segura. A Rentivo não recebe seus dados biométricos.</p>
              </>
            ) : null}

            {activeMethod === "recovery" && methods.has("recovery") ? (
              <>
                <div className="mfa-page__method-heading">
                  <span aria-hidden="true"><KeyRound size={20} /></span>
                  <div>
                    <h2>Código de recuperação</h2>
                    <p>Use um dos códigos salvos quando configurou a autenticação.</p>
                  </div>
                </div>
                <form className="mfa-page__form" onSubmit={(event) => void verifyCode(event, "recovery")}>
                  <div className="field">
                    <label className="field-label" htmlFor="recovery-code">Código de recuperação</label>
                    <input
                      aria-describedby="recovery-help"
                      autoComplete="one-time-code"
                      className="field-input mfa-page__recovery-input"
                      id="recovery-code"
                      name="code"
                      onChange={(event) => setRecoveryCode(event.target.value)}
                      placeholder="Ex.: ABCD-EFGH…"
                      ref={recoveryRef}
                      required
                      spellCheck={false}
                      type="text"
                      value={recoveryCode}
                    />
                    <small className="mfa-page__field-help" id="recovery-help">Cada código funciona uma única vez.</small>
                  </div>
                  <SubmitButton
                    className="btn btn--primary mfa-page__submit"
                    disabled={loadingMethod !== null}
                    loading={loadingMethod === "recovery"}
                  >
                    {loadingMethod === "recovery" ? "Verificando…" : "Confirmar código"}
                  </SubmitButton>
                </form>
              </>
            ) : null}
          </div>}

          <footer className="mfa-page__footer">
            <span>Não consegue confirmar?</span>
            <Link to={mobileLoginPath}>Voltar para o login</Link>
          </footer>
        </div>
      </div>
    </section>
  );
}
