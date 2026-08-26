import { Building2, CheckCircle2, ChevronLeft, PencilLine, QrCode, ShieldCheck } from "lucide-react";
import { useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router";

import { LoadError } from "../../components/PageState";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import { errorMessage, normalizedFieldErrors } from "../../lib/api/errors";
import type { components } from "../../lib/api/schema";
import { useDocumentTitle } from "../../lib/useDocumentTitle";
import { pushAnalyticsFromResponse } from "../auth/analytics";
import { OrganizationForm, type OrganizationValues } from "./OrganizationForm";
import "./OrganizationEditPage.css";

type Detail = components["schemas"]["OrganizationLoginDetailResponse"];
const ORGANIZATION_FIELDS = ["name", "pix_key", "pix_merchant_city", "pix_merchant_name"] as const;

function valuesFor(detail: Detail): OrganizationValues {
  return {
    name: detail.name,
    pix_key: detail.settings?.pix_key ?? "",
    pix_merchant_city: detail.settings?.pix_merchant_city ?? "",
    pix_merchant_name: detail.settings?.pix_merchant_name ?? ""
  };
}

function hasPixConfiguration(values: OrganizationValues) {
  return Boolean(values.pix_key && values.pix_merchant_city && values.pix_merchant_name);
}

interface OrganizationEditFrameProps {
  children: ReactNode;
  crumbLabel?: string;
  crumbUrl?: string;
}

function OrganizationEditFrame({
  children,
  crumbLabel = "Organizações",
  crumbUrl = "/organizations/"
}: OrganizationEditFrameProps) {
  return (
    <div className="organization-edit-page">
      <Link className="crumb" to={crumbUrl}>
        <ChevronLeft aria-hidden="true" size={16} strokeWidth={2.5} />
        {crumbLabel}
      </Link>
      <header className="pagehead organization-edit-page__head">
        <div>
          <h1 className="pagehead__title">Editar Organização</h1>
          <p className="pagehead__sub">Mantenha a identificação e o recebimento da organização em um único lugar.</p>
        </div>
      </header>
      {children}
    </div>
  );
}

export function OrganizationEditPage() {
  const { orgUuid = "" } = useParams<{ orgUuid: string }>();
  const navigate = useNavigate();
  const [detail, setDetail] = useState<Detail | null>(null);
  const [loadError, setLoadError] = useState("");
  const [error, setError] = useState("");
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [draftValues, setDraftValues] = useState<Partial<OrganizationValues>>({});
  const generationRef = useRef(0);
  const saveRef = useRef<AbortController | null>(null);

  const load = useCallback(async (signal?: AbortSignal, generation = generationRef.current) => {
    setLoadError("");
    try {
      const { data } = await apiRequest(apiClient.GET("/api/v1/organizations/{organization_uuid}", {
        params: { path: { organization_uuid: orgUuid } },
        signal
      }));
      if (!signal?.aborted && generation === generationRef.current) setDetail(data as Detail);
    } catch (caught) {
      if (!signal?.aborted && generation === generationRef.current) {
        setLoadError(errorMessage(caught, "Não foi possível carregar a organização."));
      }
    }
  }, [orgUuid]);

  useEffect(() => {
    const generation = ++generationRef.current;
    const controller = new AbortController();
    saveRef.current?.abort();
    saveRef.current = null;
    setDetail(null);
    setError("");
    setFieldErrors({});
    setSaving(false);
    setDraftValues({});
    void load(controller.signal, generation);
    return () => controller.abort();
  }, [load]);
  useEffect(() => () => {
    generationRef.current += 1;
    saveRef.current?.abort();
    saveRef.current = null;
  }, []);
  useDocumentTitle(detail ? `Editar ${detail.name} - Rentivo` : "Editar Organização - Rentivo");

  const submit = async (values: OrganizationValues) => {
    if (saveRef.current) return;
    const controller = new AbortController();
    const generation = generationRef.current;
    saveRef.current = controller;
    setSaving(true);
    setError("");
    setFieldErrors({});
    try {
      const { response } = await apiRequest(apiClient.PATCH("/api/v1/organizations/{organization_uuid}", {
        body: {
          name: values.name.trim(),
          pix_key: values.pix_key.trim(),
          pix_merchant_city: values.pix_merchant_city.trim(),
          pix_merchant_name: values.pix_merchant_name.trim()
        },
        params: { path: { organization_uuid: orgUuid } },
        signal: controller.signal
      }));
      if (controller.signal.aborted || generation !== generationRef.current) return;
      pushAnalyticsFromResponse(response);
      navigate(`/organizations/${orgUuid}`);
    } catch (caught) {
      if (controller.signal.aborted || generation !== generationRef.current) return;
      if (caught instanceof ApiError) {
        setError(Object.keys(caught.fields).length ? "" : caught.message);
        setFieldErrors(normalizedFieldErrors(caught));
      } else {
        setError("Não foi possível atualizar a organização.");
      }
    } finally {
      if (saveRef.current === controller) {
        saveRef.current = null;
        setSaving(false);
      }
    }
  };

  if (loadError) {
    return <OrganizationEditFrame><div className="organization-edit-state"><LoadError message={loadError} onRetry={() => void load()} /></div></OrganizationEditFrame>;
  }
  if (!detail || detail.uuid !== orgUuid) {
    return (
      <OrganizationEditFrame>
        <div aria-label="Carregando organização…" aria-live="polite" className="organization-edit-state organization-edit-state--loading" role="status">
          <p>Carregando organização…</p>
          <div aria-hidden="true" className="organization-edit-skeleton">
            <span className="organization-edit-skeleton__wide" />
            <span />
            <span className="organization-edit-skeleton__wide" />
            <span />
            <span />
          </div>
        </div>
      </OrganizationEditFrame>
    );
  }
  if (!detail.capabilities.can_manage) {
    return <OrganizationEditFrame crumbLabel={detail.name} crumbUrl={`/organizations/${orgUuid}`}><div className="organization-edit-state"><div className="toast toast--warning" role="alert">Você não tem permissão para editar esta organização.</div></div></OrganizationEditFrame>;
  }

  const initialValues = valuesFor(detail);
  const currentValues = { ...initialValues, ...draftValues };
  const formDirty = ORGANIZATION_FIELDS.some((field) => currentValues[field] !== initialValues[field]);
  const pixConfigured = hasPixConfiguration(currentValues);
  const captureDraft = (event: FormEvent<HTMLDivElement>) => {
    const input = event.target;
    if (!(input instanceof HTMLInputElement) || !ORGANIZATION_FIELDS.includes(input.id as typeof ORGANIZATION_FIELDS[number])) return;
    const field = input.id as typeof ORGANIZATION_FIELDS[number];
    setDraftValues((current) => ({ ...current, [field]: input.value }));
  };

  return (
    <OrganizationEditFrame crumbLabel={detail.name} crumbUrl={`/organizations/${orgUuid}`}>
      <section aria-label="Configurações da organização" className="organization-edit-workspace">
        <div className="organization-edit-workspace__form" onChange={captureDraft}>
          <OrganizationForm error={error} fieldErrors={fieldErrors} key={detail.uuid} mode="edit" onSubmit={(values) => void submit(values)} organizationUuid={orgUuid} saving={saving} values={valuesFor(detail)} />
        </div>

        <aside aria-label="Resumo da configuração" className="organization-edit-summary">
          <div className="organization-edit-summary__mark">
            <Building2 aria-hidden="true" size={24} strokeWidth={2.25} />
          </div>
          <div>
            <h2>Resumo da configuração</h2>
            <p>As alterações valem para novas cobranças e para os próximos documentos gerados.</p>
          </div>

          <div className="organization-edit-summary__status">
            {formDirty ? <PencilLine aria-hidden="true" size={21} strokeWidth={2.25} /> : <CheckCircle2 aria-hidden="true" size={21} strokeWidth={2.25} />}
            <div aria-live="polite">
              <strong>{formDirty ? "Alterações pendentes" : "Sem alterações pendentes"}</strong>
              <span>{formDirty ? "Salve para aplicar o rascunho à organização." : "Os dados exibidos já estão salvos."}</span>
            </div>
          </div>

          <div className="organization-edit-summary__status">
            <QrCode aria-hidden="true" size={21} strokeWidth={2.25} />
            <div>
              <strong>{pixConfigured ? "PIX configurado" : "PIX pendente"}</strong>
              <span>{pixConfigured ? "QR Code disponível para as próximas faturas." : "Preencha os 3 campos de recebimento para emitir faturas com QR Code."}</span>
            </div>
          </div>

          <div className="organization-edit-summary__guidance">
            <ShieldCheck aria-hidden="true" size={20} strokeWidth={2.25} />
            <div>
              <strong>Antes de salvar</strong>
              <ul>
                <li>Use um nome reconhecível pela equipe.</li>
                <li>Confira a chave PIX antes de emitir uma fatura.</li>
                <li>Digite nome e cidade normalmente; o PIX ajusta maiúsculas e acentos.</li>
              </ul>
            </div>
          </div>
        </aside>
      </section>
    </OrganizationEditFrame>
  );
}
