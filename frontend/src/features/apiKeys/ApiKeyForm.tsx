import { useMemo, useState, type FormEvent } from "react";

import { FieldError } from "../../components/FieldError";
import type { components } from "../../lib/api/schema";
import { shouldAutoFocus } from "../../lib/autofocus";
import { limitApiCharacters } from "../../lib/textLimits";

type ApiKey = components["schemas"]["APIKeyResponse"];
type ApiKeyCreate = components["schemas"]["APIKeyCreateRequest"];
type ApiKeyOptions = components["schemas"]["APIKeyOptionsResponse"];

export type ApiKeyFormPayload = Omit<ApiKeyCreate, "grants"> & {
  grants?: ApiKeyCreate["grants"];
};

interface ApiKeyFormProps {
  initialKey?: ApiKey;
  loading?: boolean;
  onCancel: () => void;
  onSubmit: (payload: ApiKeyFormPayload) => Promise<void> | void;
  options: ApiKeyOptions;
}

const SCOPE_LABELS: Record<string, string> = {
  "billings:read": "Consultar cobranças",
  "billings:write": "Gerenciar cobranças",
  "bills:read": "Consultar faturas",
  "bills:write": "Gerenciar faturas",
  "communications:read": "Consultar comunicações",
  "communications:send": "Enviar comunicações",
  "expenses:read": "Consultar despesas",
  "expenses:write": "Gerenciar despesas",
  "exports:create": "Criar exportações",
  "files:read": "Consultar arquivos",
  "files:write": "Gerenciar arquivos",
  "organizations:read": "Consultar organizações",
  "profile:read": "Consultar perfil",
  "themes:read": "Consultar temas",
  "themes:write": "Gerenciar temas"
};

function defaultExpiration(days: number): string {
  const value = new Date();
  value.setDate(value.getDate() + days);
  return value.toISOString().slice(0, 10);
}

function explicitExpiration(value: string, maxDays: number): string {
  const selectedEndOfDay = new Date(`${value}T23:59:59.999Z`).getTime();
  const maximum = Date.now() + maxDays * 24 * 60 * 60 * 1000 - 60_000;
  return new Date(Math.min(selectedEndOfDay, maximum)).toISOString();
}

// eslint-disable-next-line react-refresh/only-export-components
export function scopeLabel(scope: string): string {
  return SCOPE_LABELS[scope] ?? scope;
}

export function ApiKeyForm({ initialKey, loading = false, onCancel, onSubmit, options }: ApiKeyFormProps) {
  const initialOrganizations = useMemo(
    () => {
      const selectable = new Set(options.organizations.map((organization) => organization.resource_id));
      return initialKey?.grants
        .filter((grant) => grant.available && grant.resource_type === "organization" && grant.resource_id)
        .filter((grant) => selectable.has(grant.resource_id as string))
        .map((grant) => grant.resource_id as string) ?? [];
    },
    [initialKey, options.organizations]
  );
  const [name, setName] = useState(initialKey?.name ?? "");
  const [scopes, setScopes] = useState<string[]>(initialKey?.scopes ?? []);
  const [personal, setPersonal] = useState(
    initialKey?.grants.some((grant) => grant.available && grant.resource_type === "user") ?? false
  );
  const [organizations, setOrganizations] = useState<string[]>(initialOrganizations);
  const [expiresAt, setExpiresAt] = useState(defaultExpiration(options.default_expiration_days));
  const [expirationChanged, setExpirationChanged] = useState(false);
  const [grantsChanged, setGrantsChanged] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  function toggle(values: string[], value: string): string[] {
    return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitted(true);
    const normalizedName = name.trim();
    const hasWorkspace = personal || organizations.length > 0 || Boolean(initialKey && !grantsChanged);
    if (!normalizedName || scopes.length === 0 || !hasWorkspace) {
      return;
    }
    await onSubmit({
      ...(!initialKey && expirationChanged
        ? { expires_at: explicitExpiration(expiresAt, options.max_expiration_days) }
        : {}),
      ...(!initialKey || grantsChanged ? {
        grants: [
          ...(personal ? [{ resource_id: "personal", resource_type: "user" as const }] : []),
          ...organizations.map((resourceId) => ({ resource_id: resourceId, resource_type: "organization" as const }))
        ]
      } : {}),
      name: normalizedName,
      scopes
    });
  }

  return (
    <form aria-label="Configurar chave de integração" className="api-key-form" onSubmit={(event) => void handleSubmit(event)}>
      <div className="field">
        <label className="field-label" htmlFor="api-key-name">Nome</label>
        <input aria-describedby={submitted && !name.trim() ? "api-key-name-error" : undefined} aria-invalid={submitted && !name.trim()} autoComplete="off" autoFocus={shouldAutoFocus()} className="field-input" id="api-key-name" name="api_key_name" onChange={(event) => setName(limitApiCharacters(event.target.value, 255))} value={name} />
        <FieldError id="api-key-name-error" message={submitted && !name.trim() ? "Informe um nome para a chave." : undefined} />
      </div>
      <fieldset aria-describedby={submitted && scopes.length === 0 ? "api-key-scopes-error" : undefined} className="field api-key-form__group">
        <legend className="field-label">Permissões</legend>
        <div className="api-key-choice-grid">
          {options.scopes.map((scope) => (
            <label className="api-key-choice" key={scope}>
              <input checked={scopes.includes(scope)} onChange={() => setScopes(toggle(scopes, scope))} type="checkbox" />
              {scopeLabel(scope)}
            </label>
          ))}
        </div>
        <FieldError id="api-key-scopes-error" message={submitted && scopes.length === 0 ? "Selecione pelo menos um escopo." : undefined} />
      </fieldset>
      <fieldset aria-describedby={submitted && !personal && organizations.length === 0 && (!initialKey || grantsChanged) ? "api-key-workspaces-error" : undefined} className="field api-key-form__group">
        <legend className="field-label">Espaços de trabalho</legend>
        <div className="api-key-choice-grid api-key-choice-grid--workspaces">
        <label className="api-key-choice">
          <input checked={personal} onChange={(event) => { setPersonal(event.target.checked); setGrantsChanged(true); }} type="checkbox" />
          Pessoal
        </label>
        {options.organizations.map((organization) => (
          <label className="api-key-choice" key={organization.resource_id}>
            <input
              checked={organizations.includes(organization.resource_id)}
              onChange={() => { setOrganizations(toggle(organizations, organization.resource_id)); setGrantsChanged(true); }}
              type="checkbox"
            />
            {organization.name}
          </label>
        ))}
        </div>
        <FieldError id="api-key-workspaces-error" message={submitted && !personal && organizations.length === 0 && (!initialKey || grantsChanged) ? "Selecione pelo menos um espaço de trabalho." : undefined} />
      </fieldset>
      {!initialKey ? (
        <div className="field api-key-form__expiration">
          <label className="field-label" htmlFor="api-key-expiration">Expira em</label>
          <input autoComplete="off" className="field-input" id="api-key-expiration" max={defaultExpiration(options.max_expiration_days)} min={new Date().toISOString().slice(0, 10)} name="api_key_expiration" onChange={(event) => { setExpiresAt(event.target.value); setExpirationChanged(true); }} required type="date" value={expiresAt} />
        </div>
      ) : null}
      <div className="btn-row">
        <button className="btn btn--primary btn--sm" disabled={loading} type="submit">{initialKey ? "Salvar alterações" : "Criar chave"}</button>
        <button className="btn btn--sm" disabled={loading} onClick={onCancel} type="button">Cancelar</button>
      </div>
    </form>
  );
}
