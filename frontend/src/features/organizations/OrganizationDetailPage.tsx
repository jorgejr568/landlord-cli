import { Building2, ChevronDown, ChevronLeft, LockKeyhole, Mail, Plus, ShieldCheck, UsersRound } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent, type KeyboardEvent as ReactKeyboardEvent } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import { FieldError } from "../../components/FieldError";
import { LoadError, LoadingState } from "../../components/PageState";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage, normalizedFieldErrors } from "../../lib/api/errors";
import type { components } from "../../lib/api/schema";
import { formatBrl } from "../../lib/format";
import { limitApiCharacters } from "../../lib/textLimits";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { useAuth } from "../auth/AuthProvider";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import { OrganizationMembers } from "./OrganizationMembers";

import "./OrganizationDetailPage.css";

type Detail = components["schemas"]["OrganizationLoginDetailResponse"];
type Member = components["schemas"]["OrganizationMemberResponse"];
type MemberRole = Member["role"];
type Billing = components["schemas"]["BillingListItemResponse"];
type BillingList = components["schemas"]["BillingListResponse"];
type BillingStats = components["schemas"]["BillingStatsResponse"];
type Invite = components["schemas"]["OrganizationInviteResponse"];
type ActiveAction = { controller: AbortController; generation: number; key: string };
type OrganizationView = "access" | "billings" | "team";

interface Confirmation {
  body: string;
  confirm: () => void;
  label: string;
  title: string;
  variant?: "danger" | "primary";
}

const ROLE_LABELS: Record<MemberRole, string> = {
  admin: "Admin",
  manager: "Gerente",
  viewer: "Visualizador"
};
const ROLE_TAGS: Record<MemberRole, string> = {
  admin: "tag--fixed",
  manager: "tag--variable",
  viewer: "tag--draft"
};
const INVITE_META: Record<Invite["status"], { className: string; label: string }> = {
  accepted: { className: "tag--paid", label: "Aceito" },
  declined: { className: "tag--overdue", label: "Recusado" },
  pending: { className: "tag--pending", label: "Pendente" }
};
const BILL_STATUS: Record<string, { className: string; label: string }> = {
  cancelled: { className: "tag--cancelled", label: "Cancelado" },
  delayed_payment: { className: "tag--delayed", label: "Pag. Atrasado" },
  draft: { className: "tag--draft", label: "Rascunho" },
  paid: { className: "tag--paid", label: "Pago" },
  published: { className: "tag--published", label: "Publicado" },
  sent: { className: "tag--sent", label: "Enviado" }
};

function plural(count: number, singular: string, multiple: string): string {
  return count === 1 ? singular : multiple;
}

function Stats({ stats }: { stats: BillingStats }) {
  return (
    <dl aria-label={`Resumo financeiro de ${stats.year}`} className="organization-finance-strip">
      <div><dt>Faturado em {stats.year}</dt><dd>{formatBrl(stats.expected)}</dd><small>{stats.billed_count} {plural(stats.billed_count, "fatura", "faturas")} no ano</small></div>
      <div className="organization-finance-strip__received"><dt>Recebido</dt><dd>{formatBrl(stats.received)}</dd><small>{stats.paid_count} {plural(stats.paid_count, "fatura paga", "faturas pagas")}</small></div>
      <div><dt>Pendente</dt><dd>{formatBrl(stats.pending)}</dd><small>{stats.pending_count} aguardando</small></div>
      <div className="organization-finance-strip__overdue"><dt>Em atraso</dt><dd>{formatBrl(stats.overdue)}</dd><small>{stats.overdue_count} {plural(stats.overdue_count, "vencida", "vencidas")}</small></div>
    </dl>
  );
}

function BillingTable({ billings }: { billings: Billing[] }) {
  return (
    <div className="organization-billing-table">
      <table className="table">
        <thead><tr><th>Imóvel</th><th className="center">Itens</th><th className="num">Fatura atual</th><th className="center">Status</th><th /></tr></thead>
        <tbody>
          {billings.map((billing) => {
            const status = billing.current_bill ? BILL_STATUS[billing.current_bill.status] : null;
            return (
              <tr key={billing.uuid}>
                <td className="table__primary"><Link to={`/billings/${billing.uuid}`}>{billing.name}</Link></td>
                <td className="center mono" data-label="Itens">{billing.item_count}</td>
                <td className="num" data-label="Fatura atual">{billing.current_bill ? formatBrl(billing.current_bill.total_amount) : <span className="muted">Sem valor</span>}</td>
                <td className="center" data-label="Status">{status ? <span className={`tag ${status.className}`}>{status.label}</span> : <span className="tag tag--draft">Sem fatura</span>}</td>
                <td className="num"><Link aria-label={`Abrir cobrança ${billing.name}`} className="btn btn--sm" to={`/billings/${billing.uuid}`}>Abrir</Link></td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export function OrganizationDetailPage() {
  const { orgUuid = "" } = useParams<{ orgUuid: string }>();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { refreshSession } = useAuth();
  const [detail, setDetail] = useState<Detail | null>(null);
  const [billingList, setBillingList] = useState<BillingList | null>(null);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [success, setSuccess] = useState("");
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const [inviteEmail, setInviteEmail] = useState("");
  const [inviteRole, setInviteRole] = useState<MemberRole>("viewer");
  const [inviteErrors, setInviteErrors] = useState<Record<string, string>>({});
  const [transferUuid, setTransferUuid] = useState("");
  const [activeAction, setActiveAction] = useState("");
  const [actionsOpen, setActionsOpen] = useState(false);
  const activeActionRef = useRef<ActiveAction | null>(null);
  const generationRef = useRef(0);
  const pendingFocusRef = useRef<(() => HTMLElement | null) | null>(null);
  const inviteEmailRef = useRef<HTMLInputElement>(null);
  const membersHeadingRef = useRef<HTMLHeadingElement>(null);
  const transferRef = useRef<HTMLButtonElement>(null);
  const deleteRef = useRef<HTMLButtonElement>(null);
  const mfaRef = useRef<HTMLButtonElement>(null);
  const actionsButtonRef = useRef<HTMLButtonElement>(null);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);

  const load = useCallback(async (signal?: AbortSignal, generation = generationRef.current) => {
    setLoadError("");
    try {
      const [organizationResult, billingResult] = await Promise.all([
        apiRequest(apiClient.GET("/api/v1/organizations/{organization_uuid}", {
          params: { path: { organization_uuid: orgUuid } }, signal
        })),
        apiRequest(apiClient.GET("/api/v1/billings", { signal }))
      ]);
      if (!signal?.aborted && generation === generationRef.current) {
        setDetail(organizationResult.data as Detail);
        setBillingList(billingResult.data);
      }
    } catch (caught) {
      if (!signal?.aborted && generation === generationRef.current) {
        setLoadError(errorMessage(caught, "Não foi possível carregar a organização."));
      }
    }
  }, [orgUuid]);

  useEffect(() => {
    const generation = ++generationRef.current;
    const controller = new AbortController();
    activeActionRef.current?.controller.abort();
    activeActionRef.current = null;
    pendingFocusRef.current = null;
    setActiveAction("");
    setDetail(null);
    setBillingList(null);
    setLoadError("");
    setActionError("");
    setSuccess("");
    setConfirmation(null);
    setInviteErrors({});
    setInviteEmail("");
    setInviteRole("viewer");
    setTransferUuid("");
    setActionsOpen(false);
    void load(controller.signal, generation);
    return () => controller.abort();
  }, [load]);
  useEffect(() => () => {
    generationRef.current += 1;
    activeActionRef.current?.controller.abort();
    activeActionRef.current = null;
    pendingFocusRef.current = null;
  }, []);
  useEffect(() => {
    if (!actionsOpen) return;
    const close = () => setActionsOpen(false);
    const closeWithKeyboard = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setActionsOpen(false);
      actionsButtonRef.current?.focus();
    };
    document.addEventListener("click", close);
    document.addEventListener("keydown", closeWithKeyboard);
    return () => {
      document.removeEventListener("click", close);
      document.removeEventListener("keydown", closeWithKeyboard);
    };
  }, [actionsOpen]);
  useDocumentTitle(detail ? `${detail.name} - Rentivo` : "Organização - Rentivo");

  const focusLater = (control: HTMLElement | null) => { pendingFocusRef.current = () => control; };
  const beginAction = () => { setActionError(""); setSuccess(""); };
  const startAction = (key: string): ActiveAction | null => {
    if (activeActionRef.current) return null;
    const action = { controller: new AbortController(), generation: generationRef.current, key };
    activeActionRef.current = action;
    setActiveAction(key);
    beginAction();
    return action;
  };
  const isCurrentAction = (action: ActiveAction) => (
    activeActionRef.current === action
    && !action.controller.signal.aborted
    && action.generation === generationRef.current
  );
  const finishAction = (action: ActiveAction) => {
    if (activeActionRef.current !== action) return;
    activeActionRef.current = null;
    setActiveAction("");
    const resolveControl = pendingFocusRef.current;
    pendingFocusRef.current = null;
    if (resolveControl) setTimeout(() => resolveControl()?.focus(), 0);
  };
  const focusMemberControl = (userId: number) => {
    pendingFocusRef.current = () => document.querySelector<HTMLElement>(`[data-member-id="${userId}"] button[data-member-control]`);
  };
  const runAction = async <T,>(
    key: string,
    request: (signal: AbortSignal) => Promise<T>,
    onSuccess: (result: T) => void,
    onError: (caught: unknown) => void
  ) => {
    const action = startAction(key);
    if (!action) return;
    try {
      const result = await request(action.controller.signal);
      if (isCurrentAction(action)) onSuccess(result);
    } catch (caught) {
      if (isCurrentAction(action)) onError(caught);
    } finally {
      finishAction(action);
    }
  };

  const changeRole = async (member: Member, role: MemberRole, control: HTMLSelectElement) => {
    await runAction(
      `member-role:${member.user_id}`,
      (signal) => apiRequest(apiClient.PATCH("/api/v1/organizations/{organization_uuid}/members/{user_id}", {
        body: { role },
        params: { path: { organization_uuid: orgUuid, user_id: member.user_id } },
        signal
      })),
      ({ data, response }) => {
        pushAnalyticsFromResponse(response);
        setDetail((current) => ({ ...current as Detail, members: (current as Detail).members.map((item) => item.user_id === member.user_id ? data : item) }));
        setSuccess("Papel atualizado com sucesso!");
      },
      (caught) => {
        setActionError(errorMessage(caught, "Não foi possível atualizar o papel."));
        focusLater(control);
      }
    );
  };

  const removeMember = async (member: Member) => {
    const removableMembers = (detail as Detail).members.filter((item) => !item.is_current_user);
    const removedIndex = removableMembers.findIndex((item) => item.user_id === member.user_id);
    const remainingMembers = removableMembers.filter((item) => item.user_id !== member.user_id);
    const focusMember = remainingMembers[Math.min(removedIndex, remainingMembers.length - 1)];
    await runAction(
      `member-remove:${member.user_id}`,
      (signal) => apiRequest(apiClient.DELETE("/api/v1/organizations/{organization_uuid}/members/{user_id}", {
        params: { path: { organization_uuid: orgUuid, user_id: member.user_id } },
        signal
      })),
      ({ response }) => {
        pushAnalyticsFromResponse(response);
        setDetail((current) => ({ ...current as Detail, members: (current as Detail).members.filter((item) => item.user_id !== member.user_id) }));
        setSuccess("Membro removido.");
        if (focusMember) focusMemberControl(focusMember.user_id);
        else focusLater(membersHeadingRef.current);
      },
      (caught) => {
        setActionError(errorMessage(caught, "Não foi possível remover o membro."));
        focusMemberControl(member.user_id);
      }
    );
  };

  const sendInvite = async (event: FormEvent) => {
    event.preventDefault();
    await runAction(
      "invite-create",
      (signal) => {
        setInviteErrors({});
        return apiRequest(apiClient.POST("/api/v1/organizations/{organization_uuid}/invites", {
          body: { email: inviteEmail.trim().toLowerCase(), role: inviteRole },
          params: { path: { organization_uuid: orgUuid } },
          signal
        }));
      },
      ({ data, response }) => {
        pushAnalyticsFromResponse(response);
        setDetail((current) => ({ ...current as Detail, invites: [...(current as Detail).invites, data] }));
        setInviteEmail("");
        setInviteRole("viewer");
        setSuccess("Convite enviado com sucesso!");
      },
      (caught) => {
        if (caught instanceof ApiError) {
          setInviteErrors(normalizedFieldErrors(caught));
          setActionError(Object.keys(caught.fields).length ? "" : caught.message);
        } else setActionError("Não foi possível enviar o convite.");
        focusLater(inviteEmailRef.current);
      }
    );
  };

  const updateMfa = async () => {
    await runAction(
      "mfa",
      async (signal) => {
        const result = await apiRequest(apiClient.PUT("/api/v1/organizations/{organization_uuid}/mfa-policy", {
          body: { enforce_mfa: !(detail as Detail).enforce_mfa },
          params: { path: { organization_uuid: orgUuid } },
          signal
        }));
        await refreshSession().catch(() => undefined);
        return result;
      },
      ({ data, response }) => {
        pushAnalyticsFromResponse(response);
        setDetail((current) => ({ ...current as Detail, enforce_mfa: data.enforce_mfa }));
        if (data.mfa_setup_required) navigate("/security/totp/setup");
        else setSuccess("Política de MFA atualizada.");
      },
      (caught) => {
        setActionError(errorMessage(caught, "Não foi possível atualizar a política de MFA."));
        focusLater(mfaRef.current);
      }
    );
  };

  const transferBilling = async () => {
    await runAction(
      "billing-transfer",
      (signal) => apiRequest(apiClient.POST("/api/v1/organizations/{organization_uuid}/billing-transfers", {
        body: { billing_uuid: transferUuid },
        params: { path: { organization_uuid: orgUuid } },
        signal
      })),
      ({ response }) => {
        pushAnalyticsFromResponse(response);
        setBillingList((current) => ({
          ...current as BillingList,
          items: (current as BillingList).items.map((billing) => billing.uuid === transferUuid ? { ...billing, capabilities: { ...billing.capabilities, can_transfer: false }, owner: { name: (detail as Detail).name, type: "organization", uuid: orgUuid } } : billing)
        }));
        setTransferUuid("");
        setSuccess("Cobrança transferida com sucesso!");
      },
      (caught) => {
        setActionError(errorMessage(caught, "Não foi possível transferir a cobrança."));
        focusLater(transferRef.current);
      }
    );
  };

  const deleteOrganization = async () => {
    await runAction(
      "organization-delete",
      (signal) => apiRequest(apiClient.DELETE("/api/v1/organizations/{organization_uuid}", {
        params: { path: { organization_uuid: orgUuid } },
        signal
      })),
      ({ response }) => {
        pushAnalyticsFromResponse(response);
        navigate("/organizations/");
      },
      (caught) => {
        setActionError(errorMessage(caught, "Não foi possível excluir a organização."));
        focusLater(deleteRef.current);
      }
    );
  };

  if (loadError) return <LoadError message={loadError} onRetry={() => void load()} />;
  if (!detail || detail.uuid !== orgUuid || !billingList) return <LoadingState label="Carregando organização…" />;

  const organizationBillings = billingList.items.filter((billing) => billing.owner.type === "organization" && billing.owner.uuid === orgUuid);
  const personalBillings = billingList.items.filter((billing) => billing.owner.type === "user" && billing.capabilities.can_transfer);
  const canManageMembers = detail.capabilities.can_invite;
  const requestedView = searchParams.get("view");
  const selectedView: OrganizationView = requestedView === "team" || requestedView === "access" ? requestedView : "billings";
  const views: OrganizationView[] = ["billings", "team", "access"];
  const changeView = (view: OrganizationView) => {
    const next = new URLSearchParams(searchParams);
    if (view === "billings") next.delete("view");
    else next.set("view", view);
    setSearchParams(next, { replace: true });
  };
  const handleTabKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, view: OrganizationView) => {
    if (!(["ArrowLeft", "ArrowRight", "Home", "End"] as string[]).includes(event.key)) return;
    event.preventDefault();
    const currentIndex = views.indexOf(view);
    const nextIndex = event.key === "Home" ? 0
      : event.key === "End" ? views.length - 1
        : (currentIndex + (event.key === "ArrowRight" ? 1 : -1) + views.length) % views.length;
    changeView(views[nextIndex]);
    tabRefs.current[nextIndex]?.focus();
  };
  const memberCount = `${detail.members.length} ${plural(detail.members.length, "pessoa", "pessoas")}`;
  const billingCount = `${organizationBillings.length} ${plural(organizationBillings.length, "cobrança", "cobranças")}`;
  const roleGuidance = detail.capabilities.can_create_billing
    ? "Você pode criar cobranças e gerar faturas. Apenas administradores alteram membros e configurações."
    : "Seu acesso é somente leitura. Gerentes e administradores cuidam das cobranças e configurações.";

  return (
    <>
      <Link className="crumb" to="/organizations/"><ChevronLeft aria-hidden="true" size={16} strokeWidth={2.5} />Organizações</Link>
      {success ? <div className="toast toast--success" role="status">{success}</div> : null}
      {actionError ? <div className="toast toast--danger" role="alert">{actionError}</div> : null}
      <article aria-label={`Organização ${detail.name}`} className="organization-workspace">
        <header className="organization-workspace__header">
          <div className="organization-workspace__identity">
            <span aria-hidden="true" className="organization-workspace__mark">{detail.name.slice(0, 1).toLocaleUpperCase("pt-BR")}</span>
            <div>
              <div className="organization-workspace__title-row">
                <h1 className="pagehead__title">{detail.name}</h1>
                <span className={`tag ${ROLE_TAGS[detail.current_role]}`}>{ROLE_LABELS[detail.current_role]}</span>
              </div>
              <p>Espaço compartilhado para cobranças, pessoas e segurança.</p>
            </div>
          </div>
          <div className="organization-workspace__toolbar">
            {detail.capabilities.can_create_billing ? <Link className="btn btn--primary btn--sm" to="/billings/create"><Plus aria-hidden="true" size={15} />Criar cobrança</Link> : null}
            {detail.capabilities.can_manage ? <div className={`btn-dropdown organization-action-menu${actionsOpen ? " open" : ""}`}>
              <button aria-controls="organization-actions-menu" aria-expanded={actionsOpen} aria-label="Ações da organização" className="btn btn--sm btn-dropdown-toggle" onClick={(event) => { event.stopPropagation(); setActionsOpen((open) => !open); }} ref={actionsButtonRef} type="button">Ações <ChevronDown aria-hidden="true" size={14} /></button>
              <div className="btn-dropdown-menu" id="organization-actions-menu" onClick={(event) => event.stopPropagation()}>
                <Link className="btn-dropdown-item" onClick={() => setActionsOpen(false)} to={`/organizations/${orgUuid}/edit`}>Editar organização</Link>
                <Link className="btn-dropdown-item" onClick={() => setActionsOpen(false)} to={`/themes/organization/${orgUuid}`}>Tema da organização</Link>
              </div>
            </div> : null}
          </div>
          <dl className="organization-workspace__summary">
            <div><dt>Cobranças</dt><dd>{billingCount}</dd></div>
            <div><dt>Equipe</dt><dd>{memberCount}</dd></div>
            <div><dt>Segurança</dt><dd>{detail.enforce_mfa ? "MFA obrigatório" : "MFA opcional"}</dd></div>
          </dl>
        </header>

        <nav aria-label="Áreas da organização" className="organization-workspace__tabs" role="tablist">
          <button aria-controls="organization-billings-panel" aria-selected={selectedView === "billings"} id="organization-billings-tab" onClick={() => changeView("billings")} onKeyDown={(event) => handleTabKeyDown(event, "billings")} ref={(element) => { tabRefs.current[0] = element; }} role="tab" tabIndex={selectedView === "billings" ? 0 : -1} type="button">Cobranças <span>{organizationBillings.length}</span></button>
          <button aria-controls="organization-team-panel" aria-selected={selectedView === "team"} id="organization-team-tab" onClick={() => changeView("team")} onKeyDown={(event) => handleTabKeyDown(event, "team")} ref={(element) => { tabRefs.current[1] = element; }} role="tab" tabIndex={selectedView === "team" ? 0 : -1} type="button">Equipe <span>{detail.members.length}</span></button>
          <button aria-controls="organization-access-panel" aria-selected={selectedView === "access"} id="organization-access-tab" onClick={() => changeView("access")} onKeyDown={(event) => handleTabKeyDown(event, "access")} ref={(element) => { tabRefs.current[2] = element; }} role="tab" tabIndex={selectedView === "access" ? 0 : -1} type="button">Acesso</button>
        </nav>

        {selectedView === "billings" ? <section aria-labelledby="organization-billings-tab" className="organization-workspace__panel" id="organization-billings-panel" role="tabpanel">
          <div className="organization-workspace__section-heading">
            <div><h2>Cobranças da organização</h2><p>Acompanhe os imóveis e o estado da fatura atual.</p></div>
            <strong>{billingCount}</strong>
          </div>
          {organizationBillings.length && detail.capabilities.can_view_billing_stats && detail.stats ? <Stats stats={detail.stats} /> : null}
          {organizationBillings.length ? <BillingTable billings={organizationBillings} /> : <div className="organization-workspace__empty"><Building2 aria-hidden="true" size={24} /><div><h3>Nenhuma cobrança por aqui</h3><p>Crie uma cobrança para a organização ou transfira uma cobrança pessoal disponível.</p></div></div>}
          {detail.capabilities.can_manage && personalBillings.length ? <div className="organization-transfer-row">
            <div className="organization-transfer-row__copy"><Building2 aria-hidden="true" size={18} /><span><strong>Trazer cobrança pessoal</strong><small>A cobrança passa a pertencer a esta organização.</small></span></div>
            <div className="organization-transfer-row__controls"><label className="sr-only" htmlFor="transfer-billing">Cobrança para transferir</label><select aria-label="Cobrança para transferir" className="select" disabled={activeAction !== ""} id="transfer-billing" name="transfer-billing" onChange={(event) => setTransferUuid(event.target.value)} value={transferUuid}><option value="">Escolha uma cobrança</option>{personalBillings.map((billing) => <option key={billing.uuid} value={billing.uuid}>{billing.name}</option>)}</select><button className="btn btn--primary btn--sm" disabled={!transferUuid || activeAction !== ""} onClick={() => setConfirmation({ body: "A cobrança passará a pertencer a esta organização. Esta ação não pode ser desfeita.", confirm: () => void transferBilling(), label: "Transferir", title: "Transferir cobrança?", variant: "primary" })} ref={transferRef} type="button">{activeAction === "billing-transfer" ? "Transferindo…" : "Transferir cobrança"}</button></div>
          </div> : null}
        </section> : null}

        {selectedView === "team" ? <section aria-labelledby="organization-team-tab" className="organization-workspace__panel organization-team" id="organization-team-panel" role="tabpanel">
          <div className="organization-workspace__section-heading organization-team__heading">
            <div><h2>Pessoas e convites</h2><p>Defina quem participa e o que cada pessoa pode fazer.</p></div>
            <UsersRound aria-hidden="true" size={22} />
          </div>
          <div className={`organization-team__body${canManageMembers ? " organization-team__body--managed" : ""}`}>
            <div className="organization-team__directory">
              <OrganizationMembers canManageMembers={canManageMembers} disabled={activeAction !== ""} headingRef={membersHeadingRef} members={detail.members} onRemove={(member) => setConfirmation({ body: `Remover ${member.email} desta organização?`, confirm: () => void removeMember(member), label: "Remover membro", title: "Remover membro?" })} onRoleChange={(member, role, control) => void changeRole(member, role, control)} />
              {canManageMembers && detail.invites.length ? <section aria-labelledby="organization-invites-heading" className="organization-invites"><div className="organization-team__subheading"><h3 id="organization-invites-heading">Convites enviados</h3><span>{detail.invites.length}</span></div><div className="organization-invites__list">{detail.invites.map((invite) => { const status = INVITE_META[invite.status]; return <div className="organization-invite-row" key={invite.uuid}><span className="organization-invite-row__email">{invite.invited_email}</span><span className={`tag ${ROLE_TAGS[invite.role]}`}>{ROLE_LABELS[invite.role]}</span><span className={`tag ${status.className}`}>{status.label}</span></div>; })}</div></section> : null}
            </div>
            {canManageMembers ? <aside className="organization-invite-form" aria-labelledby="organization-invite-heading"><div className="organization-invite-form__heading"><Mail aria-hidden="true" size={19} /><div><h3 id="organization-invite-heading">Convidar membro</h3><p>O convite será enviado por e-mail.</p></div></div><form onSubmit={(event) => void sendInvite(event)}><div className="field"><label className="field__label" htmlFor="invite-email">E-mail</label><input aria-describedby={inviteErrors.email ? "invite-email-error" : undefined} autoComplete="off" className="input mono" disabled={activeAction !== ""} id="invite-email" inputMode="email" name="invite-email" onChange={(event) => setInviteEmail(limitApiCharacters(event.target.value, 320))} placeholder="nome@exemplo.com…" ref={inviteEmailRef} required spellCheck={false} type="email" value={inviteEmail} /><FieldError id="invite-email-error" message={inviteErrors.email} /></div><div className="field"><label className="field__label" htmlFor="invite-role">Papel</label><select aria-label="Papel do convite" className="select" disabled={activeAction !== ""} id="invite-role" name="invite-role" onChange={(event) => setInviteRole(event.target.value as MemberRole)} value={inviteRole}>{Object.entries(ROLE_LABELS).map(([role, label]) => <option key={role} value={role}>{label}</option>)}</select></div><button className="btn btn--primary btn--sm" disabled={activeAction !== ""} type="submit">{activeAction === "invite-create" ? "Enviando…" : "Enviar convite"}</button></form></aside> : null}
          </div>
        </section> : null}

        {selectedView === "access" ? <section aria-labelledby="organization-access-tab" className="organization-workspace__panel organization-access" id="organization-access-panel" role="tabpanel">
          <div className="organization-workspace__section-heading"><div><h2>Segurança da organização</h2><p>Revise seu acesso e a proteção exigida para a equipe.</p></div><ShieldCheck aria-hidden="true" size={22} /></div>
          <div className="organization-access__grid">
            <div className="organization-access__policy"><div className="organization-access__icon"><ShieldCheck aria-hidden="true" size={20} /></div><div><h3>Autenticação em 2 etapas</h3><p>{detail.enforce_mfa ? "Obrigatória para todas as pessoas da organização." : "Opcional para as pessoas desta organização."}</p></div>{detail.capabilities.can_manage ? <button aria-checked={detail.enforce_mfa} aria-label={detail.enforce_mfa ? "Desativar exigência de MFA" : "Ativar exigência de MFA"} className="switch" disabled={activeAction !== ""} onClick={() => void updateMfa()} ref={mfaRef} role="switch" title={detail.enforce_mfa ? "Desativar exigência de MFA" : "Ativar exigência de MFA"} type="button" /> : <span className={`tag ${detail.enforce_mfa ? "tag--paid" : "tag--draft"}`}>{detail.enforce_mfa ? "Obrigatória" : "Opcional"}</span>}</div>
            <div className="organization-access__role"><LockKeyhole aria-hidden="true" size={19} /><div><h3>Seu acesso</h3><p>{roleGuidance}</p></div><span className={`tag ${ROLE_TAGS[detail.current_role]}`}>{ROLE_LABELS[detail.current_role]}</span></div>
          </div>
          {detail.capabilities.can_manage ? <div className="organization-danger-row"><div><h3>Excluir organização</h3><p>As cobranças serão desvinculadas. Esta ação não pode ser desfeita.</p></div><button className="btn btn--danger btn--sm" disabled={activeAction !== ""} onClick={() => setConfirmation({ body: "A organização será excluída e suas cobranças serão desvinculadas. Esta ação não pode ser desfeita.", confirm: () => void deleteOrganization(), label: "Excluir organização", title: "Excluir organização?" })} ref={deleteRef} type="button">Excluir organização</button></div> : null}
        </section> : null}
      </article>
      <ConfirmDialog acceptLabel={confirmation?.label} body={confirmation?.body} onClose={() => setConfirmation(null)} onConfirm={() => confirmation?.confirm()} open={confirmation !== null} title={confirmation?.title ?? "Confirmar"} variant={confirmation?.variant} />
    </>
  );
}
