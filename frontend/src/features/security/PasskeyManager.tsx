import { KeyRound, Trash2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import type { components } from "../../lib/api/schema";
import { limitApiCharacters } from "../../lib/textLimits";

type Passkey = components["schemas"]["PasskeyResponse"];

interface PasskeyManagerProps {
  onDelete: (uuid: string) => Promise<void>;
  onRegister: (name: string) => Promise<void>;
  onSessionRevoked: () => void;
  organizationEnforced: boolean;
  passkeys: Passkey[];
}

const DATE_FORMAT = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short" });

export function PasskeyManager({ onDelete, onRegister, onSessionRevoked, organizationEnforced, passkeys }: PasskeyManagerProps) {
  const [name, setName] = useState("");
  const [target, setTarget] = useState<Passkey | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { if (error) inputRef.current?.focus(); }, [error]);

  async function register() {
    setLoading(true);
    setError(null);
    try {
      await onRegister(name.trim() || "Minha Passkey");
      setName("");
    } catch (caught: unknown) {
      if (caught instanceof DOMException && caught.name === "NotAllowedError") {
        return;
      }
      setError(caught instanceof Error ? caught.message : "Não foi possível cadastrar a passkey.");
    } finally {
      setLoading(false);
    }
  }

  async function remove() {
    const uuid = target!.uuid;
    setTarget(null);
    setLoading(true);
    setError(null);
    try {
      await onDelete(uuid);
      onSessionRevoked();
    } catch (caught: unknown) {
      setError(caught instanceof Error ? caught.message : "Não foi possível remover a passkey.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <article aria-labelledby="passkeys-title" className="security-auth-method security-auth-method--passkeys">
      <div className="security-auth-method__heading"><KeyRound aria-hidden="true" size={20} /><div><h3 id="passkeys-title">Passkeys</h3><p>Entre com o dispositivo, sem digitar a senha.</p></div></div>
        {organizationEnforced ? <div className="security-inline-notice">Sua organização exige autenticação multifator. Mantenha pelo menos um fator ativo.</div> : null}
        {error ? <div className="toast toast--danger" role="alert">{error}</div> : null}
        {passkeys.length ? (
          <div className="data-table-wrap security-passkey-table">
            <table className="data-table">
              <thead><tr><th>Nome</th><th>Criada em</th><th>Último uso</th><th className="text-right">Ações</th></tr></thead>
              <tbody>{passkeys.map((passkey) => (
                <tr key={passkey.uuid}>
                  <td>{passkey.name || "Sem nome"}</td>
                  <td>{DATE_FORMAT.format(new Date(passkey.created_at))}</td>
                  <td>{passkey.last_used_at ? DATE_FORMAT.format(new Date(passkey.last_used_at)) : "Nunca"}</td>
                  <td className="text-right"><button aria-label={`Remover ${passkey.name}`} className="icon-btn" disabled={loading} onClick={() => setTarget(passkey)} title="Remover" type="button"><Trash2 aria-hidden="true" size={16} /></button></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        ) : <p className="security-auth-method__empty">Nenhuma passkey cadastrada.</p>}
        <form className="security-passkey-form" onSubmit={(event) => { event.preventDefault(); void register(); }}>
          <div className="field"><label className="field-label" htmlFor="passkey-name">Nome da passkey</label><input autoComplete="off" className="field-input" id="passkey-name" name="passkey_name" onChange={(event) => setName(limitApiCharacters(event.target.value, 255))} placeholder="Ex.: Notebook…" ref={inputRef} value={name} /></div>
          <button className="btn btn--primary btn--sm" disabled={loading} type="submit"><KeyRound aria-hidden="true" size={15} />Adicionar Passkey</button>
        </form>
      <ConfirmDialog acceptLabel="Remover passkey" body="Você precisará entrar novamente após remover esta passkey." onClose={() => setTarget(null)} onConfirm={() => void remove()} open={target !== null} title="Remover esta passkey?" />
    </article>
  );
}
