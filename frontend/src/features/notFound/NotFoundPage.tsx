import { ArrowLeft, ArrowRight, Building2, HousePlus, MapPinOff } from "lucide-react";
import { Link, useLocation, useNavigate } from "react-router";

import { useDocumentTitle } from "../../lib/useDocumentTitle";
import "./NotFoundPage.css";

export function NotFoundPage() {
  const location = useLocation();
  const navigate = useNavigate();

  useDocumentTitle("Página não encontrada - Rentivo");

  return (
    <section aria-labelledby="not-found-title" className="not-found-page">
      <div aria-hidden="true" className="not-found-page__signal">
        <span>Rota não encontrada</span>
        <strong>404</strong>
        <i />
      </div>

      <div className="not-found-page__content">
        <MapPinOff aria-hidden="true" className="not-found-page__icon" size={38} strokeWidth={2.1} />
        <h1 id="not-found-title">Esta página não está no mapa</h1>
        <p>O endereço pode estar incompleto, ter mudado ou não fazer mais parte da Rentivo.</p>

        <div aria-label="Endereço não encontrado" className="not-found-page__route">
          <span>Endereço solicitado</span>
          <code>{location.pathname}</code>
        </div>

        <div className="not-found-page__actions">
          <Link className="btn btn--primary" to="/billings/">
            Minhas cobranças
            <ArrowRight aria-hidden="true" size={17} strokeWidth={2.5} />
          </Link>
          <button className="btn" onClick={() => navigate(-1)} type="button">
            <ArrowLeft aria-hidden="true" size={17} strokeWidth={2.5} />
            Voltar
          </button>
        </div>
      </div>

      <nav aria-label="Atalhos de recuperação" className="not-found-page__shortcuts">
        <span>Outros caminhos</span>
        <Link to="/billings/create">
          <HousePlus aria-hidden="true" size={18} strokeWidth={2.25} />
          Nova cobrança
        </Link>
        <Link to="/organizations/">
          <Building2 aria-hidden="true" size={18} strokeWidth={2.25} />
          Organizações
        </Link>
      </nav>
    </section>
  );
}
