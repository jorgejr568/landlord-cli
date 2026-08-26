import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { CircleAlert, Fingerprint, KeyRound, Landmark, ShieldCheck } from "lucide-react";
import { Link, useNavigate } from "react-router";

import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import { passwordValidationError, validatePix } from "../../forms/validators";
import type { components } from "../../lib/api/schema";
import { limitApiCharacters } from "../../lib/textLimits";
import { ApiKeySection } from "../apiKeys/ApiKeySection";
import { SubmitButton } from "../auth/AuthComponents";
import { useAuth } from "../auth/AuthProvider";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import { PasskeyManager } from "./PasskeyManager";
import { createPasskey } from "./webauthn";
import "./SecurityPage.css";

type SecuritySummary = components["schemas"]["SecuritySummaryResponse"];
type AccountDeletionReadiness = components["schemas"]["AccountDeletionReadinessResponse"];

function messageFor(error: unknown, fallback: string): string {
  return error instanceof ApiError ? error.message : fallback;
}

export function SecurityPage() {
  const { logout } = useAuth();
  const navigate = useNavigate();
  const [summary, setSummary] = useState<SecuritySummary | null>(null);
  const [deletionReadiness, setDeletionReadiness] = useState<AccountDeletionReadiness | null>(null);
  const [deletionReadinessError, setDeletionReadinessError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [savingPix, setSavingPix] = useState(false);
  const [changingPassword, setChangingPassword] = useState(false);
  const [regeneratingRecoveryCodes, setRegeneratingRecoveryCodes] = useState(false);
  const [disablingTotp, setDisablingTotp] = useState(false);
  const [showDisableTotp, setShowDisableTotp] = useState(false);
  const [showDeleteAccount, setShowDeleteAccount] = useState(false);
  const [deletePassword, setDeletePassword] = useState("");
  const [deletingAccount, setDeletingAccount] = useState(false);
  const [pixKey, setPixKey] = useState("");
  const [pixName, setPixName] = useState("");
  const [pixCity, setPixCity] = useState("");
  const [pixErrors, setPixErrors] = useState<Record<string, string>>({});
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [disablePassword, setDisablePassword] = useState("");
  const actionRef = useRef<HTMLElement | null>(null);
  const pixRef = useRef<HTMLInputElement>(null);
  const pixNameRef = useRef<HTMLInputElement>(null);
  const pixCityRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);
  const recoveryRef = useRef<HTMLButtonElement>(null);
  const recoveryRequestInFlight = useRef(false);
  const disableTotpRef = useRef<HTMLInputElement>(null);
  const deleteAccountRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadError(null);
    setSummary(null);
    setDeletionReadiness(null);
    setDeletionReadinessError(null);
    const [summaryResult, readinessResult] = await Promise.allSettled([
      apiRequest(apiClient.GET("/api/v1/security")),
      apiRequest(apiClient.GET("/api/v1/security/account-deletion-readiness"))
    ]);
    if (summaryResult.status === "rejected") {
      setLoadError(messageFor(summaryResult.reason, "Não foi possível carregar as configurações de segurança."));
      setLoading(false);
      return;
    }
    setSummary(summaryResult.value.data);
    setPixKey(summaryResult.value.data.profile.pix_key ?? "");
    setPixName(summaryResult.value.data.profile.pix_merchant_name ?? "");
    setPixCity(summaryResult.value.data.profile.pix_merchant_city ?? "");
    if (readinessResult.status === "fulfilled") setDeletionReadiness(readinessResult.value.data);
    else setDeletionReadinessError(messageFor(readinessResult.reason, "Não foi possível verificar se a conta pode ser excluída."));
    setLoading(false);
  }, []);

  useEffect(() => { document.title = "Segurança - Rentivo"; void load(); }, [load]);
  useEffect(() => { if (actionError) actionRef.current?.focus(); }, [actionError]);

  function startAction(focusTarget: HTMLElement | null = null) {
    actionRef.current = focusTarget;
    setActionError(null);
    setMessage(null);
  }

  async function updatePix(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const validation = validatePix({ city: pixCity, key: pixKey, name: pixName });
    startAction(pixRef.current);
    if ("errors" in validation) {
      setPixErrors(validation.errors);
      const first = ["key", "name", "city"].find((field) => validation.errors[field]);
      if (first === "key") pixRef.current?.focus();
      else if (first === "name") pixNameRef.current?.focus();
      else pixCityRef.current?.focus();
      return;
    }
    setPixErrors({});
    setSavingPix(true);
    try {
      const { data } = await apiRequest(
        apiClient.POST("/api/v1/security/pix", {
          body: {
            pix_key: validation.value.key,
            pix_merchant_city: validation.value.city,
            pix_merchant_name: validation.value.name
          }
        })
      );
      setSummary((value) => ({ ...value!, profile: data.profile }));
      setMessage("Dados do PIX atualizados.");
    } catch (caught: unknown) {
      setActionError(messageFor(caught, "Não foi possível atualizar os dados do PIX."));
    } finally {
      setSavingPix(false);
    }
  }

  async function changePassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    startAction(passwordRef.current);
    const passwordError = passwordValidationError(currentPassword, newPassword, confirmPassword);
    if (passwordError) {
      setActionError(passwordError);
      return;
    }
    if (newPassword !== confirmPassword) {
      setActionError("As senhas não coincidem.");
      return;
    }
    setChangingPassword(true);
    try {
      const { response } = await apiRequest(
        apiClient.POST("/api/v1/security/change-password", {
          body: {
            confirm_password: confirmPassword,
            current_password: currentPassword,
            new_password: newPassword
          }
        })
      );
      pushAnalyticsFromResponse(response);
      setCurrentPassword(""); setNewPassword(""); setConfirmPassword("");
      setMessage("Senha alterada com sucesso!");
    } catch (caught: unknown) {
      setActionError(messageFor(caught, "Não foi possível alterar a senha."));
    } finally {
      setChangingPassword(false);
    }
  }

  async function regenerateRecoveryCodes() {
    if (recoveryRequestInFlight.current) return;
    recoveryRequestInFlight.current = true;
    setRegeneratingRecoveryCodes(true);
    startAction(recoveryRef.current);
    try {
      const { data, response } = await apiRequest(
        apiClient.POST("/api/v1/security/recovery-codes/regenerate")
      );
      pushAnalyticsFromResponse(response);
      navigate("/security/recovery-codes", { state: { recoveryCodes: data.recovery_codes } });
    } catch (caught: unknown) {
      setActionError(messageFor(caught, "Não foi possível regenerar os códigos de recuperação."));
    } finally {
      recoveryRequestInFlight.current = false;
      setRegeneratingRecoveryCodes(false);
    }
  }

  async function disableTotp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    startAction(disableTotpRef.current);
    const passwordError = passwordValidationError(disablePassword);
    if (passwordError) {
      setActionError(passwordError);
      return;
    }
    setDisablingTotp(true);
    try {
      const { response } = await apiRequest(
        apiClient.POST("/api/v1/security/totp/disable", {
          body: { password: disablePassword }
        })
      );
      pushAnalyticsFromResponse(response);
      await logout().catch(() => undefined);
    } catch (caught: unknown) {
      setActionError(messageFor(caught, "Não foi possível desativar o TOTP."));
    } finally {
      setDisablingTotp(false);
    }
  }

  async function deleteAccount(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    startAction(deleteAccountRef.current);
    const passwordError = passwordValidationError(deletePassword);
    if (passwordError) {
      setActionError(passwordError);
      return;
    }
    setDeletingAccount(true);
    try {
      const { response } = await apiRequest(
        apiClient.POST("/api/v1/security/delete-account", {
          body: { password: deletePassword }
        })
      );
      pushAnalyticsFromResponse(response);
      await logout().catch(() => undefined);
    } catch (caught: unknown) {
      setActionError(messageFor(caught, "Não foi possível excluir a conta."));
    } finally {
      setDeletingAccount(false);
    }
  }

  async function registerPasskey(name: string) {
    startAction();
    const { data: begin } = await apiRequest(
      apiClient.POST("/api/v1/security/passkeys/register/begin")
    );
    const credential = await createPasskey(begin.options);
    if (!credential) throw new DOMException("Operação cancelada.", "NotAllowedError");
    const { data, response } = await apiRequest(
      apiClient.POST("/api/v1/security/passkeys/register/complete", {
        body: { challenge_id: begin.challenge_id, credential, name }
      })
    );
    pushAnalyticsFromResponse(response);
    setSummary((value) => ({ ...value!, passkeys: [...value!.passkeys, data] }));
    setMessage("Passkey cadastrada.");
  }

  async function deletePasskey(uuid: string) {
    startAction();
    const { response } = await apiRequest(
      apiClient.DELETE("/api/v1/security/passkeys/{passkey_uuid}", {
        params: { path: { passkey_uuid: uuid } }
      })
    );
    pushAnalyticsFromResponse(response);
  }

  if (loading) {
    return (
      <div aria-busy="true" className="security-center security-center--loading">
        <div className="security-loading__heading" />
        <div className="security-loading__surface" />
        <p role="status">Carregando segurança…</p>
      </div>
    );
  }
  if (!summary) {
    return (
      <div className="security-center security-center--error">
        <CircleAlert aria-hidden="true" size={28} />
        <h1>Segurança</h1>
        <div className="toast toast--danger" role="alert">{loadError}</div>
        <button className="btn btn--primary" onClick={() => void load()} type="button">Tentar novamente</button>
      </div>
    );
  }

  const pixIncomplete = !summary.profile.pix_key || !summary.profile.pix_merchant_name || !summary.profile.pix_merchant_city;
  const passkeyStatus = summary.passkeys.length === 0
    ? "Nenhuma chave de acesso"
    : `${summary.passkeys.length} ${summary.passkeys.length === 1 ? "chave de acesso" : "chaves de acesso"}`;
  return (
    <div className="security-center">
      <header className="security-center__header">
        <div className="security-center__title">
          <span aria-hidden="true" className="security-center__mark"><ShieldCheck size={28} /></span>
          <div>
            <h1>Segurança</h1>
            <p>Proteja o acesso, defina o PIX pessoal e controle as integrações da sua conta.</p>
          </div>
        </div>
        <div aria-label="Resumo de segurança" className="security-status" role="list">
          <div className={`security-status__item ${pixIncomplete ? "is-pending" : "is-ready"}`} role="listitem">
            <Landmark aria-hidden="true" size={19} />
            <span><small>Recebimento</small><strong>{pixIncomplete ? "PIX pendente" : "PIX configurado"}</strong></span>
          </div>
          <div className={`security-status__item ${summary.totp.enabled ? "is-ready" : "is-pending"}`} role="listitem">
            <KeyRound aria-hidden="true" size={19} />
            <span><small>Autenticador</small><strong>{summary.totp.enabled ? "Aplicativo autenticador ativo" : "Aplicativo autenticador desativado"}</strong></span>
          </div>
          <div className={`security-status__item ${summary.passkeys.length ? "is-ready" : "is-neutral"}`} role="listitem">
            <Fingerprint aria-hidden="true" size={19} />
            <span><small>Passkeys</small><strong>{passkeyStatus}</strong></span>
          </div>
        </div>
      </header>

      <nav aria-label="Atalhos de segurança" className="security-shortcuts">
        <a href="#recebimento">Recebimento</a>
        <a href="#acesso">Acesso</a>
        <a href="#integracoes">Integrações</a>
        <a href="#conta">Conta</a>
      </nav>

      {summary.mfa.setup_required ? <div className="mfa-enforcement-banner">Sua organização exige autenticação multifator. Configure o TOTP ou uma passkey para continuar.</div> : null}
      <div aria-live="polite" className="security-feedback">
        {actionError ? <div className="toast toast--danger" role="alert">{actionError}</div> : null}
        {message ? <div className="toast toast--success" role="status">{message}</div> : null}
      </div>

      <div className="security-surface">
        <section aria-labelledby="recebimento-title" className="security-section security-section--pix" id="recebimento">
          <div className="security-section__heading">
            <div>
              <h2 id="recebimento-title">PIX pessoal</h2>
              <p>Usado nas faturas de cobranças pessoais que não têm um PIX próprio.</p>
            </div>
            <span className={`security-section__state ${pixIncomplete ? "is-pending" : "is-ready"}`}>{pixIncomplete ? "Configuração pendente" : "Pronto para receber"}</span>
          </div>
          {pixIncomplete ? <div className="security-inline-notice" role="alert">Preencha todos os campos abaixo para poder gerar faturas das cobranças pessoais.</div> : null}
          <form className="security-pix-form" onSubmit={(event) => void updatePix(event)}>
            <div className="field security-pix-form__key"><label className="field-label" htmlFor="pix_key">Chave PIX</label><input aria-invalid={Boolean(pixErrors.key)} autoComplete="off" className="field-input" id="pix_key" name="pix_key" onChange={(event) => { setPixKey(event.target.value); setPixErrors({}); }} ref={pixRef} spellCheck={false} value={pixKey} />{pixErrors.key ? <span className="field-error">{pixErrors.key}</span> : <span className="field-hint">Para celular, inclua +55. Sem o prefixo, 11 dígitos são tratados como CPF.</span>}</div>
            <div className="field"><label className="field-label" htmlFor="pix_merchant_name">Nome do recebedor</label><input aria-invalid={Boolean(pixErrors.name)} autoComplete="off" className="field-input" id="pix_merchant_name" name="pix_merchant_name" onChange={(event) => { setPixName(limitApiCharacters(event.target.value, 25)); setPixErrors({}); }} ref={pixNameRef} value={pixName} />{pixErrors.name ? <span className="field-error">{pixErrors.name}</span> : <span className="field-hint">Até 25 caracteres.</span>}</div>
            <div className="field"><label className="field-label" htmlFor="pix_merchant_city">Cidade do recebedor</label><input aria-invalid={Boolean(pixErrors.city)} autoComplete="off" className="field-input" id="pix_merchant_city" name="pix_merchant_city" onChange={(event) => { setPixCity(limitApiCharacters(event.target.value, 15)); setPixErrors({}); }} ref={pixCityRef} value={pixCity} />{pixErrors.city ? <span className="field-error">{pixErrors.city}</span> : <span className="field-hint">Até 15 caracteres, sem acentos.</span>}</div>
            <div className="security-pix-form__action"><SubmitButton className="btn btn--primary btn--sm" loading={savingPix}>Salvar Dados PIX</SubmitButton></div>
          </form>
        </section>

        <section aria-labelledby="acesso-title" className="security-section security-section--access" id="acesso">
          <div className="security-section__heading">
            <div><h2 id="acesso-title">Acesso à conta</h2><p>Combine um aplicativo autenticador, passkeys e uma senha exclusiva.</p></div>
          </div>
          <div className="security-auth-grid">
            <article className="security-auth-method">
              <div className="security-auth-method__heading"><KeyRound aria-hidden="true" size={20} /><div><h3>Aplicativo autenticador</h3><p>{summary.totp.enabled ? "Ativo nesta conta" : "Ainda não configurado"}</p></div></div>
              {summary.totp.enabled ? (
                <>
                  <p className="security-auth-method__metric"><strong>{summary.totp.recovery_codes_remaining}</strong> códigos de recuperação disponíveis</p>
                  {summary.totp.recovery_codes_remaining < 3 ? <p className="security-auth-method__warning">Poucos códigos restantes. Recomendamos regenerar seus códigos.</p> : null}
                  <div className="security-auth-method__actions">
                    <button aria-busy={regeneratingRecoveryCodes} className="btn btn--sm" disabled={regeneratingRecoveryCodes} onClick={() => void regenerateRecoveryCodes()} ref={recoveryRef} type="button">Regenerar Códigos de Recuperação</button>
                    {!showDisableTotp ? <button className="btn btn--sm btn--danger" onClick={() => setShowDisableTotp(true)} type="button">Desativar TOTP</button> : null}
                  </div>
                  {showDisableTotp ? <form className="security-inline-form" onSubmit={(event) => void disableTotp(event)}><div className="field"><label className="field-label" htmlFor="disable-totp-password">Confirme sua senha para desativar</label><input autoComplete="current-password" className="field-input" id="disable-totp-password" name="disable_totp_password" onChange={(event) => setDisablePassword(event.target.value)} ref={disableTotpRef} required type="password" value={disablePassword} /></div><SubmitButton className="btn btn--danger btn--sm" loading={disablingTotp}>Confirmar Desativação</SubmitButton></form> : null}
                </>
              ) : (
                <Link className="btn btn--primary btn--sm" to="/security/totp/setup">Configurar TOTP</Link>
              )}
            </article>
            <PasskeyManager onDelete={deletePasskey} onRegister={registerPasskey} onSessionRevoked={() => { void logout().catch(() => undefined); }} organizationEnforced={summary.mfa.organization_enforced} passkeys={summary.passkeys} />
          </div>

          <div className="security-password">
            <div className="security-password__heading"><div><h3>Senha</h3><p>Troque a senha sem sair desta página.</p></div><span>Use uma senha forte e exclusiva</span></div>
            <form className="security-password__form" onSubmit={(event) => void changePassword(event)}>
              <div className="field"><label className="field-label" htmlFor="current_password">Senha atual</label><input autoComplete="current-password" className="field-input" id="current_password" name="current_password" onChange={(event) => setCurrentPassword(event.target.value)} ref={passwordRef} required type="password" value={currentPassword} /></div>
              <div className="field"><label className="field-label" htmlFor="new_password">Nova senha</label><input autoComplete="new-password" className="field-input" id="new_password" name="new_password" onChange={(event) => setNewPassword(event.target.value)} required type="password" value={newPassword} /></div>
              <div className="field"><label className="field-label" htmlFor="confirm_password">Confirmar nova senha</label><input autoComplete="new-password" className="field-input" id="confirm_password" name="confirm_password" onChange={(event) => setConfirmPassword(event.target.value)} required type="password" value={confirmPassword} /></div>
              <div className="security-password__action"><SubmitButton className="btn btn--primary btn--sm" loading={changingPassword}>Alterar Senha</SubmitButton></div>
            </form>
          </div>
        </section>

        <div id="integracoes"><ApiKeySection /></div>

        <section aria-labelledby="conta-title" className="security-section security-section--danger" id="conta">
          <div className="security-section__heading">
            <div><h2 id="conta-title">Excluir conta</h2><p>Remove cobranças e dados pessoais de forma permanente.</p></div>
            {deletionReadiness?.can_delete ? <span className="security-section__state is-danger">Ação permanente</span> : null}
          </div>
          <p className="security-danger-copy">Registros exigidos por lei podem ser retidos conforme a <Link to="/privacy">Política de Privacidade</Link>. Se você entra apenas com o Google, defina uma senha antes em <Link to="/forgot-password">Esqueci minha senha</Link>.</p>
          {deletionReadinessError ? <div className="security-danger-actions"><div className="security-inline-notice" role="alert">{deletionReadinessError}</div><button className="btn btn--sm" onClick={() => void load()} type="button">Verificar novamente</button></div> : null}
          {deletionReadiness && !deletionReadiness.can_delete ? <div className="security-inline-notice" role="alert">{deletionReadiness.reason === "sole_organization_admin" ? "Transfira a administração ou exclua suas organizações antes de excluir a conta." : "A exclusão da conta não está disponível no momento."}</div> : null}
          {deletionReadiness?.can_delete && !showDeleteAccount ? <button className="btn btn--sm btn--danger" onClick={() => setShowDeleteAccount(true)} type="button">Excluir conta</button> : null}
          {deletionReadiness?.can_delete && showDeleteAccount ? <form className="security-delete-form" onSubmit={(event) => void deleteAccount(event)}>
            <div className="field"><label className="field-label" htmlFor="delete-account-password">Confirme sua senha para excluir a conta</label><input autoComplete="current-password" className="field-input" id="delete-account-password" name="delete_account_password" onChange={(event) => setDeletePassword(event.target.value)} ref={deleteAccountRef} required type="password" value={deletePassword} /></div>
            <SubmitButton className="btn btn--danger btn--sm" loading={deletingAccount}>Excluir minha conta permanentemente</SubmitButton>
          </form> : null}
        </section>
      </div>
    </div>
  );
}
