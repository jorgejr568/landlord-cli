import { ArrowLeft } from "lucide-react";
import { Fragment, useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router";

import { FieldError } from "../../components/FieldError";
import { FormWizard, WizardReviewRow, WizardSummary, type WizardStep } from "../../components/FormWizard";
import { DirtyFormGuard } from "../../forms/useDirtyFormGuard";
import { LoadError, LoadingState } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage, firstFieldError, normalizedFieldErrors } from "../../lib/api/errors";
import type { components } from "../../lib/api/schema";
import { formatBrl, formatIsoDate, formatMonth } from "../../lib/format";
import { limitApiCharacters } from "../../lib/textLimits";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import type { Bill, Billing } from "./billSupport";

type CommType = components["schemas"]["CommunicationSendRequest"]["comm_type"];
const MAX_COMMUNICATION_SUBJECT_LENGTH = 998;
const MAX_COMMUNICATION_BODY_BYTES = 4_096;

const COMMUNICATION_STEPS: WizardStep[] = [
  { description: "Escolha quem receberá uma cópia individual deste documento.", id: "recipients", label: "Destinatários" },
  { description: "Personalize o texto e confira como as variáveis serão preenchidas.", id: "message", label: "Mensagem" },
  { description: "Revise destinatários, conteúdo e preferências antes de enviar.", id: "review", label: "Revisar envio" }
];

const TEMPLATE_VARIABLES = [
  { label: "nome do inquilino", value: "{{nome_inquilino}}" },
  { label: "unidade", value: "{{unidade}}" },
  { label: "mês", value: "{{mes}}" },
  { label: "vencimento", value: "{{vencimento}}" },
  { label: "total", value: "{{total}}" }
] as const;

function normalizeCommunicationContent(subject: string, body: string) {
  return { subject: subject.trim(), body: body.trim() };
}

function communicationContentErrors(subject: string, body: string): Record<string, string> {
  const normalized = normalizeCommunicationContent(subject, body);
  const errors: Record<string, string> = {};
  if (!normalized.subject) errors.subject = "Informe o assunto.";
  /* v8 ignore start -- the controlled input truncates API characters before this defense */
  else if (Array.from(normalized.subject).length > MAX_COMMUNICATION_SUBJECT_LENGTH) {
    errors.subject = "O assunto deve ter no máximo 998 caracteres.";
  }
  /* v8 ignore stop */
  if (!normalized.body) errors.body = "Informe o corpo da mensagem.";
  else if (new TextEncoder().encode(normalized.body).byteLength > MAX_COMMUNICATION_BODY_BYTES) {
    errors.body = "A mensagem deve ter no máximo 4096 bytes.";
  }
  return errors;
}

function isFullContact(contact: Billing["recipients"][number]): contact is Extract<Billing["recipients"][number], { email: string }> {
  return "email" in contact;
}

function stepForCommunicationField(field: string | undefined): number | null {
  if (field?.startsWith("recipient_uuids")) return 0;
  if (field === "subject" || field === "body") return 1;
  if (field === "save_scope") return 2;
  return null;
}

function personalizeContent(content: string, billing: Billing, bill: Bill, recipientName: string): string {
  const values: Record<string, string> = {
    "{{nome_inquilino}}": recipientName,
    "{{unidade}}": billing.name,
    "{{mes}}": formatMonth(bill.reference_month),
    "{{vencimento}}": bill.due_date ? formatIsoDate(bill.due_date) : "sem vencimento",
    "{{total}}": formatBrl(bill.total_amount)
  };
  return Object.entries(values).reduce((result, [variable, value]) => result.replaceAll(variable, value), content);
}

function renderInlineMarkdown(content: string): ReactNode[] {
  return content.split(/(\*\*[^*\n]+\*\*)/g).filter(Boolean).map((part, index) =>
    part.startsWith("**") && part.endsWith("**")
      ? <strong key={`${index}-${part}`}>{part.slice(2, -2)}</strong>
      : <Fragment key={`${index}-${part}`}>{part}</Fragment>
  );
}

function MessagePreviewBody({ content }: { content: string }) {
  return <div className="message-preview__body">{content.split(/\n{2,}/).map((paragraph, paragraphIndex) => (
    <p key={`${paragraphIndex}-${paragraph}`}>{paragraph.split("\n").map((line, lineIndex) => (
      <Fragment key={`${lineIndex}-${line}`}>{lineIndex > 0 ? <br /> : null}{renderInlineMarkdown(line)}</Fragment>
    ))}</p>
  ))}</div>;
}

export function CommunicationComposePage() {
  const { billingUuid = "", billUuid = "" } = useParams<{ billingUuid: string; billUuid: string }>();
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const requestedType = searchParams.get("type");
  const commType: CommType | null = requestedType === "bill_ready" || requestedType === "payment_receipt"
    ? requestedType
    : null;
  const isRecibo = commType === "payment_receipt";
  const commLabel = commType ? (isRecibo ? "recibo de pagamento" : "fatura") : "comunicação";
  const [billing, setBilling] = useState<Billing | null>(null);
  const [bill, setBill] = useState<Bill | null>(null);
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [selectedRecipients, setSelectedRecipients] = useState<string[]>([]);
  const [saveScope, setSaveScope] = useState<"" | "billing" | "owner">("");
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [isDirty, setIsDirty] = useState(false);
  const [activeStep, setActiveStep] = useState(0);
  const [visitedStep, setVisitedStep] = useState(0);
  const loadController = useRef<AbortController | null>(null);
  const sendController = useRef<AbortController | null>(null);
  const sendInFlight = useRef(false);
  const recipientRef = useRef<HTMLInputElement>(null);
  const subjectRef = useRef<HTMLInputElement>(null);
  const bodyRef = useRef<HTMLTextAreaElement>(null);
  const saveScopeRef = useRef<HTMLSelectElement>(null);

  useDocumentTitle(`Enviar ${commLabel} - Rentivo`);

  const load = useCallback(async () => {
    /* v8 ignore next -- invalid communication types never invoke resource loading */
    if (!commType) return;
    loadController.current?.abort();
    sendController.current?.abort();
    const controller = new AbortController();
    loadController.current = controller;
    setBilling(null);
    setBill(null);
    setSubject("");
    setBody("");
    setSelectedRecipients([]);
    setSaveScope("");
    setLoading(true);
    setSending(false);
    setLoadError("");
    setActionError("");
    setFieldErrors({});
    setIsDirty(false);
    setActiveStep(0);
    setVisitedStep(0);
    try {
      const [billingResult, billResult] = await Promise.all([
        apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}", { params: { path: { billing_uuid: billingUuid } }, signal: controller.signal })),
        apiRequest(apiClient.GET("/api/v1/billings/{billing_uuid}/bills/{bill_uuid}", { params: { path: { billing_uuid: billingUuid, bill_uuid: billUuid } }, signal: controller.signal }))
      ]);
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      const template = billingResult.data.communication_templates.find((item) => item.comm_type === commType);
      setBilling(billingResult.data);
      setBill(billResult.data);
      setSubject(template?.subject ?? "");
      setBody(template?.body ?? "");
      setSelectedRecipients(billingResult.data.recipients.map((recipient) => recipient.uuid));
      setLoading(false);
    } catch (caught) {
      /* v8 ignore next -- an aborted request is intentionally discarded */
      if (controller.signal.aborted) return;
      setLoadError(errorMessage(caught, "Não foi possível carregar a comunicação."));
      setLoading(false);
    }
  }, [billUuid, billingUuid, commType]);

  useEffect(() => {
    if (commType) void load();
    return () => {
      loadController.current?.abort();
      sendController.current?.abort();
    };
  }, [commType, load]);

  const focusError = (key: string | undefined) => {
    const step = stepForCommunicationField(key);
    if (step === null) return;
    const focusTarget = () => {
      if (key?.startsWith("recipient_uuids")) recipientRef.current?.focus();
      else if (key === "subject") subjectRef.current?.focus();
      else if (key === "body") bodyRef.current?.focus();
      else saveScopeRef.current?.focus();
    };
    if (activeStep === step) {
      focusTarget();
      return;
    }
    setActiveStep(step);
    setVisitedStep((current) => Math.max(current, step));
    requestAnimationFrame(() => requestAnimationFrame(focusTarget));
  };

  const continueWizard = () => {
    setActionError("");
    if (activeStep === 0 && selectedRecipients.length === 0) {
      const errors = { recipient_uuids: "Selecione ao menos um destinatário." };
      setFieldErrors(errors);
      focusError("recipient_uuids");
      return;
    }
    if (activeStep === 1) {
      const errors = communicationContentErrors(subject, body);
      setFieldErrors(errors);
      const firstError = firstFieldError(errors, ["subject", "body"]);
      if (firstError) {
        focusError(firstError);
        return;
      }
    }
    setFieldErrors({});
    const nextStep = Math.min(activeStep + 1, COMMUNICATION_STEPS.length - 1);
    setActiveStep(nextStep);
    setVisitedStep((current) => Math.max(current, nextStep));
  };

  const insertVariable = (variable: string) => {
    const textarea = bodyRef.current;
    const hasTextCursor = textarea && document.activeElement === textarea;
    const start = hasTextCursor ? textarea.selectionStart : body.length;
    const end = hasTextCursor ? textarea.selectionEnd : body.length;
    const nextBody = `${body.slice(0, start)}${variable}${body.slice(end)}`;
    setBody(nextBody);
    setIsDirty(true);
    requestAnimationFrame(() => {
      const nextCursor = start + variable.length;
      bodyRef.current?.focus();
      bodyRef.current?.setSelectionRange(nextCursor, nextCursor);
    });
  };

  const send = async (event: FormEvent) => {
    event.preventDefault();
    if (sendInFlight.current) return;
    /* v8 ignore next -- invalid communication types never render the send form */
    if (!commType) return;
    setActionError(""); setFieldErrors({});
    if (selectedRecipients.length === 0) {
      setFieldErrors({ recipient_uuids: "Selecione ao menos um destinatário." });
      focusError("recipient_uuids");
      return;
    }
    const localErrors = communicationContentErrors(subject, body);
    if (Object.keys(localErrors).length) {
      setFieldErrors(localErrors);
      requestAnimationFrame(() => focusError(firstFieldError(localErrors, ["subject", "body"])));
      return;
    }
    const normalized = normalizeCommunicationContent(subject, body);
    sendInFlight.current = true;
    const controller = new AbortController();
    sendController.current = controller;
    setSending(true);
    try {
      const requestBody: components["schemas"]["CommunicationSendRequest"] = {
        acknowledge_warning: false,
        bill_uuid: billUuid,
        body: normalized.body,
        comm_type: commType,
        recipient_uuids: selectedRecipients,
        save_scope: saveScope || null,
        subject: normalized.subject
      };
      const { response } = await apiRequest(apiClient.POST(
        "/api/v1/billings/{billing_uuid}/communications/send",
        { body: requestBody, params: { path: { billing_uuid: billingUuid } }, signal: controller.signal }
      ));
      if (controller.signal.aborted) return;
      pushAnalyticsFromResponse(response);
      navigate(`/billings/${billingUuid}/bills/${billUuid}`);
    } catch (caught) {
      if (controller.signal.aborted) return;
      const errors = normalizedFieldErrors(caught);
      setFieldErrors(errors);
      setActionError(errorMessage(caught, "Não foi possível enviar a comunicação."));
      requestAnimationFrame(() => focusError(firstFieldError(errors, ["recipient_uuids", "subject", "body", "save_scope"])));
    } finally {
      sendInFlight.current = false;
      if (!controller.signal.aborted) setSending(false);
    }
  };

  if (!commType) return <div className="panel"><div className="panel__body"><p className="text-muted">Tipo de comunicação inválido.</p></div></div>;
  if (loading) return <LoadingState label="Carregando comunicação..." />;
  if (loadError) return <LoadError message={loadError} onRetry={() => void load()} />;
  /* v8 ignore next -- successful paired loading always sets both resources */
  if (!billing || !bill) return null;

  if (!bill.capabilities.can_compose) {
    return <div className="panel"><div className="panel__body"><p className="text-muted">Você não possui permissão para enviar esta comunicação.</p></div></div>;
  }
  const canSendDocument = isRecibo ? bill.capabilities.can_send_recibo : bill.capabilities.can_send_invoice;
  if (!canSendDocument) {
    return <div className="panel"><div className="panel__body"><p className="text-muted">{isRecibo ? "O recibo ainda está sendo gerado." : "A fatura ainda está sendo gerada."}</p></div></div>;
  }

  const selectedPreviewRecipient = billing.recipients.filter(isFullContact).find((recipient) => selectedRecipients.includes(recipient.uuid));
  const previewRecipientName = selectedPreviewRecipient?.name ?? "destinatário";
  const previewSubject = personalizeContent(subject, billing, bill, previewRecipientName);
  const previewBody = personalizeContent(body, billing, bill, previewRecipientName);
  const bodyBytes = new TextEncoder().encode(body).length;
  const preview = (
    <WizardSummary title="Prévia personalizada">
      <div className="message-preview">
        <span className="message-preview__to">Para {previewRecipientName}</span>
        <strong>{previewSubject || "Assunto da mensagem"}</strong>
        <MessagePreviewBody content={previewBody || "A mensagem aparecerá aqui enquanto você escreve."} />
        <span className="message-preview__attachment">{isRecibo ? "Recibo" : "Fatura"} · PDF anexado</span>
      </div>
    </WizardSummary>
  );

  return (
    <>
      <DirtyFormGuard isDirty={isDirty && !sending} />
      <Link className="crumb" to={`/billings/${billingUuid}/bills/${billUuid}`}><ArrowLeft aria-hidden="true" size={16} /> Fatura {formatMonth(bill.reference_month)}</Link>
      <div className="pagehead"><div><h1 className="pagehead__title">Enviar {commLabel}</h1><p className="pagehead__sub">{billing.name} · {formatMonth(bill.reference_month)}. Cada destinatário recebe um e-mail separado com o {isRecibo ? "recibo" : "PDF da fatura"} anexado.</p></div></div>
      {billing.recipients.length === 0 ? <div className="panel"><div className="panel__body"><p className="text-muted">Nenhum destinatário cadastrado. <Link to={`/billings/${billingUuid}/edit`}>Adicione destinatários</Link> na cobrança antes de enviar.</p></div></div> : (
        <form id="comm-form" onChange={() => setIsDirty(true)} onSubmit={(event) => void send(event)}>
          {actionError ? <div className="toast toast--danger" role="alert">{actionError}</div> : null}
          <FormWizard
            activeStep={activeStep}
            aside={preview}
            busy={sending}
            cancelAction={<Link className="btn btn--ghost" to={`/billings/${billingUuid}/bills/${billUuid}`}>Cancelar</Link>}
            finalLabel={`Enviar ${commLabel}`}
            onBack={() => setActiveStep((current) => Math.max(0, current - 1))}
            onNext={continueWizard}
            onStepChange={setActiveStep}
            steps={COMMUNICATION_STEPS}
            visitedStep={visitedStep}
          >
            {activeStep === 0 ? (
              <div className="recipient-picker">{billing.recipients.map((recipient, index) => {
                const label = isFullContact(recipient) ? `${recipient.name} <${recipient.email}>` : "Destinatário protegido";
                return <label className="recipient-option" key={recipient.uuid}><input aria-describedby={index === 0 && fieldErrors.recipient_uuids ? "recipient_uuids-error" : undefined} aria-label={label} checked={selectedRecipients.includes(recipient.uuid)} onChange={(event) => setSelectedRecipients((current) => event.target.checked ? [...current, recipient.uuid] : current.filter((uuid) => uuid !== recipient.uuid))} ref={index === 0 ? recipientRef : undefined} type="checkbox" value={recipient.uuid} /><span aria-hidden="true"><strong>{label}</strong><small>{isFullContact(recipient) ? "Receberá um e-mail individual" : "Dados protegidos pela organização"}</small></span></label>;
              })}<FieldError id="recipient_uuids-error" message={fieldErrors.recipient_uuids} /></div>
            ) : null}

            {activeStep === 1 ? (
              <>
                <div className="field"><label className="field__label" htmlFor="subject">Assunto</label><input aria-describedby={fieldErrors.subject ? "subject-error" : undefined} className="input" id="subject" onChange={(event) => setSubject(limitApiCharacters(event.target.value, MAX_COMMUNICATION_SUBJECT_LENGTH))} ref={subjectRef} required value={subject} /><FieldError id="subject-error" message={fieldErrors.subject} /></div>
                <div className="field"><div className="field-label-row"><label className="field__label" htmlFor="body">Corpo (Markdown — HTML não é permitido)</label><span className={bodyBytes > MAX_COMMUNICATION_BODY_BYTES * 0.9 ? "byte-count byte-count--warning" : "byte-count"} id="body-byte-count">{bodyBytes} / 4096 bytes</span></div><textarea aria-describedby={["body-byte-count", fieldErrors.body ? "body-error" : ""].filter(Boolean).join(" ")} className="input" id="body" onChange={(event) => setBody(event.target.value)} ref={bodyRef} required rows={12} value={body} /><div aria-label="Variáveis da mensagem" className="variable-toolbar">{TEMPLATE_VARIABLES.map((variable) => <button aria-label={`Inserir ${variable.label}`} key={variable.value} onClick={() => insertVariable(variable.value)} onMouseDown={(event) => event.preventDefault()} type="button">{variable.label}</button>)}</div><FieldError id="body-error" message={fieldErrors.body} /></div>
              </>
            ) : null}

            {activeStep === 2 ? (
              <>
                <dl className="review-list">
                  <WizardReviewRow label="Destinatários" onEdit={() => setActiveStep(0)} value={`${selectedRecipients.length} ${selectedRecipients.length === 1 ? "destinatário" : "destinatários"}`} />
                  <WizardReviewRow label="Mensagem" onEdit={() => setActiveStep(1)} value={subject} />
                  <WizardReviewRow label="Documento" value={`${isRecibo ? "Recibo" : "Fatura"} em PDF`} />
                </dl>
                <div className="field review-save-scope"><label className="field__label" htmlFor="save_scope">Salvar esta mensagem como modelo?</label><select aria-describedby={fieldErrors.save_scope ? "save_scope-error" : undefined} aria-label="Salvar modelo" className="select" id="save_scope" onChange={(event) => setSaveScope(event.target.value as typeof saveScope)} ref={saveScopeRef} value={saveScope}><option value="">Não salvar como modelo</option><option value="billing">Salvar para esta cobrança</option>{billing.capabilities.can_edit && <option value="owner">Salvar para {billing.owner.type === "organization" ? "a organização" : "minha conta"}</option>}</select><FieldError id="save_scope-error" message={fieldErrors.save_scope} /></div>
              </>
            ) : null}
          </FormWizard>
        </form>
      )}
    </>
  );
}
