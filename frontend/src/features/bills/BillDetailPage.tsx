import { ArrowLeft, CalendarDays, ChevronDown, Download, Edit3, FileCheck2, FileClock, FileText, FileWarning, RefreshCw, Send, Trash2 } from "lucide-react";
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type MouseEvent } from "react";
import { Link, useNavigate, useParams } from "react-router";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import { LoadingState } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage } from "../../lib/api/errors";
import { formatBrl, formatDateTime, formatIsoDate, formatMonth } from "../../lib/format";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import { BillStatusActions } from "./BillStatusActions";
import { BillLifecycle } from "./InvoiceLifecycle";
import { ReceiptManager } from "./ReceiptManager";
import type { Bill, Billing } from "./billSupport";

const STATUS_META: Record<string, { className: string; label: string }> = {
  cancelled: { className: "tag--cancelled", label: "Cancelado" },
  delayed_payment: { className: "tag--delayed", label: "Pag. Atrasado" },
  draft: { className: "tag--draft", label: "Rascunho" },
  paid: { className: "tag--paid", label: "Pago" },
  published: { className: "tag--published", label: "Publicado" },
  sent: { className: "tag--sent", label: "Enviado" }
};

function DocumentFeedback({ ready, status }: { ready: boolean; status: string | null }) {
  if (status === "pending") {
    return <div aria-live="polite" className="document-feedback document-feedback--pending"><FileClock aria-hidden="true" /><div><h3>Gerando documento</h3><p>Estamos montando o PDF e o QR Code. Esta página atualiza automaticamente.</p></div></div>;
  }
  if (status === "failed") {
    return <div aria-live="polite" className="document-feedback document-feedback--failed"><FileWarning aria-hidden="true" /><div><h3>Falha ao gerar o documento</h3><p>Os dados estão salvos. Tente regenerar o PDF no menu de ações.</p></div></div>;
  }
  if (ready) {
    return <div className="document-feedback document-feedback--ready"><FileCheck2 aria-hidden="true" /><div><h3>Documento pronto</h3><p>O PDF com QR Code está disponível para abrir, baixar ou enviar.</p></div></div>;
  }
  return <div className="document-feedback"><FileClock aria-hidden="true" /><div><h3>Documento indisponível</h3><p>O PDF será liberado quando a geração for concluída.</p></div></div>;
}

export function BillDetailPage() {
  const { billingUuid = "", billUuid = "" } = useParams<{ billingUuid: string; billUuid: string }>();
  const navigate = useNavigate();
  const [billing, setBilling] = useState<Billing | null>(null);
  const [bill, setBill] = useState<Bill | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [success, setSuccess] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [regenerating, setRegenerating] = useState(false);
  const [downloadingRecibo, setDownloadingRecibo] = useState(false);
  const [openDropdown, setOpenDropdown] = useState<"actions" | null>(null);
  const [activeRecords, setActiveRecords] = useState<"communications" | "receipts">("communications");
  const controllerRef = useRef<AbortController | null>(null);
  const actionsButtonRef = useRef<HTMLButtonElement>(null);
  const actionsMenuRef = useRef<HTMLDivElement>(null);
  const recordTabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const mutationControllers = useRef(new Set<AbortController>());
  const routeGeneration = useRef(0);

  useDocumentTitle(bill ? `Fatura ${formatMonth(bill.reference_month)} - Rentivo` : "Fatura - Rentivo");

  useEffect(() => {
    const controllers = mutationControllers.current;
    const generation = ++routeGeneration.current;
    setActionError("");
    setSuccess("");
    setDeleting(false);
    setDeleteOpen(false);
    setRegenerating(false);
    setDownloadingRecibo(false);
    setOpenDropdown(null);
    setActiveRecords("communications");
    return () => {
      /* v8 ignore next -- cleanup always runs before the next effect setup */
      if (routeGeneration.current === generation) routeGeneration.current += 1;
      controllers.forEach((controller) => controller.abort());
      controllers.clear();
    };
  }, [billingUuid, billUuid]);

  useEffect(() => {
    if (!openDropdown) return;
    const close = () => setOpenDropdown(null);
    const closeWithKeyboard = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpenDropdown(null);
      actionsButtonRef.current?.focus();
    };
    document.addEventListener("click", close);
    document.addEventListener("keydown", closeWithKeyboard);
    return () => {
      document.removeEventListener("click", close);
      document.removeEventListener("keydown", closeWithKeyboard);
    };
  }, [openDropdown]);

  useLayoutEffect(() => {
    if (openDropdown !== "actions") return;
    const placeMenu = () => {
      const trigger = actionsButtonRef.current;
      const menu = actionsMenuRef.current;
      /* v8 ignore next -- both refs are mounted whenever the actions menu is open */
      if (!trigger || !menu) return;
      const triggerBox = trigger.getBoundingClientRect();
      const edge = 12;
      const gap = 8;
      const availableBelow = window.innerHeight - triggerBox.bottom - gap - edge;
      const availableAbove = triggerBox.top - gap - edge;
      const placement = availableBelow < Math.min(menu.scrollHeight, 320) && availableAbove > availableBelow ? "top" : "bottom";
      const available = placement === "top" ? availableAbove : availableBelow;
      menu.dataset.placement = placement;
      menu.style.setProperty("--bill-action-menu-space", `${Math.max(48, Math.floor(available))}px`);
    };
    placeMenu();
    window.addEventListener("resize", placeMenu);
    window.addEventListener("scroll", placeMenu, true);
    return () => {
      window.removeEventListener("resize", placeMenu);
      window.removeEventListener("scroll", placeMenu, true);
    };
  }, [openDropdown]);

  const beginMutation = () => {
    const controller = new AbortController();
    mutationControllers.current.add(controller);
    return { controller, generation: routeGeneration.current };
  };

  const mutationIsCurrent = (controller: AbortController, generation: number) => (
    !controller.signal.aborted && generation === routeGeneration.current
  );

  const load = useCallback(async ({ silent = false } = {}) => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    if (!silent) setLoading(true);
    try {
      const [billingResult, billResult] = await Promise.all([
        apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}", {
          params: { path: { billing_uuid: billingUuid } }, signal: controller.signal
        })),
        apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}/bills/{bill_uuid}", {
          params: { path: { billing_uuid: billingUuid, bill_uuid: billUuid } }, signal: controller.signal
        }))
      ]);
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      setBilling(billingResult.data);
      setBill(billResult.data);
      setLoadError("");
      setLoading(false);
    } catch (caught) {
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      // A silent poll keeps the loaded page instead of replacing it with the load-error state.
      if (!silent) setLoadError(errorMessage(caught, "Não foi possível carregar a fatura."));
      setLoading(false);
    }
  }, [billUuid, billingUuid]);

  useEffect(() => {
    void load();
    return () => controllerRef.current?.abort();
  }, [load]);

  const pdfRendering = bill?.pdf_render_status === "pending";
  useEffect(() => {
    if (!pdfRendering) return;
    const timer = window.setInterval(() => { void load({ silent: true }); }, 3000);
    return () => window.clearInterval(timer);
  }, [pdfRendering, load]);

  const regenerate = async () => {
    /* v8 ignore next -- the action is only rendered after bill loading */
    if (!bill) return;
    const { controller, generation } = beginMutation();
    setRegenerating(true);
    setActionError("");
    try {
      const { data, response } = await apiRequest(apiClient.POST(
        "/api/v1/billings/{billing_uuid}/bills/{bill_uuid}/regenerate",
        { params: { path: { billing_uuid: billingUuid, bill_uuid: bill.uuid } }, signal: controller.signal }
      ));
      if (!mutationIsCurrent(controller, generation)) return;
      pushAnalyticsFromResponse(response);
      setBill((current) => ({ ...current!, ...data }));
      setSuccess("O PDF será regenerado em segundo plano.");
    } catch (caught) {
      if (!mutationIsCurrent(controller, generation)) return;
      setActionError(errorMessage(caught, "Não foi possível regenerar o PDF."));
    } finally {
      mutationControllers.current.delete(controller);
      if (mutationIsCurrent(controller, generation)) setRegenerating(false);
    }
  };

  const removeBill = async () => {
    /* v8 ignore next -- the action is only rendered after bill loading */
    if (!bill) return;
    const { controller, generation } = beginMutation();
    setDeleting(true);
    setActionError("");
    try {
      const { response } = await apiRequest(apiClient.DELETE(
        "/api/v1/billings/{billing_uuid}/bills/{bill_uuid}",
        { params: { path: { billing_uuid: billingUuid, bill_uuid: bill.uuid } }, signal: controller.signal }
      ));
      if (!mutationIsCurrent(controller, generation)) return;
      pushAnalyticsFromResponse(response);
      navigate(`/billings/${billingUuid}`);
    } catch (caught) {
      if (!mutationIsCurrent(controller, generation)) return;
      setActionError(errorMessage(caught, "Não foi possível excluir a fatura."));
    } finally {
      mutationControllers.current.delete(controller);
      if (mutationIsCurrent(controller, generation)) setDeleting(false);
    }
  };

  const downloadRecibo = async (event: MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    const { controller, generation } = beginMutation();
    setDownloadingRecibo(true);
    setActionError("");
    try {
      const { data, response } = await apiRequest(apiClient.GET(
        "/api/v1/billings/{billing_uuid}/bills/{bill_uuid}/recibo/download",
        {
          params: { path: { billing_uuid: billingUuid, bill_uuid: billUuid } },
          signal: controller.signal
        }
      ));
      if (!mutationIsCurrent(controller, generation)) return;
      pushAnalyticsFromResponse(response);
      const anchor = document.createElement("a");
      anchor.href = data.download_url;
      anchor.download = data.filename;
      document.body.append(anchor);
      anchor.click();
      anchor.remove();
    } catch {
      if (!mutationIsCurrent(controller, generation)) return;
      setActionError("Não foi possível baixar o recibo.");
    } finally {
      mutationControllers.current.delete(controller);
      if (mutationIsCurrent(controller, generation)) setDownloadingRecibo(false);
    }
  };

  const changeRecordsTab = (tab: "communications" | "receipts", focus = false) => {
    setActiveRecords(tab);
    if (focus) recordTabRefs.current[tab === "communications" ? 0 : 1]?.focus();
  };

  const handleRecordsKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, current: "communications" | "receipts") => {
    if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    if (event.key === "Home") return changeRecordsTab("communications", true);
    if (event.key === "End") return changeRecordsTab("receipts", true);
    changeRecordsTab(current === "communications" ? "receipts" : "communications", true);
  };

  if (loading) return <LoadingState label="Carregando fatura..." />;
  if (loadError) return (
    <section aria-labelledby="bill-load-error-title" className="bill-route-error">
      <FileWarning aria-hidden="true" size={24} />
      <div>
        <h1 id="bill-load-error-title">Não foi possível abrir esta fatura</h1>
        <p role="alert">{loadError}</p>
      </div>
      <div className="bill-route-error__actions">
        <button className="btn btn--primary" onClick={() => void load()} type="button">Tentar novamente</button>
        <Link className="btn" to={`/billings/${billingUuid}`}><ArrowLeft aria-hidden="true" size={15} />Voltar para a cobrança</Link>
      </div>
    </section>
  );
  /* v8 ignore next -- successful paired loading always sets both resources */
  if (!bill || !billing) return null;
  const status = STATUS_META[bill.status] ?? { className: "tag--draft", label: bill.status };
  const hasFullCommunication = (communication: Bill["communications"][number]): communication is Extract<Bill["communications"][number], { recipient_email: string }> => "recipient_email" in communication;
  const hasActions = bill.capabilities.can_download_invoice || bill.capabilities.can_edit || bill.capabilities.can_compose
    || bill.capabilities.can_regenerate || bill.capabilities.can_transition || bill.capabilities.can_delete;

  return (
    <>
      <Link className="crumb" to={`/billings/${billingUuid}`}><ArrowLeft aria-hidden="true" size={16} />{billing.name}</Link>
      <article aria-label={`Fatura de ${formatMonth(bill.reference_month)}`} className={`bill-workspace${openDropdown === "actions" ? " bill-workspace--menu-open" : ""}`}>
        <header className="bill-workspace__header">
          <div className="bill-workspace__identity">
            <div className="bill-workspace__title-row">
              <h1 className="pagehead__title">Fatura · {formatMonth(bill.reference_month)}</h1>
              <span className={`tag ${status.className}`}>{["sent", "paid", "delayed_payment"].includes(bill.status) && <span className="dot" />}{status.label}</span>
              {bill.pdf_render_status === "pending" ? <span className="tag tag--draft" title="O PDF está sendo regenerado em segundo plano.">Renderizando…</span> : null}
              {bill.pdf_render_status === "failed" ? <span className="tag tag--cancelled" title="Falha ao gerar o PDF. Tente regenerar pelo menu de ações.">Falha no PDF</span> : null}
            </div>
            <p>{billing.name}{bill.due_date ? ` · vencimento ${formatIsoDate(bill.due_date)}` : ""}</p>
          </div>
        </header>

        <section aria-label="Resumo da fatura" className="bill-workspace__control-strip">
          <div className="bill-workspace__amount">
            <span>Total a pagar</span>
            <strong>{formatBrl(bill.total_amount)}</strong>
          </div>
          <div className="bill-workspace__due">
            <CalendarDays aria-hidden="true" size={17} />
            <span>{bill.due_date ? <>Vencimento<strong>{formatIsoDate(bill.due_date)}</strong></> : <>Vencimento<strong>Sem data definida</strong></>}</span>
          </div>
          <div className="bill-workspace__toolbar">
            {bill.capabilities.can_download_invoice ? <a className="btn btn--sm btn--primary" href={`/api/v1/billings/${billingUuid}/bills/${bill.uuid}/invoice`} target="_blank"><FileText aria-hidden="true" size={15} />Abrir PDF</a> : null}
            {hasActions ? <BillStatusActions
              billingUuid={billingUuid}
              bill={bill}
              onChange={setBill}
              onStale={() => void load()}
              renderMenu={(transitionItems) => (
                <div className={`btn-dropdown bill-action-menu${openDropdown === "actions" ? " open" : ""}`}>
                  <button aria-controls="bill-actions-menu" aria-expanded={openDropdown === "actions"} aria-label="Ações da fatura" className="btn btn--sm btn-dropdown-toggle" onClick={(event) => { event.stopPropagation(); setOpenDropdown((current) => current === "actions" ? null : "actions"); }} ref={actionsButtonRef} type="button">Ações <ChevronDown aria-hidden="true" size={14} /></button>
                  <div className="btn-dropdown-menu" id="bill-actions-menu" ref={actionsMenuRef}>
                    {bill.capabilities.can_download_invoice ? <><span className="bill-action-menu__label">Documentos</span><a className="btn-dropdown-item" href={`/api/v1/billings/${billingUuid}/bills/${bill.uuid}/invoice`} target="_blank"><Download aria-hidden="true" size={15} />Baixar fatura</a>{bill.capabilities.can_download_recibo
                      ? <a aria-disabled={downloadingRecibo || undefined} className="btn-dropdown-item" href={`/api/v1/billings/${billingUuid}/bills/${bill.uuid}/recibo/download`} onClick={(event) => void downloadRecibo(event)} target="_blank"><Download aria-hidden="true" size={15} />Baixar recibo</a>
                      : <span aria-disabled="true" className="btn-dropdown-item btn-dropdown-item--disabled" title={bill.status === "paid" ? "O recibo ainda está sendo gerado." : "O recibo fica disponível quando a fatura está paga."}><Download aria-hidden="true" size={15} />Baixar recibo</span>}</> : null}
                    {bill.capabilities.can_edit ? <Link className="btn-dropdown-item" to={`/billings/${billingUuid}/bills/${bill.uuid}/edit`}><Edit3 aria-hidden="true" size={15} />Editar fatura</Link> : null}
                    {bill.capabilities.can_compose ? <><div className="status-menu__separator" role="separator" />{bill.capabilities.can_send_invoice
                      ? <Link className="btn-dropdown-item" to={`/billings/${billingUuid}/bills/${bill.uuid}/communications/compose?type=bill_ready`}><Send aria-hidden="true" size={15} />Enviar fatura</Link>
                      : <span aria-disabled="true" className="btn-dropdown-item btn-dropdown-item--disabled" title="A fatura ainda está sendo gerada."><Send aria-hidden="true" size={15} />Enviar fatura</span>}{bill.capabilities.can_send_recibo
                      ? <Link className="btn-dropdown-item" to={`/billings/${billingUuid}/bills/${bill.uuid}/communications/compose?type=payment_receipt`}><Send aria-hidden="true" size={15} />Enviar recibo</Link>
                      : <span aria-disabled="true" className="btn-dropdown-item btn-dropdown-item--disabled" title={bill.status === "paid" ? "O recibo ainda está sendo gerado." : "O recibo fica disponível quando a fatura está paga."}><Send aria-hidden="true" size={15} />Enviar recibo</span>}</> : null}
                    {bill.capabilities.can_regenerate ? <><div className="status-menu__separator" role="separator" /><button className="status-menu__item" disabled={regenerating} onClick={() => void regenerate()} type="button"><RefreshCw aria-hidden="true" size={15} />{regenerating ? "Regenerando…" : "Regenerar PDF"}</button></> : null}
                    {transitionItems ? <><span className="bill-action-menu__label">Alterar status</span>{transitionItems}</> : null}
                    {bill.capabilities.can_delete ? <><div className="status-menu__separator" role="separator" /><button className="status-menu__item status-menu__item--danger" disabled={deleting} onClick={() => setDeleteOpen(true)} type="button"><Trash2 aria-hidden="true" size={15} />Excluir fatura</button></> : null}
                  </div>
                </div>
              )}
            /> : null}
          </div>
        </section>

        <div className="bill-workspace__progress">
          <div><span>Andamento</span>{bill.status_updated_at ? <small>Atualizado em {formatDateTime(bill.status_updated_at)}</small> : null}</div>
          <BillLifecycle status={bill.status} />
        </div>

        <div className="bill-workspace__body">
          <section aria-labelledby="bill-composition-title" className="bill-ledger">
            <div className="bill-ledger__heading">
              <div><h2 id="bill-composition-title">Composição da fatura</h2><p>Valores cobrados neste período.</p></div>
              <span className="mono">{bill.line_items.length} {bill.line_items.length === 1 ? "item" : "itens"}</span>
            </div>
            <dl className="bill-ledger__parties">
              <div><dt>Recebedor</dt><dd>{billing.pix_merchant_name || billing.name}</dd>{billing.pix_key ? <small className="mono">{billing.pix_key}</small> : null}{billing.pix_merchant_city ? <small>{billing.pix_merchant_city}</small> : null}</div>
              <div><dt>Cobrança</dt><dd>{billing.name}</dd>{billing.description ? <small>{billing.description}</small> : null}</div>
            </dl>
            <div className="bill-ledger__table"><table className="table"><thead><tr><th>Descrição</th><th className="center">Tipo</th><th className="num">Valor</th></tr></thead><tbody>
              {bill.line_items.map((item, index) => <tr key={`${item.description}-${item.sort_order}-${index}`}><td className="table__primary">{item.description}</td><td className="center"><span className={`tag tag--${item.item_type}`}>{item.item_type === "fixed" ? "Fixo" : item.item_type === "variable" ? "Variável" : "Extra"}</span></td><td className="num">{formatBrl(item.amount)}</td></tr>)}
            </tbody></table></div>
            {bill.notes ? <div className="bill-ledger__notes"><strong>Observações</strong><p>{bill.notes}</p></div> : null}
          </section>

          <aside aria-label="Documento e registros" className="bill-operations">
            <div className="bill-operations__document">
              <DocumentFeedback ready={bill.capabilities.can_download_invoice} status={bill.pdf_render_status} />
              <p>O PDF reúne a cobrança e o QR Code PIX no padrão EMV.</p>
            </div>
            <section className="bill-records">
              <div aria-label="Registros da fatura" className="bill-records__tabs" role="tablist">
                <button aria-controls="bill-communications-panel" aria-selected={activeRecords === "communications"} id="bill-communications-tab" onClick={() => changeRecordsTab("communications")} onKeyDown={(event) => handleRecordsKeyDown(event, "communications")} ref={(element) => { recordTabRefs.current[0] = element; }} role="tab" tabIndex={activeRecords === "communications" ? 0 : -1} type="button">Comunicações <span>{bill.communications.length}</span></button>
                <button aria-controls="bill-receipts-panel" aria-selected={activeRecords === "receipts"} id="bill-receipts-tab" onClick={() => changeRecordsTab("receipts")} onKeyDown={(event) => handleRecordsKeyDown(event, "receipts")} ref={(element) => { recordTabRefs.current[1] = element; }} role="tab" tabIndex={activeRecords === "receipts" ? 0 : -1} type="button">Comprovantes <span>{bill.receipts.length}</span></button>
              </div>
              {activeRecords === "communications" ? <div aria-labelledby="bill-communications-tab" className="bill-records__panel" id="bill-communications-panel" role="tabpanel">{bill.communications.length === 0 ? <p className="text-muted">Nenhuma comunicação enviada.</p> : <ul className="bill-activity">{bill.communications.map((communication) => <li key={communication.uuid}><time className="mono">{formatDateTime(communication.created_at)}</time><div>{hasFullCommunication(communication) ? <><strong>{communication.recipient_name} &lt;{communication.recipient_email}&gt;</strong><span>{communication.subject}</span></> : <><strong>Dados do destinatário protegidos</strong><span>Assunto indisponível</span></>}</div><span className={`tag ${communication.status === "sent" ? "tag--paid" : communication.status === "failed" ? "tag--cancelled" : "tag--draft"}`}>{communication.status === "sent" ? "Enviado" : communication.status === "failed" ? "Falhou" : "Na fila"}</span></li>)}</ul>}</div> : null}
              {activeRecords === "receipts" ? <div aria-labelledby="bill-receipts-tab" className="bill-records__panel" id="bill-receipts-panel" role="tabpanel"><ReceiptManager billingUuid={billingUuid} billUuid={bill.uuid} capabilities={bill.capabilities} onChange={(receipts) => { setBill((current) => ({ ...current!, receipts })); void load({ silent: true }); }} receipts={bill.receipts} /></div> : null}
            </section>
          </aside>
        </div>
      </article>
      {actionError && <div className="toast toast--danger" role="alert">{actionError}</div>}{success && <div className="toast toast--success" role="status">{success}</div>}
      <ConfirmDialog acceptLabel="Excluir fatura" body="A fatura e seus arquivos serão removidos. Esta ação não pode ser desfeita." onClose={() => setDeleteOpen(false)} onConfirm={() => void removeBill()} open={deleteOpen} title="Tem certeza que deseja excluir esta fatura?" />
    </>
  );
}
