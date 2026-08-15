import { Building2 } from "lucide-react";
import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import { Link } from "react-router";

import { FieldError } from "../../components/FieldError";
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
  const [isDirty, setIsDirty] = useState(false);
  const refs = useRef<Record<string, HTMLInputElement | null>>({});
  const createMode = mode === "create";
  const allFieldErrors = useMemo(
    () => ({ ...fieldErrors, ...localFieldErrors }),
    [fieldErrors, localFieldErrors]
  );

  useEffect(() => {
    if (!error && !Object.keys(allFieldErrors).length) return;
    const key = FIELD_KEYS.find((field) => allFieldErrors[field]) ?? "name";
    refs.current[key]?.focus();
  }, [allFieldErrors, error]);

  const update = (key: keyof OrganizationValues, value: string) => {
    setForm((current) => ({ ...current, [key]: value }));
    setIsDirty(true);
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

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const errors: Record<string, string> = {};
    const name = validateText(form.name, { maxLength: 255, required: true });
    if ("error" in name) errors.name = name.error;
    const pix = validatePix({ city: form.pix_merchant_city, key: form.pix_key, name: form.pix_merchant_name });
    if ("errors" in pix) {
      const pixFields = { city: "pix_merchant_city", key: "pix_key", name: "pix_merchant_name" } as const;
      Object.entries(pix.errors).forEach(([key, message]) => { errors[pixFields[key as keyof typeof pixFields]] = message; });
    }
    if (Object.keys(errors).length) {
      setLocalFieldErrors(errors);
      const firstField = FIELD_KEYS.find((field) => errors[field]) as keyof OrganizationValues;
      requestAnimationFrame(() => refs.current[firstField]?.focus());
      return;
    }
    setLocalFieldErrors({});
    const validName = name as { value: string };
    const validPix = pix as { value: { city: string; key: string; name: string } };
    onSubmit({
      ...form,
      name: validName.value,
      pix_key: validPix.value.key,
      pix_merchant_city: validPix.value.city,
      pix_merchant_name: validPix.value.name
    });
  };

  if (createMode) {
    return (
      <form onSubmit={submit}>
        <DirtyFormGuard isDirty={isDirty && !saving} />
        {error ? <div className="toast toast--danger" role="alert">{error}</div> : null}
        <div className="panel">
          <div className="panel__head"><h3>Detalhes</h3><Building2 aria-hidden="true" size={18} /></div>
          <div className="panel__body">
            <div className="field mb-0">
              <label className={labelClass} htmlFor="name">Nome da organização</label>
              <input
                aria-describedby={describedBy("name")}
                autoFocus
                className={inputClass}
                id="name"
                onChange={(event) => update("name", limitApiCharacters(event.target.value, 255))}
                placeholder="Ex.: Ribeiro Imóveis"
                ref={(element) => { refs.current.name = element; }}
                required
                type="text"
                value={form.name}
              />
              <FieldError id="name-error" message={allFieldErrors.name} />
              <span className="field__hint">Você será o administrador. Poderá convidar membros depois.</span>
            </div>
          </div>
        </div>
        <div className="panel">
          <div className="panel__head"><h3>Dados do PIX</h3></div>
          <div className="panel__body">
            <p className="field__hint mb-1">Opcional. Preencha os três campos para gerar QR Codes nas cobranças desta organização.</p>
            <div className="field">
              <label className={labelClass} htmlFor="pix_key">Chave PIX</label>
              <input aria-describedby={describedBy("pix_key")} className={inputClass} id="pix_key" onChange={(event) => update("pix_key", event.target.value)} ref={(element) => { refs.current.pix_key = element; }} type="text" value={form.pix_key} />
              <FieldError id="pix_key-error" message={allFieldErrors.pix_key} />
            </div>
            <div className="field">
              <label className={labelClass} htmlFor="pix_merchant_name">Nome do recebedor</label>
              <input aria-describedby={describedBy("pix_merchant_name")} className={inputClass} id="pix_merchant_name" onChange={(event) => update("pix_merchant_name", limitApiCharacters(event.target.value, 25))} ref={(element) => { refs.current.pix_merchant_name = element; }} type="text" value={form.pix_merchant_name} />
              <FieldError id="pix_merchant_name-error" message={allFieldErrors.pix_merchant_name} />
              <span className="field__hint">Até 25 caracteres.</span>
            </div>
            <div className="field mb-0">
              <label className={labelClass} htmlFor="pix_merchant_city">Cidade do recebedor</label>
              <input aria-describedby={describedBy("pix_merchant_city")} className={inputClass} id="pix_merchant_city" onChange={(event) => update("pix_merchant_city", limitApiCharacters(event.target.value, 15))} ref={(element) => { refs.current.pix_merchant_city = element; }} type="text" value={form.pix_merchant_city} />
              <FieldError id="pix_merchant_city-error" message={allFieldErrors.pix_merchant_city} />
              <span className="field__hint">Até 15 caracteres, sem acentos.</span>
            </div>
          </div>
        </div>
        <div className="actionbar">
          <span className="muted" style={{ fontSize: "0.85rem" }}>Você entra como <strong style={{ color: "var(--ink)" }}>Admin</strong>.</span>
          <div className="btn-row">
            <Link className="btn btn--ghost" to={cancelUrl}>Cancelar</Link>
            <button className="btn btn--primary" disabled={saving} type="submit">
              {saving ? "Criando..." : "Criar organização"}
            </button>
          </div>
        </div>
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
