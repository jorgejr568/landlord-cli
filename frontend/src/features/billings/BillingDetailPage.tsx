import { ChevronDown, ChevronLeft, QrCode } from "lucide-react";
import { type FormEvent, type KeyboardEvent as ReactKeyboardEvent, useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import { FieldError } from "../../components/FieldError";
import { LoadError, LoadingState } from "../../components/PageState";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import { normalizedFieldErrors } from "../../lib/api/errors";
import type { components } from "../../lib/api/schema";
import { formatBrl, formatMonth, parseBrl } from "../../lib/format";
import { limitApiCharacters } from "../../lib/textLimits";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";

type Attachment = components["schemas"]["AttachmentResponse"];
type Bill = components["schemas"]["BillResponse"];
type Billing = components["schemas"]["BillingResponse"];
type Expense = components["schemas"]["ExpenseResponse"];
type ExpenseCategory = components["schemas"]["ExpenseCreateRequest"]["category"];
type Organization = components["schemas"]["OrganizationResponse"];
type BillingTab = "bills" | "documents" | "expenses";

interface DetailData {
  attachments: Attachment[];
  billing: Billing;
  bills: Bill[];
  expenses: Expense[];
  organizations: Organization[];
}

interface LoadedDetail {
  data: DetailData;
  billingUuid: string;
}

type DetailAction = "delete" | "expense-create" | "expense-delete" | "export-csv" | "export-xlsx" | "transfer";

interface ActionToken {
  action: DetailAction;
  billingUuid: string;
  controller: AbortController;
}

const CATEGORY_LABELS: Record<ExpenseCategory, string> = {
  condominio: "Condomínio",
  iptu: "IPTU",
  manutencao: "Manutenção",
  outros: "Outros",
  seguro: "Seguro"
};
const STATUS_LABELS: Record<string, string> = {
  cancelled: "Cancelado",
  delayed_payment: "Pag. Atrasado",
  draft: "Rascunho",
  paid: "Pago",
  published: "Publicado",
  sent: "Enviado"
};

function StatusTag({ status }: { status: string }) {
  const dotted = status === "sent" || status === "paid" || status === "delayed_payment";
  const style = status === "delayed_payment" ? "delayed" : status;
  return <span className={`tag tag--${style}`}>{dotted ? <span className="dot" /> : null}{STATUS_LABELS[status]}</span>;
}

export function BillingDetailPage() {
  const billingUuid = useParams<{ billingUuid: string }>().billingUuid!;
  const navigate = useNavigate();
  const routeUuidRef = useRef(billingUuid);
  const mutationControllersRef = useRef(new Set<AbortController>());
  const activeActionRef = useRef<ActionToken | null>(null);
  const expenseHeadingRef = useRef<HTMLHeadingElement>(null);
  const actionsButtonRef = useRef<HTMLButtonElement>(null);
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);
  routeUuidRef.current = billingUuid;
  const [loaded, setLoaded] = useState<LoadedDetail | null>(null);
  const [loadError, setLoadError] = useState("");
  const [mutationError, setMutationError] = useState("");
  const [notice, setNotice] = useState("");
  const [expenseDescription, setExpenseDescription] = useState("");
  const [expenseCategory, setExpenseCategory] = useState<ExpenseCategory>("iptu");
  const [expenseDate, setExpenseDate] = useState("");
  const [expenseAmount, setExpenseAmount] = useState("");
  const [expenseErrors, setExpenseErrors] = useState<Record<string, string>>({});
  const [pendingExpense, setPendingExpense] = useState<Expense | null>(null);
  const [pendingTransfer, setPendingTransfer] = useState(false);
  const [pendingDelete, setPendingDelete] = useState(false);
  const [organizationUuid, setOrganizationUuid] = useState("");
  const [activeAction, setActiveAction] = useState<DetailAction | null>(null);
  const [activeTab, setActiveTab] = useState<BillingTab>("bills");
  const [actionsOpen, setActionsOpen] = useState(false);

  const beginAction = (action: DetailAction): ActionToken | null => {
    if (activeActionRef.current) return null;
    const token = { action, billingUuid, controller: new AbortController() };
    activeActionRef.current = token;
    mutationControllersRef.current.add(token.controller);
    setActiveAction(action);
    return token;
  };
  const actionIsCurrent = (token: ActionToken) => activeActionRef.current === token
    && !token.controller.signal.aborted && routeUuidRef.current === token.billingUuid;
  const finishAction = (token: ActionToken) => {
    mutationControllersRef.current.delete(token.controller);
    if (activeActionRef.current === token) {
      activeActionRef.current = null;
      setActiveAction(null);
    }
  };

  const load = useCallback(async (requestUuid: string, signal?: AbortSignal) => {
    const isCurrent = () => !signal?.aborted && routeUuidRef.current === requestUuid;
    /* v8 ignore else -- every public load caller supplies the active route UUID */
    if (isCurrent()) {
      setLoadError("");
      setMutationError("");
    }
    try {
      const billingResult = await apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}", {
        params: { path: { billing_uuid: requestUuid } }, signal
      }));
      const billing = billingResult.data;
      if (!isCurrent()) return;
      const [billResult, expenseResult, attachmentResult, organizationResult] = await Promise.all([
        billing.capabilities.can_read_bills
          ? apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}/bills", { params: { path: { billing_uuid: requestUuid } }, signal }))
          : null,
        billing.capabilities.can_read_expenses
          ? apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}/expenses", { params: { path: { billing_uuid: requestUuid } }, signal }))
          : null,
        billing.capabilities.can_read_attachments
          ? apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}/attachments", { params: { path: { billing_uuid: requestUuid } }, signal }))
          : null,
        billing.capabilities.can_transfer
          ? apiRequest(apiClient.GET("/api/v1/organizations", { signal }))
          : null
      ]);
      if (isCurrent()) setLoaded({
        billingUuid: requestUuid,
        data: {
          attachments: attachmentResult?.data.items ?? [],
          billing,
          bills: billResult?.data.items ?? [],
          expenses: expenseResult?.data.items ?? [],
          organizations: organizationResult?.data.items ?? []
        }
      });
    } catch {
      if (isCurrent()) setLoadError("Não foi possível carregar a cobrança.");
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    const mutationControllers = mutationControllersRef.current;
    activeActionRef.current = null;
    setActiveAction(null);
    setPendingExpense(null);
    setPendingTransfer(false);
    setPendingDelete(false);
    setOrganizationUuid("");
    setNotice("");
    setActiveTab("bills");
    setActionsOpen(false);
    void load(billingUuid, controller.signal);
    return () => {
      controller.abort();
      mutationControllers.forEach((mutationController) => mutationController.abort());
      mutationControllers.clear();
      activeActionRef.current = null;
    };
  }, [billingUuid, load]);
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
  const data = loaded?.billingUuid === billingUuid ? loaded.data : null;
  useDocumentTitle(data ? `${data.billing.name} - Rentivo` : "Cobrança - Rentivo");
  useEffect(() => {
    const first = Object.keys(expenseErrors)[0];
    if (first) document.querySelector<HTMLElement>(`[name="expense-${first}"]`)?.focus();
  }, [expenseErrors]);

  const exportBills = async (format: "csv" | "xlsx") => {
    const token = beginAction(`export-${format}`);
    if (!token) return;
    setMutationError(""); setNotice("");
    try {
      const { response } = await apiRequest(apiClient.POST("/api/v1/billings/{billing_uuid}/exports", { body: { format }, params: { path: { billing_uuid: token.billingUuid } }, signal: token.controller.signal }));
      if (!actionIsCurrent(token)) return;
      pushAnalyticsFromResponse(response);
      setNotice(`Exportação ${format.toUpperCase()} solicitada. O arquivo será enviado para o seu e-mail.`);
    } catch {
      if (actionIsCurrent(token)) setMutationError("Não foi possível solicitar a exportação.");
    } finally {
      finishAction(token);
    }
  };

  const addExpense = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const normalizedDescription = expenseDescription.trim();
    const amount = parseBrl(expenseAmount) ?? 0;
    const localErrors: Record<string, string> = {};
    if (!normalizedDescription) localErrors.description = "Informe a descrição da despesa.";
    /* v8 ignore start -- the controlled input truncates API characters before this defense */
    else if (Array.from(normalizedDescription).length > 2_000) localErrors.description = "A descrição deve ter no máximo 2000 caracteres.";
    /* v8 ignore stop */
    if (amount <= 0) localErrors.amount = "Informe um valor válido.";
    if (!expenseDate) localErrors.incurred_on = "Informe a data da despesa.";
    if (Object.keys(localErrors).length) {
      setExpenseErrors(localErrors);
      return;
    }
    const token = beginAction("expense-create");
    if (!token) return;
    setExpenseErrors({}); setMutationError("");
    try {
      const { response } = await apiRequest(apiClient.POST("/api/v1/billings/{billing_uuid}/expenses", {
        body: { amount, category: expenseCategory, description: normalizedDescription, incurred_on: expenseDate },
        params: { path: { billing_uuid: token.billingUuid } }, signal: token.controller.signal
      }));
      /* v8 ignore next -- an aborted request rejects before yielding a stale response */
      if (!actionIsCurrent(token)) return;
      pushAnalyticsFromResponse(response);
      setExpenseDescription(""); setExpenseCategory("iptu"); setExpenseDate(""); setExpenseAmount("");
      await load(token.billingUuid, token.controller.signal);
    } catch (caught) {
      if (actionIsCurrent(token)) {
        if (caught instanceof ApiError && Object.keys(caught.fields).length) setExpenseErrors(normalizedFieldErrors(caught));
        else setMutationError("Não foi possível adicionar a despesa.");
      }
    } finally {
      finishAction(token);
    }
  };

  const removeExpense = async (expense: Expense) => {
    const token = beginAction("expense-delete");
    if (!token) return;
    setMutationError("");
    try {
      const { response } = await apiRequest(apiClient.DELETE("/api/v1/billings/{billing_uuid}/expenses/{expense_uuid}", { params: { path: { billing_uuid: token.billingUuid, expense_uuid: expense.uuid } }, signal: token.controller.signal }));
      if (!actionIsCurrent(token)) return;
      pushAnalyticsFromResponse(response);
      await load(token.billingUuid, token.controller.signal);
      if (!actionIsCurrent(token)) return;
      setNotice("Despesa removida.");
      expenseHeadingRef.current?.focus();
    } catch {
      if (actionIsCurrent(token)) setMutationError("Não foi possível remover a despesa.");
    } finally {
      finishAction(token);
    }
  };

  const transfer = async () => {
    const token = beginAction("transfer");
    if (!token) return;
    setMutationError("");
    try {
      const { response } = await apiRequest(apiClient.POST("/api/v1/billings/{billing_uuid}/transfer", { body: { organization_uuid: organizationUuid }, params: { path: { billing_uuid: token.billingUuid } }, signal: token.controller.signal }));
      if (!actionIsCurrent(token)) return;
      pushAnalyticsFromResponse(response);
      navigate("/billings/");
    } catch {
      if (actionIsCurrent(token)) setMutationError("Não foi possível transferir a cobrança.");
    } finally {
      finishAction(token);
    }
  };

  const deleteBilling = async () => {
    const token = beginAction("delete");
    if (!token) return;
    setMutationError("");
    try {
      const { response } = await apiRequest(apiClient.DELETE("/api/v1/billings/{billing_uuid}", { params: { path: { billing_uuid: token.billingUuid } }, signal: token.controller.signal }));
      if (!actionIsCurrent(token)) return;
      pushAnalyticsFromResponse(response);
      navigate("/billings/");
    } catch {
      if (actionIsCurrent(token)) setMutationError("Não foi possível excluir a cobrança.");
    } finally {
      finishAction(token);
    }
  };

  const changeTab = (tab: BillingTab) => setActiveTab(tab);
  const handleTabKeyDown = (event: ReactKeyboardEvent<HTMLButtonElement>, tab: BillingTab, tabs: BillingTab[]) => {
    const currentIndex = tabs.indexOf(tab);
    let nextIndex: number;
    if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % tabs.length;
    else if (event.key === "ArrowLeft") nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
    else if (event.key === "Home") nextIndex = 0;
    else if (event.key === "End") nextIndex = tabs.length - 1;
    else return;
    event.preventDefault();
    setActiveTab(tabs[nextIndex]);
    tabRefs.current[nextIndex]?.focus();
  };

  if (loadError) return <LoadError message={loadError} onRetry={() => void load(billingUuid)} />;
  if (!data) return <LoadingState label="Carregando cobrança..." />;
  const { attachments, billing, bills, expenses, organizations } = data;
  const fixedSubtotal = billing.items.reduce((sum, item) => sum + (item.item_type === "fixed" ? item.amount : 0), 0);
  const ownerIsOrganization = billing.owner.type === "organization";
  const hasPixOverride = Boolean(billing.pix_key || billing.pix_merchant_name || billing.pix_merchant_city);
  const availableTabs = [
    billing.capabilities.can_read_bills || billing.capabilities.can_create_exports ? "bills" : null,
    billing.capabilities.can_read_expenses || billing.capabilities.can_write_expenses ? "expenses" : null,
    billing.capabilities.can_read_attachments ? "documents" : null
  ].filter((tab): tab is BillingTab => tab !== null);
  const selectedTab = availableTabs.includes(activeTab) ? activeTab : availableTabs[0];
  const hasActions = billing.capabilities.can_read_theme || billing.capabilities.can_edit
    || (billing.capabilities.can_transfer && organizations.length > 0) || billing.capabilities.can_delete;

  return (
    <>
      <Link className="crumb" to="/billings/"><ChevronLeft aria-hidden="true" size={16} strokeWidth={2.5} />Minhas Cobranças</Link>
      {mutationError ? <div className="toast toast--error" role="alert">{mutationError} <button className="btn btn--sm" onClick={() => void load(billingUuid)} type="button">Tentar novamente</button></div> : null}
      {notice ? <div className="toast toast--success" role="status">{notice}</div> : null}
      <article aria-label={`Cobrança ${billing.name}`} className="bill-workspace billing-workspace">
        <header className="bill-workspace__header">
          <div className="bill-workspace__identity">
            <div className="bill-workspace__title-row"><h1 className="pagehead__title">{billing.name}</h1>{ownerIsOrganization ? <span className="tag tag--fixed">Organização</span> : null}</div>
            <p>{billing.description || "Modelo de cobrança recorrente"}</p>
          </div>
          <div className="bill-workspace__toolbar">
            {billing.capabilities.can_create_bills ? billing.pix_needs_setup
              ? <button className="btn btn--primary btn--sm" disabled title="Configure os dados do PIX primeiro" type="button">Gerar fatura</button>
              : <Link className="btn btn--primary btn--sm" to={`/billings/${billingUuid}/bills/generate`}>Gerar fatura</Link> : null}
            {hasActions ? <div className={`btn-dropdown bill-action-menu billing-action-menu${actionsOpen ? " open" : ""}`}>
              <button aria-controls="billing-actions-menu" aria-expanded={actionsOpen} aria-label="Ações da cobrança" className="btn btn--sm btn-dropdown-toggle" onClick={(event) => { event.stopPropagation(); setActionsOpen((open) => !open); }} ref={actionsButtonRef} type="button">Ações <ChevronDown aria-hidden="true" size={14} /></button>
              <div className="btn-dropdown-menu" id="billing-actions-menu" onClick={(event) => event.stopPropagation()}>
                {(billing.capabilities.can_read_theme || billing.capabilities.can_edit) ? <span className="bill-action-menu__label">Configuração</span> : null}
                {billing.capabilities.can_read_theme ? <Link className="btn-dropdown-item" onClick={() => setActionsOpen(false)} to={`/themes/billing/${billingUuid}`}>Tema da cobrança</Link> : null}
                {billing.capabilities.can_edit ? <Link className="btn-dropdown-item" onClick={() => setActionsOpen(false)} to={`/billings/${billingUuid}/edit`}>Editar cobrança</Link> : null}
                {billing.capabilities.can_transfer && organizations.length ? <div className="billing-action-menu__transfer">
                  <label className="bill-action-menu__label" htmlFor="billing-transfer-owner">Transferir propriedade</label>
                  <select aria-label="Organização de destino" className="select" id="billing-transfer-owner" onChange={(event) => setOrganizationUuid(event.target.value)} required value={organizationUuid}><option value="">Escolha a organização</option>{organizations.map((organization) => <option key={organization.uuid} value={organization.uuid}>{organization.name}</option>)}</select>
                  <button className="btn btn--primary btn--sm" disabled={!organizationUuid || activeAction !== null} onClick={() => { setPendingTransfer(true); setActionsOpen(false); }} type="button">Transferir</button>
                </div> : null}
                {billing.capabilities.can_delete ? <><div className="status-menu__separator" /><button className="btn-dropdown-item btn-dropdown-item--danger" disabled={activeAction !== null} onClick={() => { setPendingDelete(true); setActionsOpen(false); }} type="button">Excluir cobrança</button></> : null}
              </div>
            </div> : null}
          </div>
        </header>

        {billing.pix_needs_setup ? <div className="billing-workspace__notice" role="alert"><strong>PIX pendente.</strong> Preencha a chave, o nome e a cidade do recebedor {ownerIsOrganization ? <>em <Link to="/organizations/">Organizações</Link></> : <>em <Link to="/security">Segurança</Link></>}{billing.capabilities.can_edit ? <> ou na <Link to={`/billings/${billingUuid}/edit`}>edição desta cobrança</Link></> : null} para gerar faturas.</div> : null}

        <div className="billing-workspace__body">
          <section className="billing-ledger" aria-labelledby="billing-items-heading">
            <div className="billing-section-heading"><div><span>Modelo recorrente</span><h2 id="billing-items-heading">Itens da cobrança</h2></div><small>{billing.items.length} {billing.items.length === 1 ? "item" : "itens"}</small></div>
            <div className="bill-ledger__table"><table className="table"><thead><tr><th>Descrição</th><th className="center">Tipo</th><th className="num">Valor</th></tr></thead><tbody>{billing.items.map((item, index) => <tr key={`${item.description}-${index}`}><td className="table__primary">{item.description}</td><td className="center"><span className={`tag tag--${item.item_type}`}>{item.item_type === "fixed" ? "Fixo" : "Variável"}</span></td><td className="num">{item.item_type === "fixed" ? formatBrl(item.amount) : <span className="muted">por fatura</span>}</td></tr>)}<tr className="total"><td colSpan={2}>Subtotal fixo</td><td className="num">{formatBrl(fixedSubtotal)}</td></tr></tbody></table></div>
          </section>
          <aside className="billing-pix-rail" aria-labelledby="billing-pix-heading">
            <div className="billing-pix-rail__heading"><span className="bill-payment-rail__label">Recebimento</span><QrCode aria-hidden="true" size={20} /></div>
            <h2 id="billing-pix-heading">Recebimento PIX</h2>
            {hasPixOverride ? <dl className="billing-pix-rail__details">
              {billing.pix_key ? <div><dt>Chave PIX (override)</dt><dd className="mono">{billing.pix_key}</dd></div> : null}
              <div><dt>Recebedor</dt><dd>{billing.pix_merchant_name || "Não informado"}</dd></div>
              <div><dt>Cidade</dt><dd className="mono">{billing.pix_merchant_city || "Não informada"}</dd></div>
            </dl> : <p className="billing-pix-rail__copy">Sem dados específicos nesta cobrança. O PIX usa a configuração do proprietário ({ownerIsOrganization ? "organização" : "sua conta"}).</p>}
            <div className={`tag ${billing.pix_needs_setup ? "tag--draft" : "tag--paid"}`}><span className="dot" />{billing.pix_needs_setup ? "PIX pendente" : "PIX configurado"}</div>
          </aside>
        </div>

        {availableTabs.length ? <section className="bill-records billing-records" aria-label="Registros da cobrança">
          <div aria-label="Registros da cobrança" className="bill-records__tabs" role="tablist">
            {availableTabs.includes("bills") ? <button aria-controls="billing-bills-panel" aria-selected={selectedTab === "bills"} id="billing-bills-tab" onClick={() => changeTab("bills")} onKeyDown={(event) => handleTabKeyDown(event, "bills", availableTabs)} ref={(element) => { tabRefs.current[availableTabs.indexOf("bills")] = element; }} role="tab" tabIndex={selectedTab === "bills" ? 0 : -1} type="button">Faturas <span>{bills.length}</span></button> : null}
            {availableTabs.includes("expenses") ? <button aria-controls="billing-expenses-panel" aria-selected={selectedTab === "expenses"} id="billing-expenses-tab" onClick={() => changeTab("expenses")} onKeyDown={(event) => handleTabKeyDown(event, "expenses", availableTabs)} ref={(element) => { tabRefs.current[availableTabs.indexOf("expenses")] = element; }} role="tab" tabIndex={selectedTab === "expenses" ? 0 : -1} type="button">Despesas <span>{expenses.length}</span></button> : null}
            {availableTabs.includes("documents") ? <button aria-controls="billing-documents-panel" aria-selected={selectedTab === "documents"} id="billing-documents-tab" onClick={() => changeTab("documents")} onKeyDown={(event) => handleTabKeyDown(event, "documents", availableTabs)} ref={(element) => { tabRefs.current[availableTabs.indexOf("documents")] = element; }} role="tab" tabIndex={selectedTab === "documents" ? 0 : -1} type="button">Documentos <span>{attachments.length}</span></button> : null}
          </div>

          {selectedTab === "bills" ? <div aria-labelledby="billing-bills-tab" className="bill-records__panel billing-records__panel--flush" id="billing-bills-panel" role="tabpanel">
            <div className="billing-tab-toolbar"><div><h2>Faturas</h2>{billing.capabilities.can_read_bills ? <span>{bills.length} {bills.length === 1 ? "gerada" : "geradas"}</span> : null}</div>{billing.capabilities.can_create_exports ? <div><button className="btn btn--sm" disabled={activeAction !== null} onClick={() => void exportBills("csv")} title="Enviar as faturas em CSV para o seu e-mail" type="button">Exportar CSV</button><button className="btn btn--sm" disabled={activeAction !== null} onClick={() => void exportBills("xlsx")} title="Enviar as faturas em Excel para o seu e-mail" type="button">Exportar Excel</button></div> : null}</div>
            {billing.capabilities.can_read_bills ? bills.length ? <div className="table-wrap"><table className="table"><thead><tr><th>Referência</th><th className="num">Total</th><th className="center">Vencimento</th><th className="center">Status</th><th /></tr></thead><tbody>{bills.map((bill) => <tr key={bill.uuid}><td className="table__primary"><Link to={`/billings/${billingUuid}/bills/${bill.uuid}`}>{formatMonth(bill.reference_month)}</Link></td><td className="num">{formatBrl(bill.total_amount)}</td><td className="center mono">{bill.due_date || "Sem data"}</td><td className="center"><StatusTag status={bill.status} /></td><td className="num"><Link className="btn btn--sm" to={`/billings/${billingUuid}/bills/${bill.uuid}`}>Ver</Link></td></tr>)}</tbody></table></div> : <div className="empty-state billing-tab-empty"><p>Nenhuma fatura gerada para este imóvel.</p>{billing.capabilities.can_create_bills && !billing.pix_needs_setup ? <Link className="btn btn--primary btn--sm" to={`/billings/${billingUuid}/bills/generate`}>Gerar primeira fatura</Link> : null}</div> : null}
          </div> : null}

          {selectedTab === "expenses" ? <div aria-labelledby="billing-expenses-tab" className="bill-records__panel" id="billing-expenses-panel" role="tabpanel">
            <div className="billing-tab-toolbar"><div><h2 ref={expenseHeadingRef} tabIndex={-1}>Despesas</h2><span>Resultado líquido no ano</span></div></div>
            <dl className="billing-expense-summary"><div><dt>Recebido (ano)</dt><dd>{formatBrl(billing.stats.received)}</dd></div><div><dt>Despesas</dt><dd>{formatBrl(billing.stats.total_expenses)}</dd></div><div><dt>Resultado líquido</dt><dd>{formatBrl(billing.stats.net_income)}</dd></div></dl>
            {billing.capabilities.can_read_expenses ? expenses.length ? <div className="table-wrap"><table className="table"><thead><tr><th>Descrição</th><th className="center">Categoria</th><th className="center">Data</th><th className="num">Valor</th>{billing.capabilities.can_write_expenses ? <th /> : null}</tr></thead><tbody>{expenses.map((expense) => <tr key={expense.uuid}><td className="table__primary">{expense.description}</td><td className="center">{CATEGORY_LABELS[expense.category]}</td><td className="center mono">{expense.incurred_on}</td><td className="num">{formatBrl(expense.amount)}</td>{billing.capabilities.can_write_expenses ? <td className="num"><button aria-label={`Remover despesa ${expense.description}`} className="btn btn--danger btn--sm" disabled={activeAction !== null} onClick={() => setPendingExpense(expense)} type="button">Remover</button></td> : null}</tr>)}</tbody></table></div> : <p className="muted">Nenhuma despesa registrada.</p> : null}
            {billing.capabilities.can_write_expenses ? <form className="billing-expense-form" onSubmit={addExpense}><div className="field mb-0"><label className="field__label" htmlFor="expense-description">Descrição</label><input aria-describedby={expenseErrors.description ? "expense-description-error" : undefined} aria-label="Descrição da despesa" className="input" id="expense-description" name="expense-description" onChange={(event) => setExpenseDescription(limitApiCharacters(event.target.value, 2000))} placeholder="Ex.: Pintura" required type="text" value={expenseDescription} /><FieldError id="expense-description-error" message={expenseErrors.description} /></div><div className="field mb-0"><label className="field__label" htmlFor="expense-category">Categoria</label><select aria-describedby={expenseErrors.category ? "expense-category-error" : undefined} aria-label="Categoria da despesa" className="select" id="expense-category" name="expense-category" onChange={(event) => setExpenseCategory(event.target.value as ExpenseCategory)} required value={expenseCategory}>{Object.entries(CATEGORY_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select><FieldError id="expense-category-error" message={expenseErrors.category} /></div><div className="field mb-0"><label className="field__label" htmlFor="expense-date">Data</label><input aria-describedby={expenseErrors.incurred_on ? "expense-date-error" : undefined} aria-label="Data da despesa" className="input" id="expense-date" name="expense-incurred_on" onChange={(event) => setExpenseDate(event.target.value)} required type="date" value={expenseDate} /><FieldError id="expense-date-error" message={expenseErrors.incurred_on} /></div><div className="field mb-0"><label className="field__label" htmlFor="expense-amount">Valor (R$)</label><input aria-describedby={expenseErrors.amount ? "expense-amount-error" : undefined} aria-label="Valor da despesa (R$)" className="input" id="expense-amount" inputMode="decimal" name="expense-amount" onChange={(event) => setExpenseAmount(event.target.value)} placeholder="0,00" required type="text" value={expenseAmount} /><FieldError id="expense-amount-error" message={expenseErrors.amount} /></div><button className="btn btn--primary btn--sm" disabled={activeAction !== null} type="submit">Adicionar despesa</button></form> : null}
          </div> : null}

          {selectedTab === "documents" ? <div aria-labelledby="billing-documents-tab" className="bill-records__panel billing-records__panel--flush" id="billing-documents-panel" role="tabpanel">
            <div className="billing-tab-toolbar"><div><h2>Documentos</h2><span>{attachments.length} {attachments.length === 1 ? "anexo" : "anexos"}</span></div>{billing.capabilities.can_write_attachments ? <Link className="btn btn--sm" to={`/billings/${billingUuid}/edit`}>Gerenciar documentos</Link> : null}</div>
            {attachments.length ? <div className="table-wrap"><table className="table"><thead><tr><th>Nome</th><th>Arquivo</th><th className="num">Tamanho</th><th /></tr></thead><tbody>{attachments.map((attachment) => <tr key={attachment.uuid}><td className="table__primary">{attachment.name}</td><td className="muted">{attachment.filename}</td><td className="num">{(attachment.file_size / 1024).toFixed(1)} KB</td><td className="num"><a className="btn btn--sm" href={`/api/v1/billings/${billingUuid}/attachments/${attachment.uuid}`} rel="noreferrer" target="_blank">Baixar</a></td></tr>)}</tbody></table></div> : <div className="empty-state billing-tab-empty"><p>Nenhum documento anexado.</p>{billing.capabilities.can_write_attachments ? <Link className="btn btn--sm" to={`/billings/${billingUuid}/edit`}>Anexar documento</Link> : null}</div>}
          </div> : null}
        </section> : null}
      </article>

      <ConfirmDialog acceptLabel="Remover" body="A despesa será removida permanentemente." onClose={() => setPendingExpense(null)} onConfirm={() => { if (pendingExpense) void removeExpense(pendingExpense); }} open={pendingExpense !== null} title="Remover esta despesa?" />
      <ConfirmDialog acceptLabel="Confirmar transferência" body="Esta ação não pode ser desfeita." onClose={() => setPendingTransfer(false)} onConfirm={() => void transfer()} open={pendingTransfer} title="Transferir cobrança?" variant="primary" />
      <ConfirmDialog acceptLabel="Excluir cobrança permanentemente" body="A cobrança e suas faturas serão excluídas. Esta ação não pode ser desfeita." onClose={() => setPendingDelete(false)} onConfirm={() => void deleteBilling()} open={pendingDelete} title="Excluir cobrança?" />
    </>
  );
}
