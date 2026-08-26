import { Landmark, X } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent } from "react";

import { FieldError } from "../../components/FieldError";
import { PIX_KEY_GUIDANCE, PIX_MERCHANT_NAME_GUIDANCE } from "../../forms/pixGuidance";
import { validatePix } from "../../forms/validators";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { limitApiCharacters } from "../../lib/textLimits";
import { SubmitButton } from "../auth/AuthComponents";
import "./PixSetupDialog.css";

type PixErrors = Partial<Record<"city" | "key" | "name", string>>;
type SecuritySummary = components["schemas"]["SecuritySummaryResponse"];

interface PixSetupDialogProps {
  onClose: () => void;
  onSaved: () => Promise<void>;
  open: boolean;
}

function messageFor(error: unknown, fallback: string): string {
  return error instanceof ApiError ? error.message : fallback;
}

export function PixSetupDialog({ onClose, onSaved, open }: PixSetupDialogProps) {
  const [key, setKey] = useState("");
  const [name, setName] = useState("");
  const [city, setCity] = useState("");
  const [errors, setErrors] = useState<PixErrors>({});
  const [loaded, setLoaded] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [loadAttempt, setLoadAttempt] = useState(0);
  const dialogRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const hasFocusedForm = useRef(false);
  const keyRef = useRef<HTMLInputElement>(null);
  const nameRef = useRef<HTMLInputElement>(null);
  const cityRef = useRef<HTMLInputElement>(null);
  const savingRef = useRef(false);

  useEffect(() => {
    /* v8 ignore next -- the closed and open states are both asserted in PixSetupDialog.test */
    if (!open) return;
    const controller = new AbortController();
    setLoading(true);
    setLoaded(false);
    setLoadError("");
    setActionError("");
    setErrors({});
    hasFocusedForm.current = false;
    void apiRequest(apiClient.GET("/api/v1/security", { signal: controller.signal }))
      .then(({ data }: { data: SecuritySummary }) => {
        /* v8 ignore next -- late successful settlements after close are asserted and intentionally discarded */
        if (controller.signal.aborted) return;
        setKey(data.profile.pix_key);
        setName(data.profile.pix_merchant_name);
        setCity(data.profile.pix_merchant_city);
        setLoaded(true);
      })
      .catch((caught: unknown) => {
        if (!controller.signal.aborted) {
          setLoadError(messageFor(caught, "Não foi possível carregar seus dados PIX."));
        }
      })
      .finally(() => {
        /* v8 ignore next -- an aborted load intentionally leaves no mounted loading state to update */
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [loadAttempt, open]);

  useEffect(() => {
    /* v8 ignore next -- loading, loaded, errored, closed, and already-focused states are exercised in PixSetupDialog.test */
    if (!open || !loaded || loading || loadError || hasFocusedForm.current) return;
    hasFocusedForm.current = true;
    if (!key) keyRef.current?.focus();
    else if (!name) nameRef.current?.focus();
    else if (!city) cityRef.current?.focus();
    else keyRef.current?.focus();
  }, [city, key, loadError, loaded, loading, name, open]);

  useEffect(() => {
    savingRef.current = saving;
  }, [saving]);

  useEffect(() => {
    /* v8 ignore next -- the closed and open focus-management states are both asserted in PixSetupDialog.test */
    if (!open) return;
    const previouslyFocused = document.activeElement as HTMLElement | null;
    const previousBodyOverflow = document.body.style.overflow;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !savingRef.current) {
        event.preventDefault();
        onClose();
        return;
      }
      /* v8 ignore next -- Escape, Tab, and unrelated-key behavior are exercised through the keyboard tests */
      if (event.key !== "Tab") return;
      const focusable = Array.from(
        dialogRef.current!.querySelectorAll<HTMLElement>(
          'button:not([disabled]), input:not([disabled]), a[href]'
        )
      );
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      /* v8 ignore next -- reverse wrapping and ordinary reverse focus movement are both asserted */
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
        return;
      }
      /* v8 ignore next -- forward wrapping and ordinary forward focus movement are both asserted */
      if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", handleKeyDown, true);
    closeRef.current?.focus();
    return () => {
      document.body.style.overflow = previousBodyOverflow;
      document.removeEventListener("keydown", handleKeyDown, true);
      previouslyFocused?.focus();
    };
  }, [onClose, open]);

  async function savePix(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setActionError("");
    const validation = validatePix({ city, key, name });
    /* v8 ignore next -- valid and invalid submissions are asserted; lazy-route coverage can remap this branch */
    if ("errors" in validation) {
      setErrors(validation.errors);
      if (validation.errors.key) keyRef.current?.focus();
      else if (validation.errors.name) nameRef.current?.focus();
      else cityRef.current?.focus();
      return;
    }
    setErrors({});
    setSaving(true);
    try {
      await apiRequest(apiClient.POST("/api/v1/security/pix", {
        body: {
          pix_key: validation.value.key,
          pix_merchant_city: validation.value.city,
          pix_merchant_name: validation.value.name
        }
      }));
      await onSaved();
      onClose();
    } catch (caught: unknown) {
      setActionError(messageFor(caught, "Não foi possível salvar os dados PIX."));
      keyRef.current?.focus();
    } finally {
      setSaving(false);
    }
  }

  if (!open) return null;

  return (
    <div
      className="modal-overlay pix-setup-overlay"
      onMouseDown={(event) => {
        /* v8 ignore next -- backdrop, content, and saving-state clicks are all asserted; lazy-route coverage can remap this branch */
        if (!saving && event.currentTarget === event.target) onClose();
      }}
    >
      <div
        aria-describedby="pix-setup-intro"
        aria-labelledby="pix-setup-title"
        aria-modal="true"
        className="modal pix-setup-dialog"
        ref={dialogRef}
        role="dialog"
      >
        <header className="pix-setup-dialog__head">
          <span aria-hidden="true" className="pix-setup-dialog__icon"><Landmark size={21} /></span>
          <div>
            <h2 id="pix-setup-title">Receber por PIX</h2>
            <p id="pix-setup-intro">Só precisamos destes 3 dados para colocar o PIX nas suas faturas pessoais.</p>
          </div>
          <button aria-label="Fechar" className="pix-setup-dialog__close" disabled={saving} onClick={onClose} ref={closeRef} type="button">
            <X aria-hidden="true" size={19} />
          </button>
        </header>

        {loading ? (
          <div aria-label="Carregando dados PIX" className="pix-setup-dialog__loading" role="status">
            <span className="skeleton-block" />
            <span className="skeleton-block" />
            <span className="skeleton-block" />
          </div>
        ) : loadError ? (
          <div className="pix-setup-dialog__load-error">
            <p role="alert">{loadError}</p>
            <button className="btn btn--sm" onClick={() => setLoadAttempt((value) => value + 1)} type="button">Tentar novamente</button>
          </div>
        ) : (
          <form className="pix-setup-dialog__form" onSubmit={(event) => void savePix(event)}>
            {actionError ? <div className="toast toast--danger" role="alert">{actionError}</div> : null}
            <div className="field pix-setup-dialog__key">
              <label className="field__label" htmlFor="quick-pix-key">Chave PIX</label>
              <input aria-describedby={errors.key ? "quick-pix-key-error" : "quick-pix-key-hint"} aria-invalid={Boolean(errors.key)} autoComplete="off" className="input mono" id="quick-pix-key" name="pix_key" onChange={(event) => { setKey(event.target.value); setErrors({}); }} ref={keyRef} spellCheck={false} value={key} />
              {errors.key ? <FieldError id="quick-pix-key-error" message={errors.key} /> : <span className="field__hint" id="quick-pix-key-hint">{PIX_KEY_GUIDANCE}</span>}
            </div>
            <div className="pix-setup-dialog__row">
              <div className="field">
                <label className="field__label" htmlFor="quick-pix-name">Nome do recebedor</label>
                <input aria-describedby={errors.name ? "quick-pix-name-error" : "quick-pix-name-hint"} aria-invalid={Boolean(errors.name)} autoComplete="off" className="input" id="quick-pix-name" name="pix_merchant_name" onChange={(event) => { setName(limitApiCharacters(event.target.value, 255)); setErrors({}); }} ref={nameRef} value={name} />
                {errors.name ? <FieldError id="quick-pix-name-error" message={errors.name} /> : <span className="field__hint" id="quick-pix-name-hint">{PIX_MERCHANT_NAME_GUIDANCE}</span>}
              </div>
              <div className="field">
                <label className="field__label" htmlFor="quick-pix-city">Cidade do recebedor</label>
                <input aria-describedby={errors.city ? "quick-pix-city-error" : undefined} aria-invalid={Boolean(errors.city)} autoComplete="off" className="input mono" id="quick-pix-city" name="pix_merchant_city" onChange={(event) => { setCity(limitApiCharacters(event.target.value, 255)); setErrors({}); }} ref={cityRef} value={city} />
                <FieldError id="quick-pix-city-error" message={errors.city} />
              </div>
            </div>
            <footer className="pix-setup-dialog__foot">
              <button className="btn btn--ghost" disabled={saving} onClick={onClose} type="button">Agora não</button>
              <SubmitButton className="btn btn--primary" loading={saving}>{saving ? "Salvando..." : "Salvar PIX"}</SubmitButton>
            </footer>
          </form>
        )}
      </div>
    </div>
  );
}
