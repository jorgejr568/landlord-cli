import {
  ArrowRight,
  Check,
  Copy,
  Download,
  EyeOff,
  Printer,
  ShieldCheck
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Navigate, useLocation, useNavigate } from "react-router";

import { useAuth } from "../auth/AuthProvider";

import "./RecoveryCodesPage.css";

interface RecoveryLocationState { recoveryCodes?: string[] }

type Feedback = { kind: "error" | "success"; message: string } | null;

export function RecoveryCodesPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const { refreshSession } = useAuth();
  const recoveryCodes = (location.state as RecoveryLocationState | null)?.recoveryCodes;
  const [feedback, setFeedback] = useState<Feedback>(null);
  const [continuing, setContinuing] = useState(false);
  const [refreshFailed, setRefreshFailed] = useState(false);
  const refreshErrorRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    document.title = "Códigos de Recuperação - Rentivo";
  }, []);

  useEffect(() => {
    if (!recoveryCodes?.length) return;
    const warnBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", warnBeforeUnload);
    return () => window.removeEventListener("beforeunload", warnBeforeUnload);
  }, [recoveryCodes]);

  useEffect(() => {
    if (refreshFailed) refreshErrorRef.current?.focus();
  }, [refreshFailed]);

  if (!recoveryCodes?.length) {
    return <Navigate replace to="/security" />;
  }

  async function copyCodes() {
    try {
      await navigator.clipboard.writeText(recoveryCodes!.join("\n"));
      setFeedback({
        kind: "success",
        message: "Códigos copiados. Guarde a cópia em um local seguro."
      });
    } catch {
      setFeedback({
        kind: "error",
        message: "Não foi possível copiar. Selecione os códigos ou baixe o arquivo."
      });
    }
  }

  function downloadCodes() {
    const contents = [
      "Códigos de recuperação Rentivo",
      "Cada código funciona uma única vez.",
      "",
      ...recoveryCodes!
    ].join("\n");
    let url: string | null = null;
    try {
      const blob = new Blob([contents], { type: "text/plain;charset=utf-8" });
      url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.download = "rentivo-codigos-recuperacao.txt";
      link.href = url;
      link.click();
      setFeedback({
        kind: "success",
        message: "Arquivo baixado. Guarde-o em um local protegido."
      });
    } catch {
      setFeedback({
        kind: "error",
        message: "Não foi possível baixar. Copie os códigos ou tente imprimir."
      });
    } finally {
      if (url) URL.revokeObjectURL(url);
    }
  }

  async function continueToSecurity() {
    setContinuing(true);
    setRefreshFailed(false);
    try {
      await refreshSession();
      navigate("/security");
    } catch {
      setRefreshFailed(true);
    } finally {
      setContinuing(false);
    }
  }

  return (
    <section aria-labelledby="recovery-codes-title" className="recovery-codes-page">
      <header className="recovery-codes-page__header">
        <div className="recovery-codes-page__heading">
          <span className="recovery-codes-page__mark" aria-hidden="true">
            <ShieldCheck size={25} />
          </span>
          <div>
            <h1 id="recovery-codes-title">Códigos de Recuperação</h1>
            <p>Guarde esta lista agora. Cada código devolve o acesso à sua conta uma única vez.</p>
          </div>
        </div>
        <div className="recovery-codes-page__privacy">
          <EyeOff aria-hidden="true" size={19} />
          <span>
            <strong>Visíveis somente agora</strong>
            <small>A Rentivo não mostrará esta lista novamente.</small>
          </span>
        </div>
      </header>

      <div className="recovery-workspace">
        <section aria-labelledby="recovery-list-title" className="recovery-workspace__codes">
          <div className="recovery-workspace__codes-header">
            <div>
              <h2 id="recovery-list-title">Seus códigos</h2>
              <p>Use somente quando não tiver acesso ao seu segundo fator.</p>
            </div>
            <span>{recoveryCodes.length} {recoveryCodes.length === 1 ? "código" : "códigos"}</span>
          </div>

          <ol aria-label="Códigos de recuperação" className="recovery-code-list">
            {recoveryCodes.map((code, index) => (
              <li key={code}>
                <span aria-hidden="true">{String(index + 1).padStart(2, "0")}</span>
                <code translate="no">{code}</code>
              </li>
            ))}
          </ol>

          <div
            aria-label="Opções para guardar os códigos"
            className="recovery-workspace__tools"
            role="group"
          >
            <button className="btn btn--primary" onClick={() => void copyCodes()} type="button">
              <Copy aria-hidden="true" size={16} />
              Copiar códigos
            </button>
            <button className="btn" onClick={downloadCodes} type="button">
              <Download aria-hidden="true" size={16} />
              Baixar arquivo
            </button>
            <button className="btn" onClick={() => window.print()} type="button">
              <Printer aria-hidden="true" size={16} />
              Imprimir códigos
            </button>
          </div>

          <div className="recovery-workspace__feedback" aria-live="polite">
            {feedback ? (
              <p className={`is-${feedback.kind}`} role={feedback.kind === "error" ? "alert" : "status"}>
                {feedback.kind === "success" ? <Check aria-hidden="true" size={16} /> : null}
                {feedback.message}
              </p>
            ) : null}
          </div>
        </section>

        <aside aria-labelledby="recovery-checklist-title" className="recovery-workspace__guide">
          <h2 id="recovery-checklist-title">Antes de sair</h2>
          <p>Escolha uma opção que você consiga acessar mesmo sem o celular.</p>
          <ol>
            <li>
              <span>1</span>
              <div>
                <strong>Salve uma cópia</strong>
                <p>Use um gerenciador de senhas, arquivo protegido ou impressão guardada.</p>
              </div>
            </li>
            <li>
              <span>2</span>
              <div>
                <strong>Mantenha fora do celular</strong>
                <p>Não deixe os códigos somente no dispositivo usado para autenticar.</p>
              </div>
            </li>
            <li>
              <span>3</span>
              <div>
                <strong>Use um código por vez</strong>
                <p>Depois de usado, risque ou remova o código da sua cópia.</p>
              </div>
            </li>
          </ol>
        </aside>

        <footer className="recovery-workspace__footer">
          <div>
            <ShieldCheck aria-hidden="true" size={20} />
            <p>
              <strong>Já guardou os códigos?</strong>
              <span>Concluir fecha esta exibição única.</span>
            </p>
          </div>
          <button
            aria-busy={continuing}
            className="btn btn--primary"
            disabled={continuing}
            onClick={() => void continueToSecurity()}
            type="button"
          >
            {continuing ? "Atualizando sessão…" : refreshFailed ? "Tentar novamente" : "Concluir e ir para Segurança"}
            {!continuing ? <ArrowRight aria-hidden="true" size={17} /> : null}
          </button>
        </footer>

        {refreshFailed ? (
          <div
            className="recovery-workspace__refresh-error"
            ref={refreshErrorRef}
            role="alert"
            tabIndex={-1}
          >
            <strong>Não foi possível atualizar sua sessão. Seus códigos continuam nesta tela.</strong>
            <span>Verifique sua conexão e tente novamente.</span>
          </div>
        ) : null}
      </div>
    </section>
  );
}
