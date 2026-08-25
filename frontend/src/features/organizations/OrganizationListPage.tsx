import { ArrowRight, Building2, LockKeyhole, Plus, ShieldCheck, UsersRound } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router";

import { LoadError } from "../../components/PageState";
import { ApiError, apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { useDocumentTitle } from "../../lib/useDocumentTitle";

type Organization = components["schemas"]["OrganizationResponse"];

const ROLE_LABELS: Record<Organization["current_role"], string> = {
  admin: "Administrador",
  manager: "Gerente",
  viewer: "Visualizador"
};

function accessLabel(organization: Organization): string {
  if (organization.capabilities.can_manage) return "Acesso completo";
  if (organization.capabilities.can_create_billing) return "Gerencia cobranças";
  return "Somente leitura";
}

function organizationCount(count: number): string {
  return `${new Intl.NumberFormat("pt-BR").format(count)} ${count === 1 ? "organização" : "organizações"}`;
}

function messageFor(error: unknown): string {
  return error instanceof ApiError
    ? error.message
    : "Não foi possível carregar as organizações.";
}

export function OrganizationListPage() {
  const [organizations, setOrganizations] = useState<Organization[] | null>(null);
  const [error, setError] = useState("");

  const load = useCallback(async (signal?: AbortSignal) => {
    setError("");
    try {
      const { data } = await apiRequest(apiClient.GET("/api/v1/organizations", { signal }));
      if (!signal?.aborted) setOrganizations(data.items);
    } catch (caught) {
      if (!signal?.aborted) setError(messageFor(caught));
    }
  }, []);

  useDocumentTitle("Organizações - Rentivo");
  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  return (
    <div className="organization-index">
      <div className="pagehead organization-index__pagehead">
        <div className="organization-index__heading">
          <h1 className="pagehead__title">Organizações</h1>
          <p className="pagehead__sub">Escolha um espaço de trabalho ou reúna sua operação com outras pessoas.</p>
        </div>
        {organizations?.length ? (
          <Link className="btn btn--primary" to="/organizations/create">
            <Plus aria-hidden="true" size={17} />
            Criar organização
          </Link>
        ) : null}
      </div>

      {error ? (
        <section aria-label="Falha ao carregar organizações" className="organization-index__state">
          <LoadError message={error} onRetry={() => void load()} />
        </section>
      ) : !organizations ? (
        <section aria-live="polite" className="organization-index__state organization-index__loading" role="status">
          <div aria-hidden="true" className="organization-index__skeleton-mark" />
          <div aria-hidden="true" className="organization-index__skeleton-lines">
            <span />
            <span />
          </div>
          <p>Carregando organizações…</p>
        </section>
      ) : organizations.length ? (
        <section aria-labelledby="organization-directory-title" className="organization-directory">
          <header className="organization-directory__header">
            <div>
              <h2 id="organization-directory-title">Seus espaços de trabalho</h2>
              <p>Veja seu papel e o nível de acesso antes de entrar.</p>
            </div>
            <strong>{organizationCount(organizations.length)}</strong>
          </header>
          <div className="organization-directory__list">
            {organizations.map((organization) => (
              <Link className="organization-directory__row" key={organization.uuid} to={`/organizations/${organization.uuid}`}>
                <span aria-hidden="true" className="organization-directory__mark">
                  {organization.name.slice(0, 1).toLocaleUpperCase("pt-BR")}
                </span>
                <span className="organization-directory__identity">
                  <strong className="organization-directory__name" title={organization.name}>{organization.name}</strong>
                </span>
                <span className="organization-directory__meta organization-directory__meta--role">
                  <small>Seu papel</small>
                  <strong>{ROLE_LABELS[organization.current_role]}</strong>
                </span>
                <span className="organization-directory__meta organization-directory__meta--access">
                  <small>Permissões</small>
                  <strong>{accessLabel(organization)}</strong>
                </span>
                <span className="organization-directory__security">
                  <LockKeyhole aria-hidden="true" size={15} />
                  {organization.enforce_mfa ? "MFA exigido" : "MFA opcional"}
                </span>
                <span aria-hidden="true" className="organization-directory__open">
                  <ArrowRight size={19} />
                </span>
              </Link>
            ))}
          </div>
        </section>
      ) : (
        <section className="organization-index__empty">
          <div className="organization-index__empty-intro">
            <span aria-hidden="true" className="organization-index__empty-mark">
              <Building2 size={28} strokeWidth={2.2} />
            </span>
            <h2>Organize sua operação em equipe</h2>
            <p>Uma organização reúne imóveis, cobranças e pessoas em um espaço com permissões próprias.</p>
            <Link className="btn btn--primary" to="/organizations/create">
              <Plus aria-hidden="true" size={17} />
              Criar organização
            </Link>
          </div>
          <div aria-label="O que você pode organizar" className="organization-index__empty-guide">
            <div>
              <Building2 aria-hidden="true" size={19} />
              <span><strong>Imóveis e cobranças</strong><small>Mantenha a operação do time no mesmo lugar.</small></span>
            </div>
            <div>
              <UsersRound aria-hidden="true" size={19} />
              <span><strong>Pessoas e papéis</strong><small>Defina quem administra, gerencia ou apenas visualiza.</small></span>
            </div>
            <div>
              <ShieldCheck aria-hidden="true" size={19} />
              <span><strong>Segurança compartilhada</strong><small>Exija MFA para proteger o acesso da equipe.</small></span>
            </div>
          </div>
        </section>
      )}
    </div>
  );
}
