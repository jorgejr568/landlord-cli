import {
  ArrowRight,
  KeyRound,
  LifeBuoy,
  Mail,
  ReceiptText,
  ShieldCheck
} from "lucide-react";
import { useEffect, type ComponentType } from "react";
import { Link } from "react-router";

import "./SupportPage.css";

type SupportPath = {
  action: string;
  description: string;
  icon: ComponentType<{ "aria-hidden": true; size: number; strokeWidth: number }>;
  title: string;
  to: string;
};

const supportPaths: SupportPath[] = [
  {
    action: "Redefinir senha",
    description: "Solicite um novo link se a senha ou o acesso à conta não funcionarem.",
    icon: KeyRound,
    title: "Acesso à conta",
    to: "/forgot-password"
  },
  {
    action: "Entrar no Rentivo",
    description: "Acesse sua conta para revisar cobranças, faturas, recibos e envios.",
    icon: ReceiptText,
    title: "Cobranças e faturas",
    to: "/login"
  },
  {
    action: "Ver privacidade",
    description: "Entenda quais dados usamos e como solicitar acesso, correção ou exclusão.",
    icon: ShieldCheck,
    title: "Privacidade e dados",
    to: "/privacy"
  }
];

export function SupportPage() {
  useEffect(() => {
    document.title = "Suporte - Rentivo";
  }, []);

  return (
    <article aria-labelledby="support-title" className="support-page">
      <a className="support-page__skip-link" href="#support-content">
        Pular para o suporte
      </a>

      <nav aria-label="Navegação institucional" className="support-page__topbar">
        <Link
          aria-label="Rentivo, página inicial"
          className="support-page__brand"
          to="/"
          translate="no"
        >
          <span aria-hidden="true" className="support-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </Link>
        <Link className="support-page__back-link" to="/">Voltar ao início</Link>
      </nav>

      <div className="support-page__workspace" id="support-content" tabIndex={-1}>
        <header className="support-page__hero">
          <div className="support-page__intro">
            <p className="support-page__eyebrow">Central de ajuda</p>
            <h1 id="support-title">Como podemos ajudar?</h1>
            <p className="support-page__lede">
              Escolha o assunto para resolver agora ou fale diretamente com o suporte.
            </p>
          </div>

          <aside aria-labelledby="direct-support-title" className="support-page__contact">
            <Mail aria-hidden="true" size={24} strokeWidth={2.2} />
            <div>
              <h2 id="direct-support-title">Fale com a gente</h2>
              <p>
                Escreva para{" "}
                <a href="mailto:suporte@rentivo.com.br">suporte@rentivo.com.br</a>.
              </p>
              <p className="support-page__response-time">
                Respondemos em até 2 dias úteis.
              </p>
            </div>
            <a
              className="btn btn--primary support-page__contact-action"
              href="mailto:suporte@rentivo.com.br"
            >
              Enviar e-mail ao suporte
              <ArrowRight aria-hidden="true" size={17} strokeWidth={2.2} />
            </a>
            <p className="support-page__contact-note">
              Inclua o e-mail da conta e um resumo do que aconteceu.
            </p>
          </aside>
        </header>

        <section aria-labelledby="support-paths-title" className="support-page__paths">
          <div className="support-page__paths-intro">
            <h2 id="support-paths-title">Encontre o caminho mais rápido</h2>
            <p>Use uma opção de autoatendimento antes de nos escrever.</p>
          </div>

          <ul className="support-page__path-list">
            {supportPaths.map(({ action, description, icon: Icon, title, to }) => (
              <li key={to}>
                <Link className="support-page__path" to={to}>
                  <span aria-hidden="true" className="support-page__path-icon">
                    <Icon aria-hidden={true} size={22} strokeWidth={2.1} />
                  </span>
                  <span className="support-page__path-copy">
                    <strong>{title}</strong>
                    <span>{description}</span>
                  </span>
                  <span className="support-page__path-action">
                    {action}
                    <ArrowRight aria-hidden="true" size={17} strokeWidth={2.2} />
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </section>

        <footer className="support-page__legal">
          <LifeBuoy aria-hidden="true" size={22} strokeWidth={2.1} />
          <p>
            O uso do Rentivo também é regido pelos{" "}
            <Link to="/terms">Termos de Uso</Link>.
          </p>
        </footer>
      </div>
    </article>
  );
}
