import { ArrowLeft, CalendarDays, ChevronDown, FileText, Paperclip, Plus, RefreshCw, Trash2, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useNavigate, useParams } from "react-router";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import { FieldError } from "../../components/FieldError";
import { DirtyFormGuard } from "../../forms/useDirtyFormGuard";
import { LoadError, LoadingState } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage, firstFieldError, normalizedFieldErrors } from "../../lib/api/errors";
import {
  formatBrl, formatBrlInput, formatIsoDate, formatMonth, MAX_PERSISTED_CENTAVOS, parseBrl, parseDateInput
} from "../../lib/format";
import { limitApiCharacters } from "../../lib/textLimits";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import { ReceiptManager } from "./ReceiptManager";
import type { Bill, BillLineItemRequest, Billing } from "./billSupport";

import "./BillEditPage.css";

interface EditableLine {
  amount: string;
  description: string;
  itemType: BillLineItemRequest["item_type"];
  key: string;
}

const STATUS_LABELS: Record<string, string> = {
  cancelled: "Cancelada",
  delayed_payment: "Pagamento atrasado",
  draft: "Rascunho",
  paid: "Paga",
  published: "Publicada",
  sent: "Enviada"
};

const STATUS_CLASS_NAMES: Record<string, string> = {
  delayed_payment: "delayed"
};

const ITEM_TYPE_LABELS: Record<EditableLine["itemType"], string> = {
  extra: "Extra",
  fixed: "Fixo",
  variable: "Variável"
};

export function BillEditPage() {
  const { billingUuid = "", billUuid = "" } = useParams<{ billingUuid: string; billUuid: string }>();
  const navigate = useNavigate();
  const [billing, setBilling] = useState<Billing | null>(null);
  const [bill, setBill] = useState<Bill | null>(null);
  const [lines, setLines] = useState<EditableLine[]>([]);
  const [dueDate, setDueDate] = useState("");
  const [notes, setNotes] = useState("");
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [success, setSuccess] = useState("");
  const [saveComplete, setSaveComplete] = useState(false);
  const [saving, setSaving] = useState(false);
  const [regenerating, setRegenerating] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [actionsOpen, setActionsOpen] = useState(false);
  const [receiptsOpen, setReceiptsOpen] = useState(false);
  const nextKey = useRef(0);
  const fieldRefs = useRef<Record<string, HTMLInputElement | HTMLTextAreaElement | null>>({});
  const actionsButtonRef = useRef<HTMLButtonElement>(null);
  const controllerRef = useRef<AbortController | null>(null);
  const mutationControllers = useRef(new Set<AbortController>());
  const saveInFlight = useRef(false);
  const routeGeneration = useRef(0);

  useDocumentTitle("Editar Fatura - Rentivo");

  useEffect(() => {
    const controllers = mutationControllers.current;
    const generation = ++routeGeneration.current;
    setActionError("");
    setFieldErrors({});
    setSuccess("");
    setSaveComplete(false);
    setSaving(false);
    setRegenerating(false);
    setDeleting(false);
    setDeleteOpen(false);
    setActionsOpen(false);
    setReceiptsOpen(false);
    saveInFlight.current = false;
    return () => {
      /* v8 ignore next -- cleanup always runs before the next effect setup */
      if (routeGeneration.current === generation) routeGeneration.current += 1;
      controllers.forEach((controller) => controller.abort());
      controllers.clear();
    };
  }, [billingUuid, billUuid]);

  useEffect(() => {
    if (!saveComplete || !bill) return;
    navigate(`/billings/${billingUuid}/bills/${bill.uuid}`, {
      replace: true,
      state: { notice: "Fatura atualizada com sucesso." }
    });
  }, [bill, billingUuid, navigate, saveComplete]);

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

  const beginMutation = () => {
    const controller = new AbortController();
    mutationControllers.current.add(controller);
    return { controller, generation: routeGeneration.current };
  };

  const mutationIsCurrent = (controller: AbortController, generation: number) => (
    !controller.signal.aborted && generation === routeGeneration.current
  );

  const load = useCallback(async () => {
    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    setLoading(true);
    setLoadError("");
    try {
      const [billingResult, billResult] = await Promise.all([
        apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}", { params: { path: { billing_uuid: billingUuid } }, signal: controller.signal })),
        apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}/bills/{bill_uuid}", { params: { path: { billing_uuid: billingUuid, bill_uuid: billUuid } }, signal: controller.signal }))
      ]);
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      setBilling(billingResult.data);
      setBill(billResult.data);
      setLines(billResult.data.line_items.map((item, index) => ({ amount: formatBrlInput(item.amount), description: item.description, itemType: item.item_type, key: `saved-${item.sort_order}-${index}` })));
      setDueDate(billResult.data.due_date ?? "");
      setNotes(billResult.data.notes);
      setLoading(false);
    } catch (caught) {
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      setLoadError(errorMessage(caught, "Não foi possível carregar a fatura."));
      setLoading(false);
    }
  }, [billUuid, billingUuid]);

  useEffect(() => {
    void load();
    return () => controllerRef.current?.abort();
  }, [load]);

  const focusField = (key: string | undefined) => {
    if (!key) return;
    fieldRefs.current[key]?.focus();
  };

  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (saveInFlight.current) return;
    /* v8 ignore next -- the form is only rendered after bill loading */
    if (!bill) return;
    setActionError(""); setFieldErrors({}); setSuccess("");
    const parsedDate = parseDateInput(dueDate);
    const errors: Record<string, string> = {};
    /* v8 ignore next -- native date inputs sanitize malformed non-empty values */
    if (parsedDate === undefined) errors.due_date = "Informe uma data válida.";
    const lineItems = lines.map((line, index) => {
      const amount = parseBrl(line.amount);
      const description = line.description.trim();
      if (!description) errors[`line_items.${index}.description`] = "Informe a descrição.";
      /* v8 ignore start -- the controlled input truncates API characters before this defense */
      else if (Array.from(description).length > 255) errors[`line_items.${index}.description`] = "A descrição deve ter no máximo 255 caracteres.";
      /* v8 ignore stop */
      if (amount === null) errors[`line_items.${index}.amount`] = "Informe um valor válido.";
      return { amount: amount ?? 0, description, item_type: line.itemType };
    });
    if (lineItems.reduce((total, item) => total + item.amount, 0) > MAX_PERSISTED_CENTAVOS) {
      errors["line_items.0.amount"] = "O valor total deve ser de no máximo R$ 21.474.836,47.";
    }
    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors);
      focusField(Object.keys(errors)[0]);
      return;
    }
    saveInFlight.current = true;
    const { controller, generation } = beginMutation();
    setSaving(true);
    try {
      const { data, response } = await apiRequest(apiClient.PATCH(
        "/api/v1/billings/{billing_uuid}/bills/{bill_uuid}",
        { body: { due_date: parsedDate, line_items: lineItems, notes }, params: { path: { billing_uuid: billingUuid, bill_uuid: bill.uuid } }, signal: controller.signal }
      ));
      if (!mutationIsCurrent(controller, generation)) return;
      pushAnalyticsFromResponse(response);
      setBill(data);
      setSaveComplete(true);
    } catch (caught) {
      if (!mutationIsCurrent(controller, generation)) return;
      const apiErrors = normalizedFieldErrors(caught);
      setFieldErrors(apiErrors);
      setActionError(errorMessage(caught, "Não foi possível atualizar a fatura."));
      requestAnimationFrame(() => focusField(firstFieldError(apiErrors, ["line_items.0.description", "due_date", "notes"])));
    } finally {
      saveInFlight.current = false;
      mutationControllers.current.delete(controller);
      if (mutationIsCurrent(controller, generation)) setSaving(false);
    }
  };

  const regenerate = async () => {
    /* v8 ignore next -- the action is only rendered after bill loading */
    if (!bill) return;
    const { controller, generation } = beginMutation();
    setRegenerating(true); setActionError("");
    try {
      const { data, response } = await apiRequest(apiClient.POST("/api/v1/billings/{billing_uuid}/bills/{bill_uuid}/regenerate", { params: { path: { billing_uuid: billingUuid, bill_uuid: bill.uuid } }, signal: controller.signal }));
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
    setDeleting(true); setActionError("");
    try {
      const { response } = await apiRequest(apiClient.DELETE("/api/v1/billings/{billing_uuid}/bills/{bill_uuid}", { params: { path: { billing_uuid: billingUuid, bill_uuid: bill.uuid } }, signal: controller.signal }));
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

  if (loading) return <LoadingState label="Carregando fatura…" />;
  if (loadError) return <LoadError message={loadError} onRetry={() => void load()} />;
  /* v8 ignore next -- successful paired loading always sets both resources */
  if (!bill || !billing) return null;

  const editableTotal = lines.reduce((total, line) => total + (parseBrl(line.amount) ?? 0), 0);
  const isDirty = dueDate !== (bill.due_date ?? "") || notes !== bill.notes || lines.length !== bill.line_items.length || lines.some((line, index) => {
    const persisted = bill.line_items[index];
    return !persisted || line.description !== persisted.description || line.itemType !== persisted.item_type || parseBrl(line.amount) !== persisted.amount;
  });
  const itemCountLabel = `${lines.length} ${lines.length === 1 ? "item" : "itens"}`;
  const receiptCountLabel = `${bill.receipts.length} ${bill.receipts.length === 1 ? "arquivo" : "arquivos"}`;
  const hasMaintenanceActions = bill.capabilities.can_regenerate || bill.capabilities.can_delete;

  return (
    <>
      <DirtyFormGuard isDirty={isDirty && !deleting && !saveComplete} />
      <Link className="crumb invoice-edit-page__crumb" to={`/billings/${billingUuid}/bills/${bill.uuid}`}><ArrowLeft aria-hidden="true" size={16} />Voltar para a fatura</Link>
      <article aria-label={`Editor da fatura de ${formatMonth(bill.reference_month)}`} className="invoice-edit-page">
        <header className="invoice-edit-page__header">
          <div className="invoice-edit-page__identity">
            <span>Fatura de {formatMonth(bill.reference_month)}</span>
            <h1>Editar fatura</h1>
            <p>{billing.name}. Ajuste apenas o que muda neste período.</p>
          </div>
          <div className="invoice-edit-page__header-tools">
            <span className={`tag tag--${STATUS_CLASS_NAMES[bill.status] ?? bill.status}`}>{STATUS_LABELS[bill.status]}</span>
            {hasMaintenanceActions ? <div className={`btn-dropdown bill-action-menu invoice-edit-actions${actionsOpen ? " open" : ""}`}>
              <button aria-controls="invoice-edit-actions-menu" aria-expanded={actionsOpen} aria-label="Ações da fatura" className="btn btn--sm btn-dropdown-toggle" onClick={(event) => { event.stopPropagation(); setActionsOpen((current) => !current); }} ref={actionsButtonRef} type="button">Ações <ChevronDown aria-hidden="true" size={14} /></button>
              <div className="btn-dropdown-menu" id="invoice-edit-actions-menu">
                <span className="bill-action-menu__label">Documento</span>
                {bill.capabilities.can_regenerate ? <button className="status-menu__item" disabled={regenerating} onClick={() => { setActionsOpen(false); void regenerate(); }} type="button"><RefreshCw aria-hidden="true" size={15} />{regenerating ? "Regenerando…" : "Regenerar PDF"}</button> : null}
                {bill.capabilities.can_delete ? <><div className="status-menu__separator" role="separator" /><button className="status-menu__item status-menu__item--danger" disabled={deleting} onClick={() => { setActionsOpen(false); setDeleteOpen(true); }} type="button"><Trash2 aria-hidden="true" size={15} />Excluir fatura</button></> : null}
              </div>
            </div> : null}
          </div>
        </header>

        {actionError ? <div className="toast toast--danger invoice-edit-page__feedback" role="alert">{actionError}</div> : null}
        {success ? <div className="toast toast--success invoice-edit-page__feedback" role="status">{success}</div> : null}

        {bill.pdf_render_status === "pending" ? <div aria-live="polite" className="invoice-edit-page__notice"><FileText aria-hidden="true" size={17} /><span><strong>PDF em atualização.</strong> O novo arquivo será montado em segundo plano.</span></div> : null}
        {bill.pdf_render_status === "failed" ? <div className="invoice-edit-page__notice invoice-edit-page__notice--danger" role="alert"><FileText aria-hidden="true" size={17} /><span><strong>O PDF não foi gerado.</strong> Tente novamente pelo menu Ações.</span></div> : null}

        <div className="invoice-edit-page__workspace">
          {bill.capabilities.can_edit ? <form className="invoice-edit-form" id="invoice-edit-form" onSubmit={(event) => void save(event)}>
            <section aria-labelledby="invoice-edit-items-title" className="invoice-edit-section">
              <div className="invoice-edit-section__head">
                <div><h2 id="invoice-edit-items-title">Itens da fatura</h2><p>Edite os valores cobrados e inclua despesas pontuais no mesmo lugar.</p></div>
                <button aria-label="Adicionar despesa extra" className="btn btn--sm btn--primary" onClick={() => setLines((items) => [...items, { amount: "", description: "", itemType: "extra", key: `new-${nextKey.current++}` }])} type="button"><Plus aria-hidden="true" size={14} />Adicionar extra</button>
              </div>
              <div className="invoice-edit-lines" id="items-container">
                {lines.map((line, index) => <div className="invoice-edit-line" key={line.key}>
                  <div className="field mb-0"><label className="field-label" htmlFor={`line-description-${line.key}`}>Descrição</label><input aria-describedby={fieldErrors[`line_items.${index}.description`] ? `line_items.${index}.description-error` : undefined} aria-invalid={fieldErrors[`line_items.${index}.description`] ? true : undefined} autoComplete="off" className="field-input" id={`line-description-${line.key}`} name={`line_items.${index}.description`} onChange={(event) => setLines((items) => items.map((item) => item.key === line.key ? { ...item, description: limitApiCharacters(event.target.value, 255) } : item))} ref={(node) => { fieldRefs.current[`line_items.${index}.description`] = node; }} value={line.description} /><FieldError id={`line_items.${index}.description-error`} message={fieldErrors[`line_items.${index}.description`]} /></div>
                  <div className="invoice-edit-line__type"><span className="field-label">Tipo</span><span className={`tag tag--${line.itemType}`}>{ITEM_TYPE_LABELS[line.itemType]}</span></div>
                  <div className="field mb-0"><label className="field-label" htmlFor={`line-amount-${line.key}`}>Valor (R$)</label><input aria-describedby={fieldErrors[`line_items.${index}.amount`] ? `line_items.${index}.amount-error` : undefined} aria-invalid={fieldErrors[`line_items.${index}.amount`] ? true : undefined} autoComplete="off" className="field-input" id={`line-amount-${line.key}`} inputMode="decimal" name={`line_items.${index}.amount`} onChange={(event) => setLines((items) => items.map((item) => item.key === line.key ? { ...item, amount: event.target.value } : item))} ref={(node) => { fieldRefs.current[`line_items.${index}.amount`] = node; }} value={line.amount} /><FieldError id={`line_items.${index}.amount-error`} message={fieldErrors[`line_items.${index}.amount`]} /></div>
                  <div className="invoice-edit-line__remove">{line.itemType === "extra" ? <button aria-label={`Remover ${line.description.trim() || "item extra"}`} className="icon-btn" onClick={() => setLines((items) => items.filter((item) => item.key !== line.key))} type="button"><X aria-hidden="true" size={16} /></button> : null}</div>
                </div>)}
              </div>
              <div className="invoice-edit-lines__total"><span>Total desta versão</span><output aria-live="polite">{formatBrl(editableTotal)}</output></div>
            </section>

            <section aria-labelledby="invoice-edit-details-title" className="invoice-edit-section invoice-edit-section--details">
              <div className="invoice-edit-section__head"><div><h2 id="invoice-edit-details-title">Vencimento e observações</h2><p>Essas informações aparecem no PDF desta fatura.</p></div></div>
              <div className="invoice-edit-details">
                <div className="field mb-0"><label className="field-label" htmlFor="due_date">Vencimento</label><input aria-describedby={fieldErrors.due_date ? "due_date-error" : undefined} aria-invalid={fieldErrors.due_date ? true : undefined} autoComplete="off" className="field-input" id="due_date" name="due_date" onChange={(event) => setDueDate(event.target.value)} ref={(node) => { fieldRefs.current.due_date = node; }} type="date" value={dueDate} /><FieldError id="due_date-error" message={fieldErrors.due_date} /></div>
                <div className="field mb-0"><label className="field-label" htmlFor="notes">Observações</label><textarea aria-describedby={fieldErrors.notes ? "notes-error" : "notes-hint"} aria-invalid={fieldErrors.notes ? true : undefined} autoComplete="off" className="field-textarea" id="notes" name="notes" onChange={(event) => setNotes(event.target.value)} ref={(node) => { fieldRefs.current.notes = node; }} rows={4} value={notes} /><span className="field-hint" id="notes-hint">Use este campo para instruções úteis ao pagador.</span><FieldError id="notes-error" message={fieldErrors.notes} /></div>
              </div>
            </section>
          </form> : <section className="invoice-edit-page__denied"><h2>Edição indisponível</h2><p>Você não possui permissão para editar esta fatura.</p><Link className="btn btn--primary" to={`/billings/${billingUuid}/bills/${bill.uuid}`}>Voltar para a fatura</Link></section>}

          <aside aria-label="Resumo e comprovantes" className="invoice-edit-page__aside">
            <section aria-label="Resumo das alterações" className="invoice-edit-summary">
              <span>Resumo das alterações</span>
              <output>{formatBrl(editableTotal)}</output>
              <dl>
                <div><dt>Itens</dt><dd>{itemCountLabel}</dd></div>
                <div><dt>Vencimento</dt><dd>{dueDate ? formatIsoDate(dueDate) : "Sem data"}</dd></div>
                <div><dt>Estado</dt><dd>{isDirty ? "Não salvo" : "Atual"}</dd></div>
              </dl>
              {bill.capabilities.can_edit ? <div className="invoice-edit-summary__actions"><span aria-live="polite">{isDirty ? "Alterações ainda não salvas" : "Fatura sem alterações"}</span><button className="btn btn--primary btn--block" disabled={saving || !isDirty} form="invoice-edit-form" type="submit">{saving ? "Salvando…" : "Salvar alterações"}</button><Link className="btn btn--ghost btn--block" to={`/billings/${billingUuid}/bills/${bill.uuid}`}>Cancelar</Link></div> : null}
            </section>
            <section className="invoice-edit-receipts">
              <button aria-controls="invoice-edit-receipts-panel" aria-expanded={receiptsOpen} aria-label={`Comprovantes ${bill.receipts.length}`} onClick={() => setReceiptsOpen((current) => !current)} type="button"><Paperclip aria-hidden="true" size={17} /><span><strong>Comprovantes <b>{bill.receipts.length}</b></strong><small>{receiptCountLabel}</small></span><ChevronDown aria-hidden="true" className={receiptsOpen ? "is-open" : ""} size={16} /></button>
              {receiptsOpen ? <div className="invoice-edit-receipts__panel" id="invoice-edit-receipts-panel"><ReceiptManager billingUuid={billingUuid} billUuid={bill.uuid} capabilities={bill.capabilities} onChange={(receipts) => setBill((current) => ({ ...current!, receipts }))} receipts={bill.receipts} /></div> : null}
            </section>
            <div className="invoice-edit-page__aside-note"><CalendarDays aria-hidden="true" size={17} /><p><strong>Altera só esta fatura.</strong> O modelo recorrente da cobrança permanece igual.</p></div>
          </aside>
        </div>
      </article>
      <ConfirmDialog acceptLabel="Excluir fatura" body="A fatura e seus arquivos serão removidos. Esta ação não pode ser desfeita." onClose={() => setDeleteOpen(false)} onConfirm={() => void removeBill()} open={deleteOpen} title="Tem certeza que deseja excluir esta fatura?" />
    </>
  );
}
