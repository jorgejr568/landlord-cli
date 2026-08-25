import { Building2, QrCode } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Link } from "react-router";

import { FieldError } from "../../components/FieldError";
import { FormWizard, WizardReviewRow, type WizardStep } from "../../components/FormWizard";
import { DirtyFormGuard } from "../../forms/useDirtyFormGuard";
import { validatePix, validateText } from "../../forms/validators";
import { limitApiCharacters } from "../../lib/textLimits";

export interface OrganizationValues {
  name: string;
  pix_key: string;
  pix_merchant_city: string;
  pix_merchant_name: string;
}

interface OrganizationFormProps {
  error: string;
  fieldErrors: Record<string, string>;
  mode: "create" | "edit";
  onSubmit: (values: OrganizationValues) => void;
  organizationUuid?: string;
  saving: boolean;
  values: OrganizationValues;
}

const FIELD_KEYS = ["name", "pix_key", "pix_merchant_name", "pix_merchant_city"] as const;
const ORGANIZATION_STEPS: WizardStep[] = [
  { description: "Dê um nome claro para o espaço da sua equipe.", id: "identity", label: "Identidade" },
  { description: "Configure o recebimento agora ou deixe para depois.", id: "pix", label: "Recebimento PIX" },
  { description: "Confira como a organização será criada.", id: "review", label: "Revisão" }
];

function stepForField(field: string): number {
  return field.startsWith("pix_") ? 1 : 0;
}

export function OrganizationForm({
  error,
  fieldErrors,
  mode,
  onSubmit,
  organizationUuid = "",
  saving,
  values
}: OrganizationFormProps) {
  const [form, setForm] = useState(values);
  const [localFieldErrors, setLocalFieldErrors] = useState<Record<string, string>>({});
  const [ignoredServerFields, setIgnoredServerFields] = useState<string[]>([]);
  const [isDirty, setIsDirty] = useState(false);
  const [activeStep, setActiveStep] = useState(0);
  const [visitedStep, setVisitedStep] = useState(0);
  const [customPix, setCustomPix] = useState(Boolean(values.pix_key || values.pix_merchant_name || values.pix_merchant_city));
  const refs = useRef<Record<string, HTMLInputElement | null>>({});
  const createMode = mode === "create";
  const allFieldErrors = useMemo(
    () => ({ ...Object.fromEntries(Object.entries(fieldErrors).filter(([field]) => !ignoredServerFields.includes(field))), ...localFieldErrors }),
    [fieldErrors, ignoredServerFields, localFieldErrors]
  );

  useEffect(() => setIgnoredServerFields([]), [fieldErrors]);

  useEffect(() => {
    if (!error && !Object.keys(allFieldErrors).length) return;
    const key = FIELD_KEYS.find((field) => allFieldErrors[field]) ?? "name";
    if (createMode) {
      const step = stepForField(key);
      setActiveStep(step);
      setVisitedStep((current) => Math.max(current, step));
    }
    refs.current[key]?.focus();
  }, [activeStep, allFieldErrors, createMode, error]);

  const update = (key: keyof OrganizationValues, value: string) => {
    setForm((current) => ({ ...current, [key]: value }));
    setIsDirty(true);
    setIgnoredServerFields((current) => current.includes(key) ? current : [...current, key]);
    setLocalFieldErrors((current) => {
      const remaining = { ...current };
      delete remaining[key];
      return remaining;
    });
  };
  const describedBy = (key: keyof OrganizationValues) => allFieldErrors[key] ? `${key}-error` : undefined;
  const inputClass = createMode ? "input" : "field-input";
  const labelClass = createMode ? "field__label" : "field-label";
  const cancelUrl = createMode ? "/organizations/" : `/organizations/${organizationUuid}`;

  const validateNameField = (): { errors: Record<string, string>; value: string } => {
    const result = validateText(form.name, { maxLength: 255, required: true });
    return "error" in result ? { errors: { name: result.error }, value: form.name } : { errors: {}, value: result.value };
  };
  const validatePixFields = (): { errors: Record<string, string>; value: { city: string; key: string; name: string } } => {
    if (createMode && !customPix) return { errors: {}, value: { city: "", key: "", name: "" } };
    const result = validatePix({ city: form.pix_merchant_city, key: form.pix_key, name: form.pix_merchant_name });
    if (createMode && customPix && "value" in result && !result.value.city && !result.value.key && !result.value.name) {
      return { errors: { pix_key: "Informe a chave PIX.", pix_merchant_city: "Informe a cidade do recebedor.", pix_merchant_name: "Informe o nome do recebedor." }, value: result.value };
    }
    if ("errors" in result) {
      const errors: Record<string, string> = {};
      const pixFields = { city: "pix_merchant_city", key: "pix_key", name: "pix_merchant_name" } as const;
      Object.entries(result.errors).forEach(([key, message]) => { errors[pixFields[key as keyof typeof pixFields]] = message; });
      return { errors, value: { city: form.pix_merchant_city, key: form.pix_key, name: form.pix_merchant_name } };
    }
    return { errors: {}, value: result.value };
  };

  const focusFirstError = (errors: Record<string, string>) => {
    const firstField = FIELD_KEYS.find((field) => errors[field]);
    /* v8 ignore next -- validators only return keys from FIELD_KEYS */
    if (!firstField) return;
    refs.current[firstField]?.focus();
  };

  const continueWizard = () => {
    const validation = activeStep === 0 ? validateNameField() : validatePixFields();
    setLocalFieldErrors(validation.errors);
    if (Object.keys(validation.errors).length) {
      focusFirstError(validation.errors);
      return;
    }
    const completedFields = activeStep === 0 ? ["name"] : ["pix_key", "pix_merchant_name", "pix_merchant_city"];
    setIgnoredServerFields((current) => [...new Set([...current, ...completedFields])]);
    const next = Math.min(activeStep + 1, ORGANIZATION_STEPS.length - 1);
    setVisitedStep((current) => Math.max(current, next));
    setActiveStep(next);
  };

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const name = validateNameField();
    const pix = validatePixFields();
    const errors = { ...name.errors, ...pix.errors };
    if (Object.keys(errors).length) {
      setLocalFieldErrors(errors);
      const firstField = FIELD_KEYS.find((field) => errors[field]) as keyof OrganizationValues;
      if (createMode) {
        const step = stepForField(firstField);
        setActiveStep(step);
        setVisitedStep((current) => Math.max(current, step));
      }
      requestAnimationFrame(() => refs.current[firstField]?.focus());
      return;
    }
    setLocalFieldErrors({});
    onSubmit({
      ...form,
      name: name.value,
      pix_key: pix.value.key,
      pix_merchant_city: pix.value.city,
      pix_merchant_name: pix.value.name
    });
  };

  if (createMode) {
    const identityStep = (
      <>
        <div className="organization-wizard__intro"><Building2 aria-hidden="true" size={24} /><div><strong>O espaço da sua equipe</strong><p>Use um nome que todos reconheçam. Você poderá convidar membros e criar cobranças logo depois.</p></div></div>
        <div className="field mb-0">
          <label className={labelClass} htmlFor="name">Nome da organização</label>
          <input aria-describedby={describedBy("name")} autoFocus className={inputClass} id="name" name="name" onChange={(event) => update("name", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Ribeiro Imóveis" ref={(element) => { refs.current.name = element; }} required type="text" value={form.name} />
          <FieldError id="name-error" message={allFieldErrors.name} />
          <span className="field__hint">Você entra como administrador e poderá ajustar a equipe depois.</span>
        </div>
      </>
    );
    const pixStep = (
      <>
        <div className="organization-wizard__intro"><QrCode aria-hidden="true" size={24} /><div><strong>Receba por PIX nas cobranças</strong><p>Esses dados geram o QR Code das faturas emitidas pela organização.</p></div></div>
        <label className="organization-pix-choice" htmlFor="organization_custom_pix">
          <input aria-label="Configurar PIX agora" checked={customPix} id="organization_custom_pix" name="organization_custom_pix" onChange={(event) => { setCustomPix(event.target.checked); setIsDirty(true); setLocalFieldErrors({}); }} type="checkbox" />
          <span><strong>Configurar PIX agora</strong><small>Você também pode pular e configurar quando estiver pronto para emitir a primeira fatura.</small></span>
        </label>
        {customPix ? <div className="organization-pix-fields">
          <div className="field field--full"><label className={labelClass} htmlFor="pix_key">Chave PIX</label><input aria-describedby={describedBy("pix_key")} className={`${inputClass} mono`} id="pix_key" name="pix_key" onChange={(event) => update("pix_key", event.target.value)} placeholder="e-mail, CPF/CNPJ, telefone (+55) ou aleatória" ref={(element) => { refs.current.pix_key = element; }} type="text" value={form.pix_key} /><FieldError id="pix_key-error" message={allFieldErrors.pix_key} /></div>
          <div className="field"><label className={labelClass} htmlFor="pix_merchant_name">Nome do recebedor</label><input aria-describedby={describedBy("pix_merchant_name")} className={inputClass} id="pix_merchant_name" name="pix_merchant_name" onChange={(event) => update("pix_merchant_name", limitApiCharacters(event.target.value, 25))} placeholder="Até 25 caracteres" ref={(element) => { refs.current.pix_merchant_name = element; }} type="text" value={form.pix_merchant_name} /><FieldError id="pix_merchant_name-error" message={allFieldErrors.pix_merchant_name} /></div>
          <div className="field"><label className={labelClass} htmlFor="pix_merchant_city">Cidade do recebedor</label><input aria-describedby={describedBy("pix_merchant_city")} className={`${inputClass} mono`} id="pix_merchant_city" name="pix_merchant_city" onChange={(event) => update("pix_merchant_city", limitApiCharacters(event.target.value, 15))} placeholder="SEM ACENTOS" ref={(element) => { refs.current.pix_merchant_city = element; }} type="text" value={form.pix_merchant_city} /><FieldError id="pix_merchant_city-error" message={allFieldErrors.pix_merchant_city} /></div>
        </div> : <div className="organization-pix-skip" role="status"><strong>Sem problema.</strong><span>A organização será criada sem PIX e você poderá completar isso depois.</span></div>}
      </>
    );
    const reviewStep = (
      <dl className="review-list">
        <WizardReviewRow label="Nome da organização" onEdit={() => setActiveStep(0)} value={form.name || "Não informado"} />
        <WizardReviewRow label="Seu papel" value="Admin" />
        <WizardReviewRow label="Recebimento PIX" onEdit={() => setActiveStep(1)} value={customPix ? <>PIX configurado · <span className="mono">{form.pix_key}</span></> : "Configurar depois"} />
      </dl>
    );
    const content = [identityStep, pixStep, reviewStep][activeStep];
    return (
      <form id="organization-create-form" onSubmit={submit}>
        <DirtyFormGuard isDirty={isDirty && !saving} />
        {error ? <div className="toast toast--danger" role="alert">{error}</div> : null}
        <FormWizard activeStep={activeStep} busy={saving} cancelAction={<Link className="btn btn--ghost" to={cancelUrl}>Cancelar</Link>} finalLabel="Criar organização" onBack={() => setActiveStep((current) => Math.max(0, current - 1))} onNext={continueWizard} onStepChange={setActiveStep} steps={ORGANIZATION_STEPS} visitedStep={visitedStep}>{content}</FormWizard>
      </form>
    );
  }

  return (
    <form onSubmit={submit}>
      <DirtyFormGuard isDirty={isDirty && !saving} />
      {error ? <div className="toast toast--danger" role="alert">{error}</div> : null}
      <div className="panel">
        <div className="panel-body">
          <div className="field mb-0">
            <label className={labelClass} htmlFor="name">Nome</label>
            <input aria-describedby={describedBy("name")} className={inputClass} id="name" onChange={(event) => update("name", limitApiCharacters(event.target.value, 255))} ref={(element) => { refs.current.name = element; }} required type="text" value={form.name} />
            <FieldError id="name-error" message={allFieldErrors.name} />
          </div>
        </div>
      </div>
      <div className="panel">
        <div className="panel-head"><h5>Dados do PIX</h5></div>
        <div className="panel-body">
          <p className="field-hint mb-1">Estes dados são usados para gerar o QR Code nas faturas das cobranças desta organização. Todos os três campos são obrigatórios para gerar faturas.</p>
          <div className="field">
            <label className={labelClass} htmlFor="pix_key">Chave PIX</label>
            <input aria-describedby={describedBy("pix_key")} className={inputClass} id="pix_key" onChange={(event) => update("pix_key", event.target.value)} ref={(element) => { refs.current.pix_key = element; }} type="text" value={form.pix_key} />
            <FieldError id="pix_key-error" message={allFieldErrors.pix_key} />
            <span className="field-hint">Para celular, inclua +55 (caso contrário 11 dígitos são tratados como CPF).</span>
          </div>
          <div className="field">
            <label className={labelClass} htmlFor="pix_merchant_name">Nome do recebedor</label>
            <input aria-describedby={describedBy("pix_merchant_name")} className={inputClass} id="pix_merchant_name" onChange={(event) => update("pix_merchant_name", limitApiCharacters(event.target.value, 25))} ref={(element) => { refs.current.pix_merchant_name = element; }} type="text" value={form.pix_merchant_name} />
            <FieldError id="pix_merchant_name-error" message={allFieldErrors.pix_merchant_name} />
            <span className="field-hint">Até 25 caracteres.</span>
          </div>
          <div className="field mb-0">
            <label className={labelClass} htmlFor="pix_merchant_city">Cidade do recebedor</label>
            <input aria-describedby={describedBy("pix_merchant_city")} className={inputClass} id="pix_merchant_city" onChange={(event) => update("pix_merchant_city", limitApiCharacters(event.target.value, 15))} ref={(element) => { refs.current.pix_merchant_city = element; }} type="text" value={form.pix_merchant_city} />
            <FieldError id="pix_merchant_city-error" message={allFieldErrors.pix_merchant_city} />
            <span className="field-hint">Até 15 caracteres, sem acentos.</span>
          </div>
        </div>
      </div>
      <div className="btn-group">
        <button className="btn btn--primary" disabled={saving} type="submit">{saving ? "Salvando..." : "Salvar"}</button>
        <Link className="btn btn--ghost" to={cancelUrl}>Cancelar</Link>
      </div>
    </form>
  );
}
