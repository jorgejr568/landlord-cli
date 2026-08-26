import {
  ArrowLeft,
  Building2,
  Check,
  Eye,
  FileText,
  Palette,
  RotateCcw,
  Save,
  TriangleAlert,
  Type
} from "lucide-react";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent
} from "react";
import { Link, useParams } from "react-router";

import { ConfirmDialog } from "../../components/ConfirmDialog";
import { FieldError } from "../../components/FieldError";
import { LoadError, LoadingState } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage, normalizedFieldErrors } from "../../lib/api/errors";
import type { components } from "../../lib/api/schema";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import "./ThemePage.css";

type ThemeResponse = components["schemas"]["ThemeResponse"];
type ThemeValues = components["schemas"]["ThemeUpdateRequest"];
type ThemeTarget = "billing" | "organization" | "user";
type ColorKey = keyof Pick<
  ThemeValues,
  "primary" | "primary_light" | "secondary" | "secondary_dark" | "text_color" | "text_contrast"
>;

export interface ThemePageProps {
  backUrl?: string;
  ownerLabel?: string;
  target: ThemeTarget;
  targetUuid?: string;
}

const BILLING_SOURCE_LABELS: Record<ThemeResponse["effective_source"], string> = {
  billing: "Personalização exclusiva",
  default: "Padrão Rentivo",
  organization: "Tema da organização",
  user: "Tema pessoal"
};

const TARGET_META: Record<ThemeTarget, {
  backPrefix: string;
  missing: string;
  resetSuccess: string;
  saveSuccess: string;
  title: string;
}> = {
  billing: {
    backPrefix: "/billings/",
    missing: "Não foi possível identificar a cobrança.",
    resetSuccess: "Personalização removida. A cobrança voltou a seguir o tema do proprietário.",
    saveSuccess: "Tema da cobrança salvo com sucesso!",
    title: "Tema da cobrança"
  },
  organization: {
    backPrefix: "/organizations/",
    missing: "Não foi possível identificar a organização.",
    resetSuccess: "Tema da organização redefinido para o padrão.",
    saveSuccess: "Tema da organização salvo com sucesso!",
    title: "Tema da organização"
  },
  user: {
    backPrefix: "/billings/",
    missing: "",
    resetSuccess: "Tema redefinido para o padrão.",
    saveSuccess: "Tema salvo com sucesso!",
    title: "Meu Tema"
  }
};

const COLOR_FIELDS: Array<{ hint: string; key: ColorKey; label: string }> = [
  { hint: "Destaques e cabeçalhos", key: "primary", label: "Primária" },
  { hint: "Fundos em destaque", key: "primary_light", label: "Primária Clara" },
  { hint: "Superfícies da fatura", key: "secondary", label: "Secundária" },
  { hint: "Blocos de informação", key: "secondary_dark", label: "Secundária Escura" },
  { hint: "Conteúdo principal", key: "text_color", label: "Texto" },
  { hint: "Texto sobre a cor primária", key: "text_contrast", label: "Contraste" }
];
const COLOR_KEYS = new Set<ColorKey>(COLOR_FIELDS.map(({ key }) => key));

const INITIAL_VALUES: ThemeValues = {
  header_font: "Space Grotesk",
  primary: "#007D53",
  primary_light: "#DBF6E7",
  secondary: "#F5F2EB",
  secondary_dark: "#1B1D29",
  text_color: "#1B1D29",
  text_contrast: "#FFFFFF",
  text_font: "Hanken Grotesk"
};

function fieldErrorId(fields: Record<string, string>, key: string): string | undefined {
  return fields[key] ? `${key}-error` : undefined;
}

function contrastRatio(first: string, second: string): number {
  const luminance = (color: string) => {
    const channels = [1, 3, 5].map((offset) => Number.parseInt(color.slice(offset, offset + 2), 16) / 255);
    const linear = channels.map((channel) => channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4);
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
  };
  const [lighter, darker] = [luminance(first), luminance(second)].sort((left, right) => right - left);
  return (lighter + 0.05) / (darker + 0.05);
}

function themesMatch(first: ThemeValues, second: ThemeValues): boolean {
  return first.header_font === second.header_font
    && first.text_font === second.text_font
    && COLOR_FIELDS.every(({ key }) => first[key] === second[key]);
}

async function getTheme(target: ThemeTarget, uuid: string, signal: AbortSignal) {
  if (target === "organization") {
    return apiRequest(apiClient.GET("/api/v1/themes/organizations/{org_uuid}", {
      params: { path: { org_uuid: uuid } },
      signal
    }));
  }
  if (target === "billing") {
    return apiRequest(apiClient.GET("/api/v1/themes/billings/{billing_uuid}", {
      params: { path: { billing_uuid: uuid } },
      signal
    }));
  }
  return apiRequest(apiClient.GET("/api/v1/themes/user", { signal }));
}

async function putTheme(
  target: ThemeTarget,
  uuid: string,
  body: ThemeValues,
  signal: AbortSignal
) {
  if (target === "organization") {
    return apiRequest(apiClient.PUT("/api/v1/themes/organizations/{org_uuid}", {
      body,
      params: { path: { org_uuid: uuid } },
      signal
    }));
  }
  if (target === "billing") {
    return apiRequest(apiClient.PUT("/api/v1/themes/billings/{billing_uuid}", {
      body,
      params: { path: { billing_uuid: uuid } },
      signal
    }));
  }
  return apiRequest(apiClient.PUT("/api/v1/themes/user", { body, signal }));
}

async function deleteTheme(target: ThemeTarget, uuid: string, signal: AbortSignal) {
  if (target === "organization") {
    return apiRequest(apiClient.DELETE("/api/v1/themes/organizations/{org_uuid}", {
      params: { path: { org_uuid: uuid } },
      signal
    }));
  }
  if (target === "billing") {
    return apiRequest(apiClient.DELETE("/api/v1/themes/billings/{billing_uuid}", {
      params: { path: { billing_uuid: uuid } },
      signal
    }));
  }
  return apiRequest(apiClient.DELETE("/api/v1/themes/user", { signal }));
}

export function ThemePage({ backUrl, ownerLabel, target, targetUuid }: ThemePageProps) {
  const { billingUuid, orgUuid } = useParams<{ billingUuid?: string; orgUuid?: string }>();
  const routeUuid = target === "organization"
    ? orgUuid ?? ""
    : target === "billing"
      ? billingUuid ?? ""
      : "";
  const uuid = targetUuid ?? routeUuid;
  const meta = TARGET_META[target];
  const [theme, setTheme] = useState<ThemeResponse | null>(null);
  const resolvedOwnerLabel = ownerLabel
    ?? (theme
      ? target === "user" || target === "organization"
        ? theme.owner_name
        : `${theme.owner_name} - Tema`
      : meta.title);
  const [values, setValues] = useState<ThemeValues>(INITIAL_VALUES);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [resetting, setResetting] = useState(false);
  const [resetOpen, setResetOpen] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [success, setSuccess] = useState("");
  const [previewError, setPreviewError] = useState("");
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewStale, setPreviewStale] = useState(false);
  const [previewUrl, setPreviewUrl] = useState("");
  const previewTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const currentPreviewUrl = useRef("");
  const previewController = useRef<AbortController | null>(null);
  const loadController = useRef<AbortController | null>(null);
  const saveController = useRef<AbortController | null>(null);
  const resetController = useRef<AbortController | null>(null);
  const targetGeneration = useRef(0);
  const targetKey = `${target}:${uuid}`;
  const renderedTargetKey = useRef(targetKey);
  if (renderedTargetKey.current !== targetKey) {
    renderedTargetKey.current = targetKey;
    targetGeneration.current += 1;
  }

  const cancelMutationWork = useCallback(() => {
    saveController.current?.abort();
    saveController.current = null;
    resetController.current?.abort();
    resetController.current = null;
  }, []);

  const cancelPreviewWork = useCallback(() => {
    previewController.current?.abort();
    previewController.current = null;
    if (previewTimer.current !== null) {
      clearTimeout(previewTimer.current);
      previewTimer.current = null;
    }
  }, []);

  const requestPreview = useCallback(async (nextValues: ThemeValues) => {
    previewController.current?.abort();
    const controller = new AbortController();
    previewController.current = controller;
    setPreviewLoading(true);
    const outcome = await apiRequest(
      apiClient.POST("/api/v1/themes/preview", {
        body: nextValues,
        parseAs: "blob",
        signal: controller.signal
      })
    ).then(
      ({ data }) => ({ data }),
      (error: unknown) => ({ error })
    );
    if (controller.signal.aborted) {
      return;
    }
    if ("error" in outcome) {
      setPreviewError(errorMessage(outcome.error, "Não foi possível gerar a pré-visualização."));
      setPreviewLoading(false);
      return;
    }
    const nextUrl = URL.createObjectURL(outcome.data);
    if (currentPreviewUrl.current) {
      URL.revokeObjectURL(currentPreviewUrl.current);
    }
    currentPreviewUrl.current = nextUrl;
    setPreviewUrl(nextUrl);
    setPreviewError("");
    setPreviewLoading(false);
    setPreviewStale(false);
  }, []);

  const schedulePreview = useCallback((nextValues: ThemeValues) => {
    if (previewTimer.current !== null) {
      clearTimeout(previewTimer.current);
    }
    previewTimer.current = setTimeout(() => {
      previewTimer.current = null;
      void requestPreview(nextValues);
    }, 300);
  }, [requestPreview]);

  const load = useCallback(async () => {
    loadController.current?.abort();
    cancelPreviewWork();
    if (currentPreviewUrl.current) {
      URL.revokeObjectURL(currentPreviewUrl.current);
      currentPreviewUrl.current = "";
    }
    setPreviewUrl("");
    setPreviewError("");
    setPreviewLoading(false);
    setPreviewStale(false);
    setTheme(null);
    setLoading(true);
    setLoadError("");
    setActionError("");
    setFieldErrors({});

    const controller = new AbortController();
    loadController.current = controller;
    if (target !== "user" && !uuid) {
      setLoadError(meta.missing);
      setLoading(false);
      return;
    }

    const outcome = await getTheme(target, uuid, controller.signal).then(
      (themeResult) => ({ themeResult }),
      (error: unknown) => ({ error })
    );

    if (controller.signal.aborted || loadController.current !== controller) {
      return;
    }
    if ("error" in outcome) {
      setLoadError(errorMessage(outcome.error, "Não foi possível carregar o tema."));
      setLoading(false);
      return;
    }

    const { data } = outcome.themeResult;
    const nextValues = data.stored ?? data.effective;
    setTheme(data);
    setValues(nextValues);
    setLoading(false);
    if (target === "user") schedulePreview(nextValues);
  }, [cancelPreviewWork, meta.missing, schedulePreview, target, uuid]);

  useEffect(() => {
    cancelMutationWork();
    setSaving(false);
    setResetting(false);
    setResetOpen(false);
    setSuccess("");
    void load();
    return () => {
      targetGeneration.current += 1;
      cancelMutationWork();
      loadController.current?.abort();
      cancelPreviewWork();
    };
  }, [cancelMutationWork, cancelPreviewWork, load]);

  useDocumentTitle(`${resolvedOwnerLabel} - Rentivo`);

  useEffect(() => () => {
    loadController.current?.abort();
    cancelPreviewWork();
    if (currentPreviewUrl.current) {
      URL.revokeObjectURL(currentPreviewUrl.current);
    }
  }, [cancelPreviewWork]);

  function updateValue<Key extends keyof ThemeValues>(key: Key, value: ThemeValues[Key]) {
    cancelPreviewWork();
    const nextValues = { ...values, [key]: value };
    setValues(nextValues);
    setFieldErrors((current) => ({ ...current, [key]: "" }));
    setPreviewLoading(false);
    setPreviewStale(true);
    if (target === "user" && !COLOR_KEYS.has(key as ColorKey)) schedulePreview(nextValues);
  }

  function previewNow() {
    if (previewTimer.current !== null) {
      clearTimeout(previewTimer.current);
      previewTimer.current = null;
    }
    void requestPreview(values);
  }

  async function saveTheme(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const controller = new AbortController();
    const generation = targetGeneration.current;
    saveController.current = controller;
    const ownsRequest = () => (
      !controller.signal.aborted
      && saveController.current === controller
      && targetGeneration.current === generation
    );
    setSaving(true);
    setSuccess("");
    setActionError("");
    setFieldErrors({});
    try {
      const { data, response } = await putTheme(target, uuid, values, controller.signal);
      if (!ownsRequest()) {
        return;
      }
      setTheme(data);
      setValues(data.effective);
      setSuccess(meta.saveSuccess);
      pushAnalyticsFromResponse(response);
    } catch (error) {
      if (!ownsRequest()) {
        return;
      }
      setActionError(errorMessage(error, "Não foi possível salvar o tema."));
      setFieldErrors(normalizedFieldErrors(error));
    } finally {
      if (ownsRequest()) {
        saveController.current = null;
        setSaving(false);
      }
    }
  }

  async function resetTheme() {
    const controller = new AbortController();
    const generation = targetGeneration.current;
    resetController.current = controller;
    const ownsRequest = () => (
      !controller.signal.aborted
      && resetController.current === controller
      && targetGeneration.current === generation
    );
    setResetting(true);
    setSuccess("");
    setActionError("");
    try {
      await deleteTheme(target, uuid, controller.signal);
      if (!ownsRequest()) {
        return;
      }
      setSuccess(meta.resetSuccess);
      await load();
    } catch (error) {
      if (!ownsRequest()) {
        return;
      }
      setActionError(errorMessage(error, "Não foi possível restaurar o tema padrão."));
    } finally {
      if (ownsRequest()) {
        resetController.current = null;
        setResetting(false);
      }
    }
  }

  const baselineValues = theme?.stored ?? theme?.effective ?? values;
  const isDirty = theme !== null && !themesMatch(values, baselineValues);

  useEffect(() => {
    if (!isDirty) return;
    const warnBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = "";
    };
    window.addEventListener("beforeunload", warnBeforeUnload);
    return () => window.removeEventListener("beforeunload", warnBeforeUnload);
  }, [isDirty]);

  if (loading) {
    return <LoadingState label="Carregando tema…" />;
  }
  if (!theme) {
    return <LoadError message={loadError} onRetry={() => void load()} />;
  }

  const resolvedBackUrl = backUrl ?? `${meta.backPrefix}${target === "user" ? "" : uuid}`;
  const ratio = contrastRatio(values.primary, values.text_contrast);
  const pageDescription = target === "organization"
    ? "Defina a identidade aplicada às faturas da organização e confira o resultado antes de salvar."
    : target === "billing"
      ? "Defina a identidade usada somente nas faturas desta cobrança e confira o resultado antes de salvar."
      : "Escolha a tipografia e a paleta usadas nas faturas enviadas aos seus inquilinos.";
  const controlsTitle = target === "organization"
    ? "Identidade da organização"
    : target === "billing"
      ? "Ajuste desta cobrança"
      : "Personalize sua marca";
  const controlsDescription = target === "billing"
    ? "As mudanças ficam restritas a esta cobrança. Atualize o PDF para conferir o documento completo."
    : "A amostra responde na hora. Atualize o PDF quando quiser conferir o documento completo.";
  const billingSourceLabel = theme.stored
    ? BILLING_SOURCE_LABELS.billing
    : BILLING_SOURCE_LABELS[theme.effective_source];
  const headerStateLabel = target === "billing"
    ? billingSourceLabel
    : theme.stored
      ? "Tema personalizado"
      : "Padrão Rentivo";
  const scopedPdfIdle = target !== "user"
    && !previewLoading
    && !previewError
    && !previewUrl;
  const previewStatus = previewLoading
    ? "Atualizando prévia…"
    : previewError
      ? "Prévia indisponível"
      : scopedPdfIdle
        ? "PDF pronto para gerar"
      : previewStale
      ? "Atualize o PDF para aplicar as cores"
      : previewUrl
        ? "Prévia atualizada"
        : "Preparando prévia…";

  return (
    <>
      <header className="theme-page-header">
        <div className="theme-page-header__copy">
          <span className="theme-page-header__eyebrow">Identidade visual</span>
          <h1 className="page-title">{resolvedOwnerLabel}</h1>
          <p>{pageDescription}</p>
        </div>
        <div className="theme-page-header__actions">
          <span className={`theme-page-header__state${theme.stored ? " is-custom" : ""}`}>
            {headerStateLabel}
          </span>
          <Link className="btn btn--ghost btn--sm" to={resolvedBackUrl}>
            <ArrowLeft aria-hidden="true" size={16} /> Voltar
          </Link>
        </div>
      </header>

      {success ? <div className="toast toast--success" role="status">{success}</div> : null}
      {actionError ? <div className="toast toast--danger" role="alert">{actionError}</div> : null}
      {!theme.capabilities.can_edit && target === "user" ? (
        <div className="toast toast--warning" role="status">Você tem acesso somente para consulta.</div>
      ) : null}

      <div className={`theme-workspace${target === "organization" ? " has-organization-scope" : ""}${target === "billing" ? " has-billing-scope" : ""}`}>
        {target === "organization" ? (
          <section
            aria-label="Alcance do tema da organização"
            className="theme-organization-scope"
          >
            <div className="theme-organization-scope__identity">
              <span className="theme-organization-scope__icon">
                <Building2 aria-hidden="true" size={19} />
              </span>
              <div>
                <h2>Padrão visual da organização</h2>
                <p>{theme.owner_name}</p>
              </div>
            </div>
            <dl className="theme-organization-scope__facts">
              <div>
                <dt>Aplicação</dt>
                <dd>Cobranças sem tema próprio</dd>
              </div>
              <div>
                <dt>Base ativa</dt>
                <dd>{theme.effective_source === "organization" ? "Personalizado aqui" : "Padrão Rentivo"}</dd>
              </div>
              <div>
                <dt>Seu acesso</dt>
                <dd>{theme.capabilities.can_edit ? "Edição permitida" : "Somente consulta"}</dd>
              </div>
            </dl>
          </section>
        ) : null}
        {target === "billing" ? (
          <section
            aria-label="Alcance do tema da cobrança"
            className="theme-billing-scope"
          >
            <div className="theme-billing-scope__identity">
              <span className="theme-billing-scope__icon">
                <FileText aria-hidden="true" size={19} />
              </span>
              <div>
                <h2>Identidade desta cobrança</h2>
                <p>{theme.owner_name}</p>
                <span>{theme.capabilities.can_edit ? "Edição permitida" : "Somente consulta"}</span>
              </div>
            </div>
            <dl className="theme-billing-scope__facts">
              <div>
                <dt>Alcance</dt>
                <dd>Somente esta cobrança</dd>
              </div>
              <div>
                <dt>Fonte ativa</dt>
                <dd>{billingSourceLabel}</dd>
              </div>
              <div>
                <dt>Ao salvar</dt>
                <dd>{theme.stored
                  ? "Atualiza a personalização exclusiva"
                  : "Cria uma personalização exclusiva"}</dd>
              </div>
            </dl>
          </section>
        ) : null}
        <section aria-label="Personalização do tema" className="theme-controls">
          <form id="theme-form" onSubmit={(event) => void saveTheme(event)}>
            <div className="theme-controls__intro">
              <div>
                <h2>{controlsTitle}</h2>
                <p>{controlsDescription}</p>
              </div>
              <span aria-live="polite" className={`theme-draft-state${isDirty ? " is-dirty" : ""}`}>
                {isDirty ? "Alterações não salvas" : "Tema sincronizado"}
              </span>
            </div>

            <section aria-labelledby="theme-fonts-title" className="theme-control-section">
              <div className="theme-control-section__heading">
                <Type aria-hidden="true" size={19} />
                <div>
                  <h3 id="theme-fonts-title">Tipografia</h3>
                  <p>Defina a hierarquia entre títulos e conteúdo.</p>
                </div>
              </div>
              <div className="theme-font-grid">
                  <div className="field mb-0">
                    <label className="field-label" htmlFor="header_font">Fonte do Cabeçalho</label>
                    <select
                      aria-describedby={fieldErrorId(fieldErrors, "header_font")}
                      autoComplete="off"
                      className="field-select theme-select"
                      disabled={!theme.capabilities.can_edit}
                      id="header_font"
                      name="header_font"
                      onChange={(event: ChangeEvent<HTMLSelectElement>) => updateValue(
                        "header_font",
                        event.target.value as ThemeValues["header_font"]
                      )}
                      value={values.header_font}
                    >
                      {theme.options.fonts.map((font) => <option key={font} value={font}>{font}</option>)}
                    </select>
                    <FieldError id="header_font-error" message={fieldErrors.header_font} />
                  </div>
                  <div className="field mb-0">
                    <label className="field-label" htmlFor="text_font">Fonte do Texto</label>
                    <select
                      aria-describedby={fieldErrorId(fieldErrors, "text_font")}
                      autoComplete="off"
                      className="field-select theme-select"
                      disabled={!theme.capabilities.can_edit}
                      id="text_font"
                      name="text_font"
                      onChange={(event: ChangeEvent<HTMLSelectElement>) => updateValue(
                        "text_font",
                        event.target.value as ThemeValues["text_font"]
                      )}
                      value={values.text_font}
                    >
                      {theme.options.fonts.map((font) => <option key={font} value={font}>{font}</option>)}
                    </select>
                    <FieldError id="text_font-error" message={fieldErrors.text_font} />
                  </div>
              </div>
            </section>

            <section aria-labelledby="theme-colors-title" className="theme-control-section">
              <div className="theme-control-section__heading">
                <Palette aria-hidden="true" size={19} />
                <div>
                  <h3 id="theme-colors-title">Paleta</h3>
                  <p>Use as cores da sua marca sem perder legibilidade.</p>
                </div>
              </div>
                <div className="theme-color-list">
                  {COLOR_FIELDS.map(({ hint, key, label }) => (
                    <div className="theme-color-field" key={key}>
                      <input
                        aria-describedby={`${key}-hint${fieldErrors[key] ? ` ${key}-error` : ""}`}
                        aria-label={label}
                        className="theme-color-input"
                        disabled={!theme.capabilities.can_edit}
                        id={key}
                        name={key}
                        onChange={(event) => updateValue(key, event.target.value)}
                        type="color"
                        value={values[key]}
                      />
                      <label className="theme-color-field__copy" htmlFor={key}>
                        <strong>{label}</strong>
                        <span id={`${key}-hint`}>{hint}</span>
                      </label>
                      <output className="theme-color-field__value" htmlFor={key}>{values[key].toUpperCase()}</output>
                      <FieldError id={`${key}-error`} message={fieldErrors[key]} />
                    </div>
                  ))}
              </div>
              <div className={`theme-contrast${ratio < 4.5 ? " is-warning" : ""}`}>
                <span className="theme-contrast__icon">
                  {ratio < 4.5
                    ? <TriangleAlert aria-hidden="true" size={15} />
                    : <Check aria-hidden="true" size={15} />}
                </span>
                <div>
                  <strong>{ratio < 4.5 ? "Contraste insuficiente" : "Contraste aprovado"}</strong>
                  <span>
                    {ratio < 4.5
                      ? "O contraste entre a cor primária e o texto está abaixo de 4,5:1."
                      : `${ratio.toLocaleString("pt-BR", { maximumFractionDigits: 1, minimumFractionDigits: 1 })}:1 entre a cor primária e o texto.`}
                  </span>
                </div>
              </div>
            </section>

            <div className="theme-controls__footer">
              <button
                className="btn btn--primary"
                disabled={!theme.capabilities.can_edit || saving}
                type="submit"
              >
                <Save aria-hidden="true" size={16} /> {saving
                  ? "Salvando…"
                  : target === "billing"
                    ? "Salvar na cobrança"
                    : "Salvar"}
              </button>
              {theme.capabilities.can_reset ? (
                <button
                  className="btn btn--ghost btn--sm theme-reset-button"
                  disabled={resetting}
                  onClick={() => setResetOpen(true)}
                  type="button"
                >
                  <RotateCcw aria-hidden="true" size={15} /> {target === "billing"
                    ? "Remover personalização"
                    : "Usar Padrão"}
                </button>
              ) : null}
            </div>
          </form>
        </section>

        <section aria-label="Prévia da fatura" className="theme-preview">
          <div className="theme-preview__header">
            <h2><FileText aria-hidden="true" size={18} /> Prévia da fatura</h2>
            <div className="theme-preview__actions">
              <span aria-live="polite" className={`theme-preview__status${previewStale ? " is-stale" : ""}`}>
                {previewStatus}
              </span>
              <button className="btn btn--sm" onClick={previewNow} type="button">
                <Eye aria-hidden="true" size={15} /> Visualizar
              </button>
            </div>
          </div>

          <div
            aria-label="Amostra local do tema"
            className="theme-local-preview"
            style={{
              backgroundColor: values.primary_light,
              color: values.text_color,
              fontFamily: values.text_font
            }}
          >
            <div
              className="theme-local-preview__brand"
              style={{
                backgroundColor: values.primary,
                color: values.text_contrast,
                fontFamily: values.header_font
              }}
            >
              <span>{target === "user" ? "Rentivo" : theme.owner_name}</span>
              <strong>Fatura de aluguel</strong>
            </div>
            <div className="theme-local-preview__content">
              <span>Exemplo de cobrança</span>
              <strong style={{ fontFamily: values.header_font }}>R$ 2.450,00</strong>
              <small>Vencimento em 10 de setembro</small>
            </div>
            <span
              className="theme-local-preview__tag"
              style={{ backgroundColor: values.secondary_dark, color: values.text_contrast }}
            >
              Em aberto
            </span>
          </div>

          <div className={`theme-pdf-stage${scopedPdfIdle ? " is-idle" : ""}`}>
            {scopedPdfIdle ? (
              <div className="theme-pdf-idle">
                <FileText aria-hidden="true" size={24} />
                <strong>PDF completo sob demanda</strong>
                <span>Gere o documento para conferir margens, tipografia e paginação.</span>
              </div>
            ) : null}
            {!scopedPdfIdle && !previewUrl && !previewError ? (
              <div className="theme-pdf-skeleton" aria-hidden="true" />
            ) : null}
            {previewUrl ? (
              <iframe
                className="theme-pdf-frame"
                src={previewUrl || undefined}
                title="Pré-visualização do tema"
              />
            ) : null}
          </div>

          {previewError ? <div className="theme-preview__error" role="alert">{previewError}</div> : null}
        </section>
      </div>

      <ConfirmDialog
        acceptLabel={target === "billing" ? "Remover personalização" : "Usar padrão"}
        body={target === "billing"
          ? "A cobrança voltará a seguir o tema do proprietário ou o padrão Rentivo."
          : "Tem certeza que deseja restaurar o tema padrão?"}
        onClose={() => setResetOpen(false)}
        onConfirm={() => void resetTheme()}
        open={resetOpen}
        title={target === "billing" ? "Remover personalização da cobrança?" : "Restaurar o tema padrão?"}
      />
    </>
  );
}
