import { Building2, QrCode, ShieldCheck } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Link } from "react-router";

import { FieldError } from "../../components/FieldError";
import { FormWizard, WizardReviewRow, type WizardStep } from "../../components/FormWizard";
import { DirtyFormGuard } from "../../forms/useDirtyFormGuard";
import { PIX_KEY_GUIDANCE, PIX_MERCHANT_NAME_GUIDANCE } from "../../forms/pixGuidance";
import { validatePix, validateText } from "../../forms/validators";
import { shouldAutoFocus } from "../../lib/autofocus";
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
  const pendingServerFocus = useRef<(typeof FIELD_KEYS)[number] | null>(null);
  const createMode = mode === "create";
  const allFieldErrors = useMemo(
    () => ({ ...Object.fromEntries(Object.entries(fieldErrors).filter(([field]) => !ignoredServerFields.includes(field))), ...localFieldErrors }),
    [fieldErrors, ignoredServerFields, localFieldErrors]
  );

  useEffect(() => setIgnoredServerFields([]), [fieldErrors]);

  useEffect(() => {
    if (!error && !Object.keys(fieldErrors).length) return;
    const key = FIELD_KEYS.find((field) => fieldErrors[field]) ?? "name";
    if (createMode) {
      pendingServerFocus.current = key;
      const step = stepForField(key);
      setActiveStep(step);
      setVisitedStep((current) => Math.max(current, step));
    } else {
      refs.current[key]?.focus();
    }
  }, [createMode, error, fieldErrors]);

  useEffect(() => {
    const key = pendingServerFocus.current;
    if (!createMode || !key || stepForField(key) !== activeStep) return;
    pendingServerFocus.current = null;
    refs.current[key]?.focus();
  }, [activeStep, createMode]);

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
  const setPixTiming = (configureNow: boolean) => {
    setCustomPix(configureNow);
    setIsDirty(true);
    setLocalFieldErrors({});
    setIgnoredServerFields((current) => [...new Set([...current, "pix_key", "pix_merchant_name", "pix_merchant_city"])]);
  };
  const describedBy = (key: keyof OrganizationValues, hintId?: string) => [allFieldErrors[key] ? `${key}-error` : "", hintId ?? ""].filter(Boolean).join(" ") || undefined;
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
        requestAnimationFrame(() => refs.current[firstField]?.focus());
      } else {
        refs.current[firstField]?.focus();
      }
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
        <div className="organization-wizard__intro"><Building2 aria-hidden="true" size={24} /><div><strong>Comece pelo nome do espaço</strong><p>Use o nome que sua equipe reconhece. Convites e cobranças entram depois da criação.</p></div></div>
        <div className="field mb-0">
          <label className={labelClass} htmlFor="name">Nome da organização</label>
          <input aria-describedby={describedBy("name", "name-hint")} autoComplete="organization" autoFocus={shouldAutoFocus()} className={inputClass} id="name" name="name" onChange={(event) => update("name", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Ribeiro Imóveis…" ref={(element) => { refs.current.name = element; }} required type="text" value={form.name} />
          <FieldError id="name-error" message={allFieldErrors.name} />
          <span className="field__hint" id="name-hint">Você será o administrador inicial e poderá ajustar os acessos depois.</span>
        </div>
      </>
    );
    const pixStep = (
      <>
        <div className="organization-wizard__intro"><QrCode aria-hidden="true" size={24} /><div><strong>Decida quando ativar o PIX</strong><p>Ao configurar agora, as faturas da organização já saem com QR Code para pagamento.</p></div></div>
        <fieldset className="organization-pix-choice">
          <legend>Quando configurar o PIX</legend>
          <div className="organization-pix-choice__options">
            <label htmlFor="organization_pix_later">
              <input checked={!customPix} id="organization_pix_later" name="organization_pix_timing" onChange={() => setPixTiming(false)} type="radio" value="later" />
              <span><strong>Configurar depois</strong><small>Crie o espaço agora e ative o PIX antes da primeira fatura.</small></span>
            </label>
            <label htmlFor="organization_pix_now">
              <input checked={customPix} id="organization_pix_now" name="organization_pix_timing" onChange={() => setPixTiming(true)} type="radio" value="now" />
              <span><strong>Configurar agora</strong><small>Informe os dados que aparecerão no QR Code das faturas.</small></span>
            </label>
          </div>
        </fieldset>
        {customPix ? <div className="organization-pix-fields">
          <div className="field field--full"><label className={labelClass} htmlFor="pix_key">Chave PIX</label><input aria-describedby={describedBy("pix_key", "pix_key-hint")} autoComplete="off" className={`${inputClass} mono`} id="pix_key" name="pix_key" onChange={(event) => update("pix_key", limitApiCharacters(event.target.value, 320))} placeholder="E-mail, CPF/CNPJ, telefone com DDD ou chave aleatória…" ref={(element) => { refs.current.pix_key = element; }} spellCheck={false} type="text" value={form.pix_key} /><FieldError id="pix_key-error" message={allFieldErrors.pix_key} /><span className="field__hint" id="pix_key-hint">{PIX_KEY_GUIDANCE}</span></div>
          <div className="field"><label className={labelClass} htmlFor="pix_merchant_name">Nome do recebedor</label><input aria-describedby={describedBy("pix_merchant_name", "pix_merchant_name-hint")} autoComplete="off" className={inputClass} id="pix_merchant_name" name="pix_merchant_name" onChange={(event) => update("pix_merchant_name", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Ribeiro Imóveis…" ref={(element) => { refs.current.pix_merchant_name = element; }} spellCheck={false} type="text" value={form.pix_merchant_name} /><FieldError id="pix_merchant_name-error" message={allFieldErrors.pix_merchant_name} /><span className="field__hint" id="pix_merchant_name-hint">{PIX_MERCHANT_NAME_GUIDANCE}</span></div>
          <div className="field"><label className={labelClass} htmlFor="pix_merchant_city">Cidade do recebedor</label><input aria-describedby={describedBy("pix_merchant_city")} autoComplete="off" className={`${inputClass} mono`} id="pix_merchant_city" name="pix_merchant_city" onChange={(event) => update("pix_merchant_city", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: São Paulo…" ref={(element) => { refs.current.pix_merchant_city = element; }} spellCheck={false} type="text" value={form.pix_merchant_city} /><FieldError id="pix_merchant_city-error" message={allFieldErrors.pix_merchant_city} /></div>
        </div> : <div aria-live="polite" className="organization-pix-skip" role="status"><strong>PIX fica para depois.</strong><span>A organização será criada normalmente e esta configuração continuará disponível.</span></div>}
      </>
    );
    const reviewStep = (
      <>
        <dl className="review-list">
          <WizardReviewRow label="Nome da organização" onEdit={() => setActiveStep(0)} value={form.name || "Não informado"} />
          <WizardReviewRow label="Seu acesso" value="Administrador" />
          <WizardReviewRow label="Recebimento PIX" onEdit={() => setActiveStep(1)} value={customPix ? <>Configurado para <span className="mono">{form.pix_key}</span></> : "Configurar depois"} />
        </dl>
        <div className="organization-review-note">
          <ShieldCheck aria-hidden="true" size={22} />
          <div><strong>Acessos continuam sob seu controle</strong><p>Depois de criar, você poderá convidar a equipe e exigir autenticação em 2 etapas nas configurações de segurança.</p></div>
        </div>
      </>
    );
    const content = [identityStep, pixStep, reviewStep][activeStep];
    return (
      <form className="organization-create-form" id="organization-create-form" onSubmit={submit}>
        <DirtyFormGuard isDirty={isDirty && !saving} />
        {error ? <div className="toast toast--danger" role="alert">{error}</div> : null}
        <FormWizard activeStep={activeStep} busy={saving} busyLabel="Criando…" cancelAction={<Link className="btn btn--ghost" to={cancelUrl}>Cancelar</Link>} finalLabel="Criar organização" onBack={() => setActiveStep((current) => Math.max(0, current - 1))} onNext={continueWizard} onStepChange={setActiveStep} steps={ORGANIZATION_STEPS} visitedStep={visitedStep}>{content}</FormWizard>
      </form>
    );
  }

  return (
    <form aria-busy={saving} className="organization-edit-form" onSubmit={submit}>
      <DirtyFormGuard isDirty={isDirty && !saving} />
      {error ? <div className="toast toast--danger" role="alert">{error}</div> : null}
      <div className="panel">
        <div className="panel-head organization-edit-form__section-head">
          <div>
            <h2>Identificação</h2>
            <p>Este nome aparece para toda a equipe e organiza suas cobranças.</p>
          </div>
        </div>
        <div className="panel-body">
          <div className="field mb-0">
            <label className={labelClass} htmlFor="name">Nome da organização</label>
            <input aria-describedby={describedBy("name", "edit-name-hint")} autoComplete="organization" className={inputClass} id="name" name="name" onChange={(event) => update("name", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Ribeiro Gestão Patrimonial…" ref={(element) => { refs.current.name = element; }} required type="text" value={form.name} />
            <FieldError id="name-error" message={allFieldErrors.name} />
            <span className="field-hint" id="edit-name-hint">Use um nome curto e fácil de reconhecer no seletor.</span>
          </div>
        </div>
      </div>
      <div className="panel">
        <div className="panel-head organization-edit-form__section-head">
          <div>
            <h2>Recebimento PIX</h2>
            <p>Esses dados geram o QR Code das próximas faturas.</p>
          </div>
        </div>
        <div className="panel-body">
          <p className="field-hint mb-1">Preencha os 3 campos para ativar o PIX. Deixe todos vazios se preferir configurar depois.</p>
          <div className="field">
            <label className={labelClass} htmlFor="pix_key">Chave PIX</label>
            <input aria-describedby={describedBy("pix_key", "edit-pix-key-hint")} autoComplete="off" className={`${inputClass} mono`} id="pix_key" name="pix_key" onChange={(event) => update("pix_key", limitApiCharacters(event.target.value, 320))} placeholder="E-mail, CPF/CNPJ, telefone com DDD ou chave aleatória…" ref={(element) => { refs.current.pix_key = element; }} spellCheck={false} type="text" value={form.pix_key} />
            <FieldError id="pix_key-error" message={allFieldErrors.pix_key} />
            <span className="field-hint" id="edit-pix-key-hint">{PIX_KEY_GUIDANCE}</span>
          </div>
          <div className="field">
            <label className={labelClass} htmlFor="pix_merchant_name">Nome do recebedor</label>
            <input aria-describedby={describedBy("pix_merchant_name", "edit-pix-name-hint")} autoComplete="off" className={inputClass} id="pix_merchant_name" name="pix_merchant_name" onChange={(event) => update("pix_merchant_name", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Ribeiro Gestão…" ref={(element) => { refs.current.pix_merchant_name = element; }} spellCheck={false} type="text" value={form.pix_merchant_name} />
            <FieldError id="pix_merchant_name-error" message={allFieldErrors.pix_merchant_name} />
            <span className="field-hint" id="edit-pix-name-hint">{PIX_MERCHANT_NAME_GUIDANCE}</span>
          </div>
          <div className="field mb-0">
            <label className={labelClass} htmlFor="pix_merchant_city">Cidade do recebedor</label>
            <input aria-describedby={describedBy("pix_merchant_city")} autoComplete="off" className={`${inputClass} mono`} id="pix_merchant_city" name="pix_merchant_city" onChange={(event) => update("pix_merchant_city", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: São Paulo…" ref={(element) => { refs.current.pix_merchant_city = element; }} spellCheck={false} type="text" value={form.pix_merchant_city} />
            <FieldError id="pix_merchant_city-error" message={allFieldErrors.pix_merchant_city} />
          </div>
        </div>
      </div>
      <div className="btn-group">
        <button className="btn btn--primary" disabled={saving} type="submit">{saving ? "Salvando…" : "Salvar alterações"}</button>
        <Link className="btn btn--ghost" to={cancelUrl}>Cancelar</Link>
      </div>
    </form>
  );
}
