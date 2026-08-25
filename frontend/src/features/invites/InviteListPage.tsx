import { ArrowRight, Check, Inbox, LockKeyhole, MailCheck, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import { LoadError } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage } from "../../lib/api/errors";
import type { components } from "../../lib/api/schema";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { useAuth } from "../auth/AuthProvider";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import "./InviteListPage.css";

type Invite = components["schemas"]["PendingInviteLoginResponse"];
type Selection = { action: "accept" | "decline"; invite: Invite } | null;
type ActiveResponse = { controller: AbortController; generation: number };
type ResponseOutcome =
  | { action: "accept"; data: components["schemas"]["InviteAcceptResponse"]; response: Response }
  | { action: "decline"; data: components["schemas"]["InviteDeclineResponse"]; response: Response };

const ROLE_LABELS: Record<Invite["role"], string> = {
  admin: "Administrador",
  manager: "Gerente",
  viewer: "Visualizador"
};

const RECEIVED_DATE = new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" });

function inviteCount(count: number): string {
  return `${new Intl.NumberFormat("pt-BR").format(count)} ${count === 1 ? "convite aguarda" : "convites aguardam"} sua decisão`;
}

function receivedDate(value: string | null): string {
  if (!value) return "Data do convite não informada";
  const date = new Date(value);
  return Number.isNaN(date.getTime())
    ? "Data do convite não informada"
    : `Recebido em ${RECEIVED_DATE.format(date)}`;
}

export function InviteListPage() {
  const navigate = useNavigate();
  const { refreshSession } = useAuth();
  const [invites, setInvites] = useState<Invite[] | null>(null);
  const [selection, setSelection] = useState<Selection>(null);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [message, setMessage] = useState("");
  const [responding, setResponding] = useState(false);
  const actionRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const activeResponseRef = useRef<ActiveResponse | null>(null);
  const generationRef = useRef(0);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const pendingFocusRef = useRef<(() => HTMLElement | null) | null>(null);

  const load = useCallback(async (signal?: AbortSignal, generation = generationRef.current) => {
    setLoadError("");
    try {
      const { data } = await apiRequest(apiClient.GET("/api/v1/invites", { signal }));
      if (!signal?.aborted && generation === generationRef.current) {
        setInvites((data as components["schemas"]["PendingInviteLoginListResponse"]).items);
      }
    } catch (caught) {
      if (!signal?.aborted && generation === generationRef.current) {
        setLoadError(errorMessage(caught, "Não foi possível carregar os convites."));
      }
    }
  }, []);

  useDocumentTitle("Convites - Rentivo");
  useEffect(() => {
    const controller = new AbortController();
    const generation = ++generationRef.current;
    void load(controller.signal, generation);
    return () => {
      generationRef.current += 1;
      controller.abort();
      activeResponseRef.current?.controller.abort();
      activeResponseRef.current = null;
      pendingFocusRef.current = null;
    };
  }, [load]);

  const respond = async (action: "accept" | "decline", invite: Invite) => {
    if (activeResponseRef.current) return;
    const active = { controller: new AbortController(), generation: generationRef.current };
    activeResponseRef.current = active;
    setResponding(true);
    setActionError("");
    setMessage("");
    const isCurrent = () => (
      activeResponseRef.current === active
      && !active.controller.signal.aborted
      && active.generation === generationRef.current
    );
    try {
      let outcome: ResponseOutcome;
      if (action === "accept") {
        const result = await apiRequest(apiClient.POST("/api/v1/invites/{invite_uuid}/accept", {
          params: { path: { invite_uuid: invite.uuid } },
          signal: active.controller.signal
        }));
        outcome = { action, data: result.data, response: result.response };
      } else {
        const result = await apiRequest(apiClient.POST("/api/v1/invites/{invite_uuid}/decline", {
          params: { path: { invite_uuid: invite.uuid } },
          signal: active.controller.signal
        }));
        outcome = { action, data: result.data, response: result.response };
      }
      if (!isCurrent()) return;
      pushAnalyticsFromResponse(outcome.response);
      await refreshSession().catch(() => undefined);
      if (!isCurrent()) return;
      if (outcome.action === "accept") {
        navigate(outcome.data.mfa_setup_required ? "/security/totp/setup" : `/organizations/${outcome.data.organization_uuid}`);
        return;
      }
      const currentInvites = invites as Invite[];
      const removedIndex = currentInvites.findIndex((item) => item.uuid === invite.uuid);
      const remaining = currentInvites.filter((item) => item.uuid !== invite.uuid);
      const focusInvite = remaining[Math.min(removedIndex, remaining.length - 1)];
      setInvites(remaining);
      setMessage("Convite recusado.");
      pendingFocusRef.current = () => (
        focusInvite ? actionRefs.current[`decline:${focusInvite.uuid}`] : headingRef.current
      );
    } catch (caught) {
      if (!isCurrent()) return;
      setActionError(errorMessage(caught, action === "accept" ? "Não foi possível aceitar o convite." : "Não foi possível recusar o convite."));
      pendingFocusRef.current = () => actionRefs.current[`${action}:${invite.uuid}`];
    } finally {
      if (activeResponseRef.current === active) {
        activeResponseRef.current = null;
        setResponding(false);
        const resolveControl = pendingFocusRef.current;
        pendingFocusRef.current = null;
        if (resolveControl) setTimeout(() => resolveControl()?.focus(), 0);
      }
    }
  };

  return (
    <div className="invite-inbox">
      <header className="invite-inbox__pagehead">
        <div>
          <h1 className="invite-inbox__title" ref={headingRef} tabIndex={-1}>Convites</h1>
          <p>Revise o acesso, o papel e os requisitos de segurança antes de responder.</p>
        </div>
        {invites ? (
          <div aria-live="polite" className="invite-inbox__count">
            <strong>{new Intl.NumberFormat("pt-BR").format(invites.length)}</strong>
            <span>{invites.length === 1 ? "pendente" : "pendentes"}</span>
          </div>
        ) : null}
      </header>
      {message ? <div className="toast toast--success" role="status">{message}</div> : null}
      {actionError ? <div className="toast toast--danger" role="alert">{actionError}</div> : null}

      {loadError ? (
        <section aria-label="Falha ao carregar convites" className="invite-inbox__state">
          <LoadError message={loadError} onRetry={() => void load()} />
        </section>
      ) : !invites ? (
        <section aria-live="polite" className="invite-inbox__loading" role="status">
          <span aria-hidden="true" className="invite-inbox__loading-mark"><Inbox size={22} /></span>
          <div>
            <p>Carregando convites…</p>
            <span aria-hidden="true" className="invite-inbox__loading-line" />
          </div>
        </section>
      ) : invites.length ? (
        <section aria-label="Convites aguardando resposta" className="invite-ledger">
          <header className="invite-ledger__header">
            <div>
              <h2>Convites aguardando resposta</h2>
              <p>Ao aceitar, a organização passa a fazer parte do seu espaço de trabalho.</p>
            </div>
            <strong>{inviteCount(invites.length)}</strong>
          </header>
          <div className="invite-ledger__table-wrap">
            <table className="invite-ledger__table">
              <caption className="sr-only">Convites de organizações que aguardam sua resposta</caption>
              <thead><tr><th>Organização</th><th>Seu papel</th><th>Enviado por</th><th>Ações</th></tr></thead>
              <tbody>
                {invites.map((invite) => (
                  <tr key={invite.uuid}>
                    <td data-label="Organização">
                      <div className="invite-ledger__identity">
                        <span aria-hidden="true" className="invite-ledger__mark">
                          {invite.organization_name.slice(0, 1).toLocaleUpperCase("pt-BR")}
                        </span>
                        <span className="invite-ledger__organization">
                          <strong title={invite.organization_name}>{invite.organization_name}</strong>
                          <small>Aguardando resposta</small>
                        </span>
                      </div>
                    </td>
                    <td data-label="Seu papel">
                      <span className="invite-ledger__role">{ROLE_LABELS[invite.role]}</span>
                      {invite.enforce_mfa ? (
                        <small className="invite-ledger__security"><LockKeyhole aria-hidden="true" size={14} />MFA será exigido</small>
                      ) : (
                        <small className="invite-ledger__security invite-ledger__security--optional">MFA opcional</small>
                      )}
                    </td>
                    <td data-label="Enviado por">
                      <span className="invite-ledger__sender" title={invite.invited_by_email}>{invite.invited_by_email}</span>
                      <small className="invite-ledger__date">{receivedDate(invite.created_at)}</small>
                    </td>
                    <td className="invite-ledger__actions" data-label="Ações">
                      <button className="btn btn--sm btn--primary" disabled={responding} onClick={() => setSelection({ action: "accept", invite })} ref={(element) => { actionRefs.current[`accept:${invite.uuid}`] = element; }} type="button"><Check aria-hidden="true" size={15} />Aceitar</button>
                      <button className="btn btn--sm invite-ledger__decline" disabled={responding} onClick={() => setSelection({ action: "decline", invite })} ref={(element) => { actionRefs.current[`decline:${invite.uuid}`] = element; }} type="button"><X aria-hidden="true" size={15} />Recusar</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : (
        <section aria-labelledby="invite-empty-title" className="invite-inbox__empty">
          <span aria-hidden="true" className="invite-inbox__empty-mark"><MailCheck size={28} /></span>
          <div>
            <h2 id="invite-empty-title">Nenhum convite pendente.</h2>
            <p>Sua caixa de convites está em dia. Novos acessos a organizações aparecerão aqui.</p>
          </div>
          <Link className="btn invite-inbox__organizations" to="/organizations/">
            Ver organizações <ArrowRight aria-hidden="true" size={16} />
          </Link>
        </section>
      )}
      <ConfirmDialog
        acceptLabel={selection?.action === "accept" ? "Aceitar convite" : "Recusar convite"}
        body={selection?.action === "accept"
          ? `Você entrará em ${selection.invite.organization_name} como ${ROLE_LABELS[selection.invite.role]}.${selection.invite.enforce_mfa ? " A organização exige MFA." : ""}`
          : `O convite de ${selection?.invite.organization_name ?? "esta organização"} será recusado e removido da lista.`}
        onClose={() => setSelection(null)}
        onConfirm={() => { if (selection) void respond(selection.action, selection.invite); }}
        open={selection !== null}
        title={selection?.action === "accept" ? "Aceitar convite?" : "Recusar convite?"}
        variant={selection?.action === "accept" ? "primary" : "danger"}
      />
    </div>
  );
}
