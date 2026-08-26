import { Pencil, Trash2 } from "lucide-react";

import type { components } from "../../lib/api/schema";
import { scopeLabel } from "./ApiKeyForm";

type ApiKey = components["schemas"]["APIKeyResponse"];
type ApiKeyOptions = components["schemas"]["APIKeyOptionsResponse"];

interface ApiKeyListProps {
  items: ApiKey[];
  onEdit: (key: ApiKey) => void;
  onRevoke: (key: ApiKey) => void;
  options: ApiKeyOptions;
}

const DATE_FORMAT = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" });

// eslint-disable-next-line react-refresh/only-export-components
export function formatDate(value: string | null): string {
  return value ? DATE_FORMAT.format(new Date(value)) : "Nunca";
}

export function ApiKeyList({ items, onEdit, onRevoke, options }: ApiKeyListProps) {
  if (items.length === 0) {
    return <p className="api-key-empty">Nenhuma chave de integração cadastrada.</p>;
  }

  const organizationNames = new Map(options.organizations.map((organization) => [organization.resource_id, organization.name]));
  return (
    <div className="data-table-wrap api-key-table-wrap">
      <table className="data-table api-key-table">
        <thead><tr><th>Nome</th><th>Chave</th><th>Permissões</th><th>Espaços</th><th>Criada em</th><th>Expira em</th><th>Último uso</th><th className="text-right">Ações</th></tr></thead>
        <tbody>
          {items.map((key) => {
            const revoked = key.revoked_at !== null;
            return (
              <tr key={key.uuid}>
                <td className="api-key-table__name"><strong>{key.name}</strong>{revoked ? <span className="tag tag--cancelled api-key-table__status">Revogada</span> : null}</td>
                <td className="api-key-table__hint"><code>{key.hint}</code></td>
                <td>{key.scopes.map(scopeLabel).join(", ")}</td>
                <td>{key.grants.map((grant) => grant.resource_type === "user" ? "Pessoal" : grant.available && grant.resource_id ? (organizationNames.get(grant.resource_id) ?? "Organização") : "Espaço indisponível").join(", ")}</td>
                <td>{formatDate(key.created_at)}</td>
                <td>{formatDate(key.expires_at)}</td>
                <td>{formatDate(key.last_used_at)}</td>
                <td className="text-right">
                  <div className="btn-row api-key-table__actions">
                    <button aria-label={`Editar ${key.name}`} className="icon-btn api-key-table__edit" disabled={revoked} onClick={() => onEdit(key)} title="Editar" type="button"><Pencil aria-hidden="true" size={16} /></button>
                    <button aria-label={`Revogar ${key.name}`} className="icon-btn api-key-table__revoke" disabled={revoked} onClick={() => onRevoke(key)} title="Revogar" type="button"><Trash2 aria-hidden="true" size={16} /></button>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
