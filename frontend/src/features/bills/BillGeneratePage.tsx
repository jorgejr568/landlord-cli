import { Plus, Trash2 } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { Link, useNavigate, useParams } from "react-router";

import { FieldError } from "../../components/FieldError";
import { FormWizard, WizardReviewRow, WizardSummary, type WizardStep } from "../../components/FormWizard";
import { DirtyFormGuard } from "../../forms/useDirtyFormGuard";
import { EmptyState, LoadError, LoadingState } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage, firstFieldError, normalizedFieldErrors } from "../../lib/api/errors";
import type { paths } from "../../lib/api/schema";
import { formatBrl, formatBrlInput, formatMonth, MAX_PERSISTED_CENTAVOS, parseBrl, parseDateInput } from "../../lib/format";
import { limitApiCharacters } from "../../lib/textLimits";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import type { Billing } from "./billSupport";
import { multipartBodySerializer } from "./billSupport";
import { receiptFileError } from "./receiptFiles";

interface ExtraRow {
  amount: string;
  description: string;
  key: number;
}

interface BillCreatePayload {
  due_date: string | null;
  extras: Array<{ amount: number; description: string }>;
  notes: string;
  reference_month: string;
  variable_amounts: Record<string, number>;
}

type GenerateBilling = Omit<Billing, "capabilities"> & {
  capabilities: Billing["capabilities"] & { can_upload_bill_receipts: boolean };
};

const GENERATE_STEPS: WizardStep[] = [
  { description: "Escolha o período cobrado nesta fatura.", id: "reference", label: "Competência" },
  { description: "Defina quando o pagamento deve acontecer.", id: "due-date", label: "Vencimento" },
  { description: "Preencha os valores variáveis e acrescente despesas pontuais.", id: "items", label: "Itens" },
  { description: "Inclua orientações e documentos de apoio, se necessário.", id: "notes", label: "Observações e comprovantes" },
  { description: "Confira todos os dados antes de criar o rascunho.", id: "review", label: "Revisar fatura" }
];

export function BillGeneratePage() {
  const { billingUuid = "" } = useParams<{ billingUuid: string }>();
  const navigate = useNavigate();
  const [billing, setBilling] = useState<GenerateBilling | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [referenceMonth, setReferenceMonth] = useState("");
  const [dueDate, setDueDate] = useState("");
  const [notes, setNotes] = useState("");
  const [variableAmounts, setVariableAmounts] = useState<Record<string, string>>({});
  const [extras, setExtras] = useState<ExtraRow[]>([]);
  const [files, setFiles] = useState<File[]>([]);
  const [fileError, setFileError] = useState("");
  const [isDirty, setIsDirty] = useState(false);
  const [activeStep, setActiveStep] = useState(0);
  const [visitedStep, setVisitedStep] = useState(0);
  const [focusRequest, setFocusRequest] = useState<{ field: string; sequence: number } | null>(null);
  const nextExtraKey = useRef(0);
  const referenceRef = useRef<HTMLInputElement>(null);
  const receiptRef = useRef<HTMLInputElement>(null);
  const variableRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const extraRefs = useRef<Record<string, HTMLInputElement | null>>({});
  const loadController = useRef<AbortController | null>(null);
  const mutationController = useRef<AbortController | null>(null);
  const submissionInFlight = useRef(false);

  useDocumentTitle(billing ? `Gerar Fatura - ${billing.name} - Rentivo` : "Gerar Fatura - Rentivo");

  const load = useCallback(async () => {
    loadController.current?.abort();
    mutationController.current?.abort();
    const controller = new AbortController();
    loadController.current = controller;
    setLoading(true);
    setLoadError("");
    setBilling(null);
    setActionError("");
    setFieldErrors({});
    setSubmitting(false);
    setReferenceMonth("");
    setDueDate("");
    setNotes("");
    setVariableAmounts({});
    setExtras([]);
    setFiles([]);
    setFileError("");
    setIsDirty(false);
    setActiveStep(0);
    setVisitedStep(0);
    setFocusRequest(null);
    nextExtraKey.current = 0;
    variableRefs.current = {};
    extraRefs.current = {};
    try {
      const { data } = await apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}", {
        params: { path: { billing_uuid: billingUuid } }, signal: controller.signal
      }));
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      setBilling(data as GenerateBilling);
      setVariableAmounts(Object.fromEntries(
        data.items.filter((item) => item.item_type === "variable").map((item) => [item.uuid, ""])
      ));
      setLoading(false);
      requestAnimationFrame(() => referenceRef.current?.focus());
    } catch (caught) {
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      setLoadError(errorMessage(caught, "Não foi possível carregar a cobrança."));
      setLoading(false);
    }
  }, [billingUuid]);

  useEffect(() => {
    void load();
    return () => {
      loadController.current?.abort();
      mutationController.current?.abort();
    };
  }, [load]);

  const stepForField = (key: string | undefined): number => {
    if (key === "reference_month") return 0;
    if (key === "due_date") return 1;
    if (key?.startsWith("variable_amounts.") || key?.startsWith("extras.")) return 2;
    return 3;
  };

  const focusError = (key: string | undefined) => {
    /* v8 ignore next -- callers only invoke focus after resolving a field key */
    if (!key) return;
    if (key === "reference_month") referenceRef.current?.focus();
    else if (key.startsWith("variable_amounts.")) {
      const input = variableRefs.current[key.slice("variable_amounts.".length)];
      if (input) input.focus();
    }
    else if (key === "receipt_files") receiptRef.current?.focus();
    else extraRefs.current[key]?.focus();
  };

  useEffect(() => {
    if (!focusRequest) return;
    const frame = requestAnimationFrame(() => focusError(focusRequest.field));
    return () => cancelAnimationFrame(frame);
  }, [activeStep, fieldErrors, focusRequest]);

  const parsedItemValues = () => {
    /* v8 ignore next -- the form is only interactive after loading */
    if (!billing) return { errors: {}, extras: [], total: 0, variables: {} };
    const errors: Record<string, string> = {};
    const parsedExtras = extras.map((extra) => ({
      amount: parseBrl(extra.amount), description: extra.description.trim(), key: extra.key
    }));
    parsedExtras.forEach((extra, index) => {
      if (!extra.description) errors[`extras.${index}.description`] = "Informe a descrição.";
      /* v8 ignore start -- the controlled input truncates API characters before this defense */
      else if (Array.from(extra.description).length > 255) errors[`extras.${index}.description`] = "A descrição deve ter no máximo 255 caracteres.";
      /* v8 ignore stop */
      if (extra.amount === null || extra.amount <= 0) errors[`extras.${index}.amount`] = "Informe um valor maior que zero.";
    });
    const variableValues: Record<string, number> = {};
    billing.items.forEach((item) => {
      if (item.item_type !== "variable") return;
      const parsed = parseBrl(variableAmounts[item.uuid]);
      if (parsed === null) errors[`variable_amounts.${item.uuid}`] = "Informe um valor válido.";
      else variableValues[item.uuid] = parsed;
    });
    const fixedSubtotal = billing.items.reduce(
      (total, item) => total + (item.item_type === "fixed" ? item.amount : 0), 0
    );
    const total = fixedSubtotal
      + Object.values(variableValues).reduce((sum, amount) => sum + amount, 0)
      + parsedExtras.reduce((sum, extra) => sum + (extra.amount ?? 0), 0);
    if (total > MAX_PERSISTED_CENTAVOS) {
      const firstVariable = billing.items.find((item) => item.item_type === "variable");
      const field = firstVariable ? `variable_amounts.${firstVariable.uuid}` : "extras.0.amount";
      errors[field] = "O valor total deve ser de no máximo R$ 21.474.836,47.";
    }
    return { errors, extras: parsedExtras, total, variables: variableValues };
  };

  const errorsForStep = (step: number): Record<string, string> => {
    if (step === 0) return referenceMonth ? {} : { reference_month: "Informe o mês de referência." };
    if (step === 1) {
      const parsedDate = parseDateInput(dueDate);
      return parsedDate === undefined ? { due_date: "Informe uma data válida." } : {};
    }
    if (step === 2) return parsedItemValues().errors;
    if (step === 3 && billing?.capabilities.can_upload_bill_receipts) {
      const validationError = receiptFileError(files);
      return validationError ? { receipt_files: validationError } : {};
    }
    return {};
  };

  const focusStepError = (step: number, errors: Record<string, string>) => {
    const field = firstFieldError(errors, step === 0 ? ["reference_month"] : step === 1 ? ["due_date"] : []);
    setActiveStep(step);
    if (field) setFocusRequest((current) => ({ field, sequence: (current?.sequence ?? 0) + 1 }));
  };

  const continueWizard = () => {
    const errors = errorsForStep(activeStep);
    if (Object.keys(errors).length) {
      setFieldErrors((current) => ({ ...current, ...errors }));
      if (errors.receipt_files) setFileError(errors.receipt_files);
      focusStepError(activeStep, errors);
      return;
    }
    setFieldErrors((current) => Object.fromEntries(
      Object.entries(current).filter(([key]) => stepForField(key) !== activeStep)
    ));
    if (activeStep === 3) setFileError("");
    const next = Math.min(activeStep + 1, GENERATE_STEPS.length - 1);
    setVisitedStep((current) => Math.max(current, next));
    setActiveStep(next);
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (submissionInFlight.current) return;
    /* v8 ignore next -- the form is only rendered after billing loading */
    if (!billing) return;
    setActionError("");
    setFieldErrors({});

    for (let step = 0; step < GENERATE_STEPS.length - 1; step += 1) {
      const errors = errorsForStep(step);
      if (Object.keys(errors).length) {
        setFieldErrors(errors);
        if (errors.receipt_files) setFileError(errors.receipt_files);
        focusStepError(step, errors);
        return;
      }
    }
    const parsedDate = parseDateInput(dueDate);
    const itemValues = parsedItemValues();
    const payload: BillCreatePayload = {
      due_date: parsedDate ?? null,
      extras: itemValues.extras.map(({ amount, description }) => ({ amount: amount!, description })),
      notes,
      reference_month: referenceMonth,
      variable_amounts: itemValues.variables
    };
    type CreateBody =
      paths["/api/v1/billings/{billing_uuid}/bills"]["post"]["requestBody"]["content"]["multipart/form-data"];
    // The multipart `payload` field is sent as a JSON string on the wire; the generated
    // client models it as the pre-serialized BillCreateRequest object, so bridge via `unknown`.
    const requestBody = {
      payload: JSON.stringify(payload),
      ...(billing.capabilities.can_upload_bill_receipts ? { receipt_files: files } : {})
    } as unknown as CreateBody;
    submissionInFlight.current = true;
    const controller = new AbortController();
    mutationController.current = controller;
    setSubmitting(true);
    try {
      const { data, response } = await apiRequest(apiClient.POST(
        "/api/v1/billings/{billing_uuid}/bills",
        {
          body: requestBody, bodySerializer: multipartBodySerializer,
          params: { path: { billing_uuid: billingUuid } }, signal: controller.signal
        }
      ));
      if (controller.signal.aborted) return;
      pushAnalyticsFromResponse(response);
      navigate(`/billings/${billingUuid}/bills/${data.uuid}`);
    } catch (caught) {
      if (controller.signal.aborted) return;
      const errors = normalizedFieldErrors(caught);
      setFieldErrors(errors);
      setActionError(errorMessage(caught, "Não foi possível gerar a fatura."));
      const field = firstFieldError(errors, ["reference_month", "due_date"]);
      const step = stepForField(field);
      setVisitedStep((current) => Math.max(current, step));
      focusStepError(step, errors);
    } finally {
      submissionInFlight.current = false;
      if (!controller.signal.aborted) setSubmitting(false);
    }
  };

  if (loading) return <LoadingState label="Carregando cobrança..." />;
  if (loadError) return <LoadError message={loadError} onRetry={() => void load()} />;
  /* v8 ignore next -- successful loading always sets the billing resource */
  if (!billing) return null;
  if (!billing.capabilities.can_manage_bills) {
    return <EmptyState body="Você não possui permissão para gerar faturas nesta cobrança." title="Geração indisponível" />;
  }
  if (billing.pix_needs_setup) {
    return <EmptyState action={<Link className="btn btn--primary" to={`/billings/${billingUuid}/edit`}>Configurar PIX</Link>} body="Configure a chave, o nome e a cidade do recebedor antes de gerar uma fatura." title="PIX necessário" />;
  }

  const itemValues = parsedItemValues();
  const fixedSubtotal = billing.items.reduce(
    (total, item) => total + (item.item_type === "fixed" ? item.amount : 0), 0
  );
  const variableSubtotal = Object.values(itemValues.variables).reduce((total, amount) => total + amount, 0);
  const extrasSubtotal = itemValues.extras.reduce((total, extra) => total + (extra.amount ?? 0), 0);
  const dueDateLabel = dueDate
    ? new Date(`${dueDate}T12:00:00`).toLocaleDateString("pt-BR")
    : "Sem vencimento definido";
  const invoiceSummary = (
    <WizardSummary title="Resumo da fatura">
      <dl className="summary-list">
        <div><dt>Cobrança</dt><dd>{billing.name}</dd></div>
        <div><dt>Competência</dt><dd>{referenceMonth ? formatMonth(referenceMonth) : "A definir"}</dd></div>
        <div><dt>Vencimento</dt><dd>{dueDateLabel}</dd></div>
        <div><dt>Itens fixos</dt><dd>{formatBrl(fixedSubtotal)}</dd></div>
        <div><dt>Variáveis e extras</dt><dd>{formatBrl(variableSubtotal + extrasSubtotal)}</dd></div>
        <div className="summary-list__total"><dt>Total</dt><dd>{formatBrl(itemValues.total)}</dd></div>
      </dl>
    </WizardSummary>
  );

  const renderStep = () => {
    if (activeStep === 0) return (
      <div className="field mb-0">
        <label className="field-label field__label" htmlFor="reference_month">Mês de Referência</label>
        <input aria-describedby={fieldErrors.reference_month ? "reference_month-error" : undefined} className="field-input input" id="reference_month" onChange={(event) => setReferenceMonth(event.target.value)} ref={referenceRef} required type="month" value={referenceMonth} />
        <span className="field__hint">Este período aparece na fatura e organiza o histórico da cobrança.</span>
        <FieldError id="reference_month-error" message={fieldErrors.reference_month} />
      </div>
    );
    if (activeStep === 1) return (
      <div className="field mb-0">
        <label className="field-label field__label" htmlFor="due_date">Vencimento</label>
        <input aria-describedby={/* v8 ignore next -- native date controls exclude malformed non-empty values */ fieldErrors.due_date ? "due_date-error" : undefined} className="field-input input" id="due_date" onChange={(event) => setDueDate(event.target.value)} type="date" value={dueDate} />
        <span className="field__hint">Você pode deixar em branco para publicar a fatura sem data de vencimento.</span>
        <FieldError id="due_date-error" message={fieldErrors.due_date} />
      </div>
    );
    if (activeStep === 2) return (
      <>
        <div className="panel">
          <div className="panel-head panel__head"><h5>Itens recorrentes</h5><span className="panel__title-eyebrow">{billing.items.length} {billing.items.length === 1 ? "item" : "itens"}</span></div>
          <div className="panel-body panel__body">
            {billing.items.map((item) => {
              const key = `variable_amounts.${item.uuid}`;
              return (
                <div className="formset-row" key={item.uuid}>
                  <div className="generate-item-grid">
                    <div><strong>{item.description}</strong> <span className={`tag tag--${item.item_type}`}>{item.item_type === "fixed" ? "Fixo" : "Variável"}</span></div>
                    <div>{item.item_type === "fixed"
                      ? <input aria-label={`${item.description} (fixo)`} className="field-input" disabled value={formatBrlInput(item.amount)} />
                      : <><input aria-describedby={fieldErrors[key] ? `${key}-error` : undefined} aria-label={item.description} className="field-input" inputMode="decimal" onChange={(event) => setVariableAmounts((values) => ({ ...values, [item.uuid]: event.target.value }))} placeholder="0,00" ref={(node) => { variableRefs.current[item.uuid] = node; }} required value={variableAmounts[item.uuid]} /><FieldError id={`${key}-error`} message={fieldErrors[key]} /></>}
                    </div>
                    <div className="text-muted text-mono">{item.item_type === "fixed" ? formatBrl(item.amount) : ""}</div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
        <div className="panel">
          <div className="panel-head panel__head"><div><h5>Despesas extras</h5><p className="panel__desc">Valores que pertencem apenas a esta fatura.</p></div><button aria-label="Adicionar despesa extra" className="btn btn--sm btn--primary" onClick={() => { setExtras((rows) => [...rows, { amount: "", description: "", key: nextExtraKey.current++ }]); setIsDirty(true); }} type="button"><Plus aria-hidden="true" size={14} /> Adicionar</button></div>
          <div className="panel-body panel__body">
            {extras.length === 0 && <p className="text-muted">Nenhuma despesa extra.</p>}
            {extras.map((extra, index) => (
              <div className="extras-grid" key={extra.key}>
                <div className="field mb-0"><input aria-label={`Descrição da despesa extra ${index + 1}`} className="field-input" onChange={(event) => setExtras((rows) => rows.map((row) => row.key === extra.key ? { ...row, description: limitApiCharacters(event.target.value, 255) } : row))} placeholder="Descrição" ref={(node) => { extraRefs.current[`extras.${index}.description`] = node; }} value={extra.description} /><FieldError id={`extras.${index}.description-error`} message={fieldErrors[`extras.${index}.description`]} /></div>
                <div className="field mb-0"><input aria-label={`Valor da despesa extra ${index + 1}`} className="field-input" inputMode="decimal" onChange={(event) => setExtras((rows) => rows.map((row) => row.key === extra.key ? { ...row, amount: event.target.value } : row))} placeholder="0,00" ref={(node) => { extraRefs.current[`extras.${index}.amount`] = node; }} value={extra.amount} /><FieldError id={`extras.${index}.amount-error`} message={fieldErrors[`extras.${index}.amount`]} /></div>
                <div><button aria-label={`Remover despesa extra ${index + 1}`} className="btn btn--sm btn--danger" onClick={() => { setExtras((rows) => rows.filter((row) => row.key !== extra.key)); setIsDirty(true); }} type="button"><Trash2 aria-hidden="true" size={14} /> Remover</button></div>
              </div>
            ))}
          </div>
        </div>
      </>
    );
    if (activeStep === 3) return (
      <>
        <div className="field"><label className="field-label field__label" htmlFor="notes">Observações</label><textarea className="field-textarea input" id="notes" onChange={(event) => setNotes(event.target.value)} rows={5} value={notes} /><span className="field__hint">Este texto aparece na fatura. Não inclua informações internas.</span><FieldError id="notes-error" message={fieldErrors.notes} /></div>
        {billing.capabilities.can_upload_bill_receipts ? <div className="field mb-0"><label className="field-label field__label" htmlFor="generate_receipt_files">Anexar comprovantes</label><input accept=".pdf,.jpg,.jpeg,.png" aria-describedby={fileError ? "generate-receipt-files-error" : undefined} className="field-input input" id="generate_receipt_files" multiple onChange={(event) => { setFiles(Array.from(event.currentTarget.files!)); setFileError(""); }} ref={receiptRef} type="file" /><small className="text-muted">PDF, JPG ou PNG. Máximo 10 MB cada. Você pode selecionar vários arquivos.</small><FieldError id="generate-receipt-files-error" message={fileError} /></div> : null}
      </>
    );
    return (
      <dl className="review-list">
        <WizardReviewRow label="Competência" onEdit={() => setActiveStep(0)} value={referenceMonth ? formatMonth(referenceMonth) : "Não informada"} />
        <WizardReviewRow label="Vencimento" onEdit={() => setActiveStep(1)} value={dueDateLabel} />
        <WizardReviewRow label="Itens e valores" onEdit={() => setActiveStep(2)} value={`${billing.items.length + extras.length} itens · ${formatBrl(itemValues.total)}`} />
        <WizardReviewRow label="Observações" onEdit={() => setActiveStep(3)} value={notes || "Nenhuma observação"} />
        <WizardReviewRow label="Comprovantes" onEdit={() => setActiveStep(3)} value={files.length ? `${files.length} ${files.length === 1 ? "arquivo" : "arquivos"}` : "Nenhum arquivo"} />
      </dl>
    );
  };

  return (
    <>
      <DirtyFormGuard isDirty={isDirty && !submitting} />
      <h2 className="mb-1">Gerar Fatura</h2>
      <p className="text-muted">Cobrança: <strong>{billing.name}</strong></p>
      {billing.items.length === 0 && (
        <EmptyState
          action={<Link className="btn btn--primary" to={`/billings/${billingUuid}/edit`}>Cadastrar itens</Link>}
          body="Cadastre ao menos um item antes de gerar a primeira fatura."
          title="Nenhum item cadastrado"
        />
      )}
      {billing.items.length > 0 && (
        <form encType="multipart/form-data" onChange={() => setIsDirty(true)} onSubmit={(event) => void submit(event)}>
          {actionError && <div className="toast toast--danger" role="alert">{actionError}</div>}
          <FormWizard
            activeStep={activeStep}
            aside={invoiceSummary}
            busy={submitting}
            cancelAction={<Link className="btn btn--ghost" to={`/billings/${billingUuid}`}>Cancelar</Link>}
            finalLabel="Gerar Fatura"
            onBack={() => setActiveStep((current) => Math.max(0, current - 1))}
            onNext={continueWizard}
            onStepChange={setActiveStep}
            steps={GENERATE_STEPS}
            visitedStep={visitedStep}
          >
            {renderStep()}
          </FormWizard>
        </form>
      )}
    </>
  );
}
