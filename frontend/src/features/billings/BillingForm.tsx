import { QrCode, Trash2 } from "lucide-react";
import { type FormEvent, useEffect, useMemo, useState } from "react";
import { Link } from "react-router";

import { FieldError } from "../../components/FieldError";
import { DirtyFormGuard } from "../../forms/useDirtyFormGuard";
import { validateContacts, validateMoney, validatePix, validateText } from "../../forms/validators";
import { formatBrl, MAX_PERSISTED_CENTAVOS, parseBrl } from "../../lib/format";
import type { components } from "../../lib/api/schema";
import { limitApiCharacters } from "../../lib/textLimits";
import { RecipientFormset, type ContactValue } from "./RecipientFormset";

type Organization = components["schemas"]["OrganizationResponse"];

export interface BillingItemValue {
  amount: string;
  description: string;
  id: string;
  itemType: "fixed" | "variable";
  uuid?: string;
}

export interface BillingFormValues {
  description: string;
  items: BillingItemValue[];
  name: string;
  ownerType: "user" | "organization";
  ownerUuid: string;
  pixKey: string;
  pixMerchantCity: string;
  pixMerchantName: string;
  recipients: ContactValue[];
  replyTo: ContactValue[];
}

interface BillingFormProps {
  cancelTo?: string;
  error: string;
  fieldErrors: Record<string, string>;
  mode: "create" | "edit";
  ownerName?: string | null;
  lockedContacts?: { recipients: boolean; replyTo: boolean };
  onSubmit: (values: BillingFormValues) => void;
  organizations: Organization[];
  saving: boolean;
  values: BillingFormValues;
}

let itemSequence = 0;

function newItem(description = "", amount = "", itemType: "fixed" | "variable" = "fixed"): BillingItemValue {
  itemSequence += 1;
  return { amount, description, id: `billing-item-${itemSequence}`, itemType };
}

function controlNameFor(field: string): string {
  const itemMatch = /^items\.(\d+)\.(description|item_type|amount|uuid)$/.exec(field);
  if (itemMatch) return itemMatch[2] === "uuid" ? `items-${itemMatch[1]}-description` : `items-${itemMatch[1]}-${itemMatch[2]}`;
  const contactMatch = /^(recipients|reply_to)\.(\d+)\.(name|email)$/.exec(field);
  if (contactMatch) return `${contactMatch[1]}-${contactMatch[2]}-${contactMatch[3]}`;
  const names: Record<string, string> = {
    description: "description",
    name: "name",
    owner: "owner",
    pix_key: "pix_key",
    pix_merchant_city: "pix_merchant_city",
    pix_merchant_name: "pix_merchant_name"
  };
  return names[field] ?? field;
}

export function BillingForm({ cancelTo, error, fieldErrors, lockedContacts, mode, onSubmit, organizations, ownerName, saving, values }: BillingFormProps) {
  const [form, setForm] = useState(values);
  const [localFieldErrors, setLocalFieldErrors] = useState<Record<string, string>>({});
  const [isDirty, setIsDirty] = useState(false);
  const [customPix, setCustomPix] = useState(Boolean(values.pixKey || values.pixMerchantName || values.pixMerchantCity));
  const allFieldErrors = useMemo(
    () => ({ ...fieldErrors, ...localFieldErrors }),
    [fieldErrors, localFieldErrors]
  );
  const showCustomPix = customPix || Boolean(allFieldErrors.pix_key || allFieldErrors.pix_merchant_name || allFieldErrors.pix_merchant_city);
  const allowedOrganizations = organizations.filter((organization) => organization.capabilities.can_create_billing);
  const fixedSubtotal = useMemo(() => {
    let total = 0;
    for (const item of form.items) {
      if (item.itemType === "variable") continue;
      total += parseBrl(item.amount) ?? 0;
    }
    return total;
  }, [form.items]);

  useEffect(() => {
    const fields = Object.keys(allFieldErrors);
    const firstField = Object.keys(localFieldErrors)[0] ?? ["name", "description", "owner", "pix_key", "pix_merchant_name", "pix_merchant_city"]
      .find((field) => fields.includes(field)) ?? fields[0];
    if (!firstField) return;
    const control = firstField === "items"
      ? (localFieldErrors.items
        ? document.querySelector<HTMLElement>('[name$="-amount"]')
        : null) ?? document.querySelector<HTMLElement>('[name="items-0-description"]') ?? document.querySelector<HTMLElement>('[name="items-add"]')
      : document.querySelector<HTMLElement>(`[name="${controlNameFor(firstField)}"]`);
    control?.focus();
  }, [allFieldErrors, localFieldErrors]);

  useEffect(() => {
    if (error) document.querySelector<HTMLElement>('[name="name"]')?.focus();
  }, [error]);

  const setField = <K extends keyof BillingFormValues>(field: K, value: BillingFormValues[K]) => {
    setIsDirty(true);
    setForm((current) => ({ ...current, [field]: value }));
  };
  const updateItem = (index: number, changes: Partial<BillingItemValue>) => {
    setIsDirty(true);
    setForm((current) => ({
      ...current,
      items: current.items.map((item, currentIndex) => currentIndex === index ? { ...item, ...changes } : item)
    }));
  };
  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const errors: Record<string, string> = {};
    const name = validateText(form.name, { maxLength: 255, required: true });
    const description = validateText(form.description, { maxLength: 2000 });
    if ("error" in name) errors.name = name.error;
    if ("error" in description) errors.description = description.error;
    const items = form.items.map((item, index) => {
      const itemDescription = validateText(item.description, { maxLength: 255, required: true });
      if ("error" in itemDescription) errors[`items.${index}.description`] = itemDescription.error;
      if (item.itemType === "fixed") {
        const amount = validateMoney(item.amount.trim() ? item.amount : "0,00");
        if ("error" in amount) errors[`items.${index}.amount`] = amount.error;
      }
      return { ...item, description: "value" in itemDescription ? itemDescription.value : item.description };
    });
    const fixedTotal = items.reduce((total, item) => total + (item.itemType === "fixed" ? (parseBrl(item.amount) ?? 0) : 0), 0);
    if (fixedTotal > MAX_PERSISTED_CENTAVOS) errors.items = "O valor total deve ser de no máximo R$ 21.474.836,47.";
    const pix = customPix ? validatePix({ city: form.pixMerchantCity, key: form.pixKey, name: form.pixMerchantName }) : { value: { city: "", key: "", name: "" } };
    if ("errors" in pix) {
      const pixFields = { city: "pix_merchant_city", key: "pix_key", name: "pix_merchant_name" } as const;
      Object.entries(pix.errors).forEach(([key, message]) => { errors[pixFields[key as keyof typeof pixFields]] = message; });
    }
    const recipients = lockedContacts?.recipients ? { value: form.recipients } : validateContacts(form.recipients);
    const replyTo = lockedContacts?.replyTo ? { value: form.replyTo } : validateContacts(form.replyTo);
    if ("errors" in recipients) Object.entries(recipients.errors).forEach(([key, message]) => { errors[`recipients.${key}`] = message; });
    if ("errors" in replyTo) Object.entries(replyTo.errors).forEach(([key, message]) => { errors[`reply_to.${key}`] = message; });
    if (Object.keys(errors).length) {
      setLocalFieldErrors(errors);
      requestAnimationFrame(() => {
        const firstField = Object.keys(errors)[0];
        const totalErrorIndex = firstField === "items"
          ? form.items.findIndex((item) => item.itemType === "fixed")
          : -1;
        const control = totalErrorIndex >= 0
          ? document.querySelector<HTMLElement>(`[name="items-${totalErrorIndex}-amount"]`)
          : document.querySelector<HTMLElement>(`[name="${controlNameFor(firstField)}"]`);
        control?.focus();
      });
      return;
    }
    setLocalFieldErrors({});
    const validName = name as { value: string };
    const validDescription = description as { value: string };
    const validPix = pix as { value: { city: string; key: string; name: string } };
    const validRecipients = recipients as { value: Array<{ email: string; name: string }> };
    const validReplyTo = replyTo as { value: Array<{ email: string; name: string }> };
    const normalizedContacts = (contacts: ContactValue[], validated: { value: Array<{ email: string; name: string }> }) => {
      const populated = contacts.filter((contact) => contact.name.trim());
      return validated.value.map((contact, index) => ({ ...populated[index], ...contact }));
    };
    onSubmit({
      ...form,
      description: validDescription.value,
      items,
      name: validName.value,
      pixKey: validPix.value.key,
      pixMerchantCity: validPix.value.city,
      pixMerchantName: validPix.value.name,
      recipients: normalizedContacts(form.recipients, validRecipients),
      replyTo: normalizedContacts(form.replyTo, validReplyTo)
    });
  };

  return (
    <form id="billing-form" onSubmit={submit}>
      <DirtyFormGuard isDirty={isDirty && !saving} />
      {error ? <div className="toast toast--error" role="alert">{error}</div> : null}
      <div className="panel">
        <div className="panel__head"><h3>Detalhes</h3><span className="panel__title-eyebrow">Obrigatório</span></div>
        <div className="panel__body">
          {mode === "create" ? (
            <div className="field field--full">
              <label className="field__label" htmlFor="owner">Proprietário</label>
              <select
                className="select"
                id="owner"
                name="owner"
                onChange={(event) => {
                  setIsDirty(true);
                  setForm((current) => ({
                    ...current,
                    ownerType: event.target.value ? "organization" : "user",
                    ownerUuid: event.target.value
                  }));
                }}
                value={form.ownerType === "organization" ? form.ownerUuid : ""}
              >
                <option value="">Minha conta</option>
                {allowedOrganizations.map((organization) => <option key={organization.uuid} value={organization.uuid}>{organization.name}</option>)}
              </select>
              <FieldError id="owner-error" message={fieldErrors.owner} />
            </div>
          ) : null}
          {mode === "edit" && form.ownerType === "organization" ? (
            <div className="field field--full">
              <label className="field__label" htmlFor="owner">Proprietário</label>
              <input className="input" disabled id="owner" name="owner" type="text" value={ownerName ?? "Organização"} />
              <span className="field__hint">Cobranças de organização não podem ser transferidas para outro proprietário.</span>
            </div>
          ) : null}
          <div className="form-grid">
            <div className="field field--full">
              <label className="field__label" htmlFor="name">Nome do imóvel</label>
              <input aria-describedby={allFieldErrors.name ? "name-error" : undefined} autoFocus className="input" id="name" name="name" onChange={(event) => setField("name", limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Apartamento 302 — Ed. Aurora" required type="text" value={form.name} />
              <FieldError id="name-error" message={allFieldErrors.name} />
            </div>
            <div className="field field--full">
              <label className="field__label" htmlFor="description">Descrição</label>
              <input aria-describedby={allFieldErrors.description ? "description-error" : undefined} className="input" id="description" name="description" onChange={(event) => setField("description", limitApiCharacters(event.target.value, 2000))} placeholder="Inquilino, endereço ou nota interna" type="text" value={form.description} />
              <FieldError id="description-error" message={allFieldErrors.description} />
            </div>
          </div>
        </div>
      </div>

      <div className="panel">
        <div className="panel__head">
          <div><h3>Recebimento PIX</h3><p className="panel__desc">Opcional — em branco usa a chave configurada na sua conta ou organização.</p></div>
          <QrCode aria-hidden="true" size={20} />
        </div>
        <div className="panel__body">
          <div className="field">
            <label className="field__label" htmlFor="use_custom_pix"><input checked={customPix} id="use_custom_pix" name="use_custom_pix" onChange={(event) => { setCustomPix(event.target.checked); setIsDirty(true); }} type="checkbox" /> Usar PIX personalizado</label>
            <span className="field__hint">Desmarcado, este imóvel usa o PIX configurado no proprietário.</span>
          </div>
          {showCustomPix ? <>
          <div className="field">
            <label className="field__label" htmlFor="pix_key">Chave PIX</label>
            <input aria-describedby="pix-key-hint pix-key-error" className="input mono" id="pix_key" name="pix_key" onChange={(event) => setField("pixKey", event.target.value)} placeholder="e-mail, CPF/CNPJ, telefone (+55) ou aleatória" type="text" value={form.pixKey} />
            <span className="field__hint" id="pix-key-hint">Para celular inclua +55, caso contrário 11 dígitos são tratados como CPF.</span>
            <FieldError id="pix-key-error" message={allFieldErrors.pix_key} />
          </div>
          <div className="form-grid">
            <div className="field">
              <label className="field__label" htmlFor="pix_merchant_name">Nome do recebedor</label>
              <input aria-describedby={allFieldErrors.pix_merchant_name ? "pix-name-error" : undefined} className="input" id="pix_merchant_name" name="pix_merchant_name" onChange={(event) => setField("pixMerchantName", limitApiCharacters(event.target.value, 25))} placeholder="Até 25 caracteres" type="text" value={form.pixMerchantName} />
              <span className="field__hint">Até 25 caracteres.</span>
              <FieldError id="pix-name-error" message={allFieldErrors.pix_merchant_name} />
            </div>
            <div className="field">
              <label className="field__label" htmlFor="pix_merchant_city">Cidade do recebedor</label>
              <input aria-describedby={allFieldErrors.pix_merchant_city ? "pix-city-error" : undefined} className="input mono" id="pix_merchant_city" name="pix_merchant_city" onChange={(event) => setField("pixMerchantCity", limitApiCharacters(event.target.value, 15))} placeholder="SEM ACENTOS" type="text" value={form.pixMerchantCity} />
              <span className="field__hint">Até 15 caracteres, sem acentos.</span>
              <FieldError id="pix-city-error" message={allFieldErrors.pix_merchant_city} />
            </div>
          </div>
          </> : <div className="toast toast--warning" role="status">PIX herdado do proprietário.</div>}
        </div>
      </div>

      <RecipientFormset fieldErrors={allFieldErrors} kind="recipients" locked={lockedContacts?.recipients} onChange={(contacts) => setField("recipients", contacts)} values={form.recipients} />
      <RecipientFormset fieldErrors={allFieldErrors} kind="reply_to" locked={lockedContacts?.replyTo} onChange={(contacts) => setField("replyTo", contacts)} values={form.replyTo} />

      <div className="panel">
        <div className="panel__head">
          <div><h3>Itens da cobrança</h3><p className="panel__desc">Fixos têm valor definido. Variáveis (água, luz) você preenche a cada fatura.</p></div>
          <button aria-label="Adicionar item" className="btn btn--sm btn--primary" name="items-add" onClick={() => setField("items", [...form.items, newItem()])} type="button">+ Adicionar <span className="sr-only">item</span></button>
        </div>
        <div className="panel__body">
          <FieldError id="items-error" message={allFieldErrors.items} />
          <input id="id_items-TOTAL_FORMS" name="items-TOTAL_FORMS" type="hidden" value={form.items.length} />
          <div id="items-container">
            {form.items.map((item, index) => {
              const descriptionError = allFieldErrors[`items.${index}.description`];
              const uuidError = allFieldErrors[`items.${index}.uuid`];
              const typeError = allFieldErrors[`items.${index}.item_type`];
              const amountError = allFieldErrors[`items.${index}.amount`];
              return (
                <div className="formset-row" id={`items-row-${index}`} key={item.id}>
                  <div className={`item-grid${item.itemType === "variable" ? " item-grid--variable" : ""}`}>
                    <div className="field mb-0">
                      <label className="field__label" htmlFor={`${item.id}-description`}>Descrição</label>
                      <input aria-describedby={[descriptionError ? `${item.id}-description-error` : "", uuidError ? `${item.id}-uuid-error` : "", index === 0 && allFieldErrors.items ? "items-error" : ""].filter(Boolean).join(" ") || undefined} aria-label={`Descrição do item ${index + 1}`} className="input" id={`${item.id}-description`} name={`items-${index}-description`} onChange={(event) => updateItem(index, { description: limitApiCharacters(event.target.value, 255) })} placeholder={index === 0 ? "Ex.: Aluguel" : "Ex.: Condomínio"} required type="text" value={item.description} />
                      <FieldError id={`${item.id}-description-error`} message={descriptionError} />
                      <FieldError id={`${item.id}-uuid-error`} message={uuidError} />
                    </div>
                    <div className="field mb-0">
                      <label className="field__label" htmlFor={`${item.id}-type`}>Tipo</label>
                      <select aria-label={`Tipo do item ${index + 1}`} className="select" id={`${item.id}-type`} name={`items-${index}-item_type`} onChange={(event) => updateItem(index, { amount: event.target.value === "variable" ? "" : item.amount, itemType: event.target.value as BillingItemValue["itemType"] })} value={item.itemType}>
                        <option value="fixed">Fixo</option><option value="variable">Variável</option>
                      </select>
                      <FieldError id={`${item.id}-type-error`} message={typeError} />
                    </div>
                    {item.itemType === "fixed" ? (
                      <div className="field mb-0">
                        <label className="field__label" htmlFor={`${item.id}-amount`}>Valor (R$)</label>
                        <input aria-describedby={amountError ? `${item.id}-amount-error` : undefined} aria-label={`Valor do item ${index + 1} (R$)`} className="input mono" id={`${item.id}-amount`} inputMode="decimal" name={`items-${index}-amount`} onChange={(event) => updateItem(index, { amount: event.target.value })} placeholder="0,00" type="text" value={item.amount} />
                        <FieldError id={`${item.id}-amount-error`} message={amountError} />
                      </div>
                    ) : null}
                    <div className="field mb-0">
                      <span className="field__label sr-only">Remover</span>
                      <button aria-label={`Remover item ${index + 1}`} className="icon-btn" disabled={form.items.length === 1} onClick={() => setField("items", form.items.filter((_, current) => current !== index))} title={form.items.length === 1 ? "A cobrança precisa de pelo menos um item" : "Remover item"} type="button"><Trash2 aria-hidden="true" size={16} /></button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="actionbar">
        <div className="actionbar__total"><span className="lbl">Subtotal fixo / mês</span><span className="val mono" id="fixed-subtotal">{formatBrl(fixedSubtotal)}</span></div>
        <div className="btn-row">
          <Link className="btn btn--ghost" to={cancelTo ?? (mode === "create" ? "/billings/" : ".")}>Cancelar</Link>
          <button className="btn btn--primary" disabled={saving} type="submit">{saving ? "Salvando..." : mode === "create" ? "Criar cobrança" : "Salvar alterações"}</button>
        </div>
      </div>
    </form>
  );
}
