import { useCallback, useEffect, useState } from "react";
import {
  AlertTriangle,
  ArrowRight,
  Building2,
  ChevronRight,
  CircleDollarSign,
  FileCheck2,
  HousePlus,
  Plus,
  ReceiptText
} from "lucide-react";
import { Link } from "react-router";

import { LoadError } from "../../components/PageState";
import { apiClient, apiRequest } from "../../lib/api/client";
import type { components } from "../../lib/api/schema";
import { formatBrl } from "../../lib/format";
import { useDocumentTitle } from "../../lib/useDocumentTitle";

type BillingList = components["schemas"]["BillingListResponse"];
type BillingListItem = BillingList["items"][number];
type Stats = components["schemas"]["BillingStatsResponse"];

const STATUS_LABELS: Record<string, string> = {
  cancelled: "Cancelado",
  delayed_payment: "Pag. Atrasado",
  draft: "Rascunho",
  paid: "Pago",
  published: "Publicado",
  sent: "Enviado"
};

function plural(count: number, singular: string, pluralValue: string): string {
  return count === 1 ? singular : pluralValue;
}

function portfolioCount(count: number): string {
  if (count === 0) return "Nenhum imóvel em cobrança";
  return `${count} ${plural(count, "imóvel em cobrança", "imóveis em cobrança")}`;
}

function BillingListSkeleton() {
  return (
    <div aria-label="Carregando painel de cobranças" className="billing-overview billing-overview--loading" role="status">
      <div className="billing-overview__skeleton-head">
        <span className="skeleton-block skeleton-block--title" />
        <span className="skeleton-block skeleton-block--button" />
      </div>
      <span className="billing-overview__loading-label">Carregando cobranças...</span>
      <div className="billing-overview__skeleton-summary">
        <span className="skeleton-block skeleton-block--metric" />
        <span className="skeleton-block skeleton-block--metric" />
        <span className="skeleton-block skeleton-block--metric-small" />
      </div>
    </div>
  );
}

function FinancialSummary({ stats }: { stats: Stats }) {
  const metrics = [
    {
      className: "billing-overview__metric--expected",
      label: `Faturado em ${stats.year}`,
      meta: `${stats.billed_count} ${plural(stats.billed_count, "fatura no ano", "faturas no ano")}`,
      value: formatBrl(stats.expected)
    },
    {
      className: "billing-overview__metric--received",
      label: `Recebido em ${stats.year}`,
      meta: `${stats.paid_count} ${plural(stats.paid_count, "fatura paga", "faturas pagas")}`,
      value: formatBrl(stats.received)
    },
    {
      className: "billing-overview__metric--pending",
      label: "A receber",
      meta: `${stats.pending_count} ${plural(stats.pending_count, "pendente", "pendentes")}`,
      value: formatBrl(stats.pending)
    },
    {
      className: "billing-overview__metric--overdue",
      label: "Em atraso",
      meta: `${stats.overdue_count} ${plural(stats.overdue_count, "vencida", "vencidas")}`,
      value: formatBrl(stats.overdue)
    }
  ];

  return (
    <section aria-label={`Resumo financeiro de ${stats.year}`} className="billing-overview__summary">
      <div className="billing-overview__summary-title">
        <CircleDollarSign aria-hidden="true" size={22} strokeWidth={2.25} />
        <div><strong>Resumo do ano</strong><span>Valores das faturas emitidas</span></div>
      </div>
      <dl className="billing-overview__metrics">
        {metrics.map((metric) => (
          <div className={`billing-overview__metric ${metric.className}`} key={metric.label}>
            <dt>{metric.label}</dt>
            <dd className="mono">{metric.value}</dd>
            <span>{metric.meta}</span>
          </div>
        ))}
      </dl>
    </section>
  );
}

function StatusTag({ status }: { status: string }) {
  return <span className={`tag tag--${status === "delayed_payment" ? "delayed" : status}`}>{STATUS_LABELS[status]}</span>;
}

function SetupNotice({ needsPix, userPixIncomplete }: { needsPix: BillingListItem[]; userPixIncomplete: boolean }) {
  if (!userPixIncomplete && needsPix.length === 0) return null;
  return (
    <section aria-label="Pendências de configuração" className="billing-overview__setup">
      <div className="billing-overview__setup-heading">
        <AlertTriangle aria-hidden="true" size={21} strokeWidth={2.4} />
        <div><h2>Pendências de configuração</h2><p>Resolva estes itens antes de emitir as próximas faturas.</p></div>
      </div>
      <div className="billing-overview__setup-items">
        {userPixIncomplete ? (
          <div className="billing-overview__setup-item">
            <div><strong>PIX da conta pendente</strong><span>Adicione o recebedor padrão das suas cobranças pessoais.</span></div>
            <Link className="btn btn--sm" to="/security">Configurar PIX</Link>
          </div>
        ) : null}
        {needsPix.length ? (
          <div className="billing-overview__setup-item">
            <div>
              <strong>{needsPix.length} {plural(needsPix.length, "cobrança sem dados de recebimento", "cobranças sem dados de recebimento")}</strong>
              <span>{userPixIncomplete ? "Defina o recebedor na conta, na organização ou em cada cobrança." : "Defina o recebedor no proprietário ou em cada cobrança."}</span>
              <div className="billing-overview__setup-links">
                {needsPix.map((billing) => <Link key={billing.uuid} to={`/billings/${billing.uuid}`}>{billing.name}</Link>)}
              </div>
            </div>
          </div>
        ) : null}
      </div>
    </section>
  );
}

function EmptyPortfolio() {
  const nextSteps = [
    { icon: HousePlus, text: "Cadastre o imóvel e identifique o inquilino.", title: "Organize a cobrança" },
    { icon: ReceiptText, text: "Defina aluguel, taxas e itens variáveis.", title: "Monte o modelo mensal" },
    { icon: FileCheck2, text: "Gere a fatura, envie e acompanhe o pagamento.", title: "Acompanhe até receber" }
  ];
  return (
    <section aria-labelledby="billing-empty-title" className="billing-overview__empty">
      <div className="billing-overview__empty-copy">
        <span className="billing-overview__empty-icon"><Building2 aria-hidden="true" size={31} strokeWidth={2.1} /></span>
        <h2 id="billing-empty-title">Cadastre seu primeiro imóvel</h2>
        <p>Crie a cobrança recorrente uma vez. A partir dela, cada fatura mensal fica pronta para revisar e enviar.</p>
        <Link className="btn btn--primary btn--lg" to="/billings/create">Cadastrar imóvel <ArrowRight aria-hidden="true" size={18} strokeWidth={2.5} /></Link>
      </div>
      <div className="billing-overview__journey">
        <h3>Da configuração ao recebimento</h3>
        <ol>
          {nextSteps.map(({ icon: Icon, text, title }) => (
            <li key={title}>
              <Icon aria-hidden="true" size={21} strokeWidth={2.2} />
              <div><strong>{title}</strong><span>{text}</span></div>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

function BillingLedger({ items }: { items: BillingListItem[] }) {
  return (
    <section aria-labelledby="billing-ledger-title" className="billing-overview__ledger">
      <div className="billing-overview__ledger-head">
        <div><h2 id="billing-ledger-title">Imóveis e cobranças</h2><p>Fatura mais recente de cada imóvel</p></div>
        <span>{items.length} {plural(items.length, "imóvel", "imóveis")}</span>
      </div>
      <div className="billing-overview__table-wrap">
        <table aria-label="Imóveis e faturas atuais" className="billing-overview__table">
          <thead><tr><th>Imóvel</th><th>Itens</th><th>Fatura atual</th><th>Status</th><th><span className="sr-only">Abrir</span></th></tr></thead>
          <tbody>
            {items.map((billing) => (
              <tr key={billing.uuid}>
                <td>
                  <div className="billing-overview__property">
                    <div><Link to={`/billings/${billing.uuid}`}>{billing.name}</Link>{billing.owner.type === "organization" ? <span className="tag tag--solid">Org</span> : null}</div>
                    {billing.description ? <span>{billing.description}</span> : null}
                    <span className="billing-overview__mobile-meta">{billing.item_count} {plural(billing.item_count, "item recorrente", "itens recorrentes")}</span>
                  </div>
                </td>
                <td className="billing-overview__items mono">{billing.item_count}</td>
                <td className="billing-overview__amount mono">{billing.current_bill ? formatBrl(billing.current_bill.total_amount) : <span>Não emitida</span>}</td>
                <td className="billing-overview__status">{billing.current_bill ? <StatusTag status={billing.current_bill.status} /> : <span className="tag tag--draft">Sem fatura</span>}</td>
                <td className="billing-overview__open"><Link aria-label={`Abrir ${billing.name}`} to={`/billings/${billing.uuid}`}><span>Abrir</span><ChevronRight aria-hidden="true" size={18} strokeWidth={2.5} /></Link></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export function BillingListPage() {
  const [payload, setPayload] = useState<BillingList | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(async (signal?: AbortSignal) => {
    setError("");
    try {
      const { data } = await apiRequest(apiClient.GET("/api/v1/billings", { signal }));
      if (!signal?.aborted) setPayload(data);
    } catch {
      if (!signal?.aborted) setError("Não foi possível carregar as cobranças.");
    }
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => { controller.abort(); };
  }, [load]);
  useDocumentTitle("Minhas Cobranças - Rentivo");

  if (error) return <LoadError message={error} onRetry={() => void load()} />;
  if (!payload) return <BillingListSkeleton />;
  const needsPix = payload.items.filter((billing) => billing.pix_needs_setup);
  const hasBillings = payload.items.length > 0;

  return (
    <div className="billing-overview">
      <header className="pagehead billing-overview__head">
        <div><h1 className="pagehead__title">Minhas Cobranças</h1><p className="pagehead__sub">{portfolioCount(payload.items.length)}</p></div>
        <div className="billing-overview__actions">
          <Link className="btn" to="/organizations/"><Building2 aria-hidden="true" size={17} strokeWidth={2.3} />Organizações</Link>
          {hasBillings ? <Link className="btn btn--primary" to="/billings/create"><Plus aria-hidden="true" size={17} strokeWidth={2.5} />Nova cobrança</Link> : null}
        </div>
      </header>
      <SetupNotice needsPix={needsPix} userPixIncomplete={payload.user_pix_incomplete} />
      {hasBillings ? <><FinancialSummary stats={payload.stats} /><BillingLedger items={payload.items} /></> : <EmptyPortfolio />}
    </div>
  );
}
