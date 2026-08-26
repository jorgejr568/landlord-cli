import { ArrowLeft, Copy, KeyRound, QrCode, ShieldCheck } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { SubmitButton } from "../auth/AuthComponents";
import { useAuth } from "../auth/AuthProvider";
import { pushAnalyticsFromResponse } from "../auth/analytics";

import "./TotpSetupPage.css";

type Setup = components["schemas"]["TOTPSetupResponse"];
type CopyStatus = "idle" | "copied" | "failed";

export function TotpSetupPage() {
  const { bootstrap, refreshSession, status } = useAuth();
  const navigate = useNavigate();
  const [setup, setSetup] = useState<Setup | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [confirmError, setConfirmError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [confirming, setConfirming] = useState(false);
  const [copyStatus, setCopyStatus] = useState<CopyStatus>("idle");
  const [code, setCode] = useState("");
  const [attempt, setAttempt] = useState(0);
  const codeRef = useRef<HTMLInputElement>(null);
  const loadErrorRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async (signal: AbortSignal) => {
    setLoading(true);
    setLoadError(null);
    setSetup(null);
    try {
      const { data } = await apiRequest(
        apiClient.POST("/api/v1/security/totp/setup", { signal })
      );
      setSetup(data);
    } catch (caught: unknown) {
      if (!signal.aborted) {
        setLoadError(
          caught instanceof ApiError
            ? caught.message
            : "Não foi possível iniciar a configuração TOTP."
        );
      }
    } finally {
      if (!signal.aborted) setLoading(false);
    }
  }, []);

  useEffect(() => {
    document.title = "Configurar TOTP - Rentivo";
    if (status !== "authenticated") return;
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [attempt, load, status]);

  useEffect(() => {
    if (confirmError) codeRef.current?.focus();
  }, [confirmError]);

  useEffect(() => {
    if (loadError) loadErrorRef.current?.focus();
  }, [loadError]);

  async function copySecret(secret: string) {
    try {
      await navigator.clipboard.writeText(secret);
      setCopyStatus("copied");
    } catch {
      setCopyStatus("failed");
    }
  }

  async function confirm(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setConfirming(true);
    setConfirmError(null);
    try {
      const { data, response } = await apiRequest(
        apiClient.POST("/api/v1/security/totp/confirm", {
          body: { code: code.trim() }
        })
      );
      pushAnalyticsFromResponse(response);
      await refreshSession().catch(() => undefined);
      navigate("/security/recovery-codes", {
        replace: true,
        state: { recoveryCodes: data.recovery_codes }
      });
    } catch (caught: unknown) {
      setConfirmError(
        caught instanceof ApiError ? caught.message : "Não foi possível confirmar o código."
      );
    } finally {
      setConfirming(false);
    }
  }

  const verificationReady = code.length === 6;

  return (
    <section aria-labelledby="totp-setup-title" className="totp-setup-page">
      <header className="totp-setup-page__header">
        <div className="totp-setup-page__heading">
          <Link className="totp-setup-page__back" to="/security">
            <ArrowLeft aria-hidden="true" size={16} />
            Segurança
          </Link>
          <p className="totp-setup-page__eyebrow">Proteção da conta</p>
          <h1 id="totp-setup-title">Configurar Autenticação TOTP</h1>
          <p>Conecte um aplicativo autenticador e confirme o primeiro código.</p>
        </div>
        <div className="totp-setup-page__assurance">
          <ShieldCheck aria-hidden="true" size={20} />
          <span>
            <strong>Configuração segura</strong>
            <small>A ativação só acontece após a confirmação.</small>
          </span>
        </div>
      </header>

      {bootstrap?.capabilities.mfa_setup_required ? (
        <div className="totp-setup-page__enforcement" role="status">
          <div>
            <strong>Sua organização exige autenticação multifator.</strong>
            <span>Conclua o TOTP ou cadastre uma passkey para continuar.</span>
          </div>
          <Link className="btn btn--sm" to="/security">
            Usar uma passkey
          </Link>
        </div>
      ) : null}

      <ol aria-label="Progresso da configuração" className="totp-setup-progress">
        <li aria-current={!verificationReady ? "step" : undefined}>
          <span className="totp-setup-progress__number">1</span>
          <span>
            <strong>Escaneie</strong>
            <small>Conecte o aplicativo</small>
          </span>
        </li>
        <li aria-current={verificationReady ? "step" : undefined}>
          <span className="totp-setup-progress__number">2</span>
          <span>
            <strong>Confirme</strong>
            <small>Valide 6 dígitos</small>
          </span>
        </li>
        <li>
          <span className="totp-setup-progress__number">3</span>
          <span>
            <strong>Guarde</strong>
            <small>Salve os códigos</small>
          </span>
        </li>
      </ol>

      {loading ? (
        <div
          aria-busy="true"
          aria-live="polite"
          className="totp-setup-state totp-setup-state--loading"
          role="status"
        >
          <div aria-hidden="true" className="totp-setup-state__qr-skeleton" />
          <div>
            <strong>Preparando seu QR code…</strong>
            <span>Gerando uma chave exclusiva para esta conta.</span>
          </div>
        </div>
      ) : null}

      {!loading && loadError ? (
        <div
          className="totp-setup-state totp-setup-state--error"
          ref={loadErrorRef}
          role="alert"
          tabIndex={-1}
        >
          <KeyRound aria-hidden="true" size={30} />
          <div>
            <h2>Não foi possível preparar o autenticador</h2>
            <p>{loadError}</p>
          </div>
          <button
            className="btn btn--primary btn--sm"
            onClick={() => setAttempt((value) => value + 1)}
            type="button"
          >
            Tentar novamente
          </button>
        </div>
      ) : null}

      {setup ? (
        <section aria-label="Conectar aplicativo autenticador" className="totp-enrollment">
          <div className="totp-enrollment__scan">
            <figure className="totp-enrollment__qr">
              <div className="totp-enrollment__qr-label">
                <QrCode aria-hidden="true" size={17} />
                QR code da conta
              </div>
              <img
                alt="QR Code TOTP"
                height="250"
                src={`data:image/png;base64,${setup.qr_code_base64}`}
                width="250"
              />
              <figcaption>Aponte a câmera do aplicativo para o código.</figcaption>
            </figure>

            <div className="totp-enrollment__instructions">
              <h2>Escaneie no aplicativo</h2>
              <p>
                Abra seu autenticador, adicione uma conta e escolha a opção para ler um QR code.
              </p>
              <ol className="totp-enrollment__checklist">
                <li>Abra Google Authenticator, Authy ou outro aplicativo compatível.</li>
                <li>Adicione uma nova conta e escaneie o QR code.</li>
                <li>Volte com o código de 6 dígitos exibido no aplicativo.</li>
              </ol>

              <div className="totp-enrollment__manual">
                <div>
                  <KeyRound aria-hidden="true" size={18} />
                  <span>
                    <strong>Sem câmera? Use a chave manual</strong>
                    <small>Selecione a opção “inserir chave” no aplicativo.</small>
                  </span>
                </div>
                <div className="totp-enrollment__secret-row">
                  <code translate="no">{setup.secret}</code>
                  <button
                    aria-label="Copiar chave"
                    className="btn btn--sm totp-enrollment__copy"
                    onClick={() => void copySecret(setup.secret)}
                    type="button"
                  >
                    <Copy aria-hidden="true" size={15} />
                    Copiar
                  </button>
                </div>
                <div aria-live="polite" className="totp-enrollment__copy-status">
                  {copyStatus === "copied" ? <span role="status">Chave copiada.</span> : null}
                  {copyStatus === "failed" ? (
                    <span role="alert">Não foi possível copiar. Selecione a chave manualmente.</span>
                  ) : null}
                </div>
              </div>
            </div>
          </div>

          <form className="totp-enrollment__verify" onSubmit={(event) => void confirm(event)}>
            <div className="totp-enrollment__verify-copy">
              <h2>Confirme o vínculo</h2>
              <p>Digite o código atual do aplicativo para ativar o TOTP.</p>
            </div>
            <div className="totp-enrollment__verify-action">
              <div className="field">
                <label className="field-label" htmlFor="totp-code">
                  Código de verificação
                </label>
                <input
                  aria-describedby={confirmError ? "totp-code-hint totp-code-error" : "totp-code-hint"}
                  aria-invalid={confirmError ? "true" : undefined}
                  autoComplete="one-time-code"
                  className="field-input"
                  id="totp-code"
                  inputMode="numeric"
                  maxLength={6}
                  name="code"
                  onChange={(event) => {
                    setCode(event.target.value.replace(/\D/g, "").slice(0, 6));
                    setConfirmError(null);
                  }}
                  pattern="[0-9]{6}"
                  placeholder="123456…"
                  ref={codeRef}
                  required
                  spellCheck={false}
                  value={code}
                />
                <small className="field-hint" id="totp-code-hint">
                  O código muda a cada 30 segundos.
                </small>
                {confirmError ? (
                  <span className="totp-enrollment__field-error" id="totp-code-error" role="alert">
                    {confirmError}
                  </span>
                ) : null}
              </div>
              <SubmitButton
                className="btn btn--primary totp-enrollment__submit"
                loading={confirming}
              >
                Confirmar e Ativar
              </SubmitButton>
            </div>
          </form>
        </section>
      ) : null}
    </section>
  );
}
