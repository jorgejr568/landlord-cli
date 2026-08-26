import {
  ArrowRight,
  Check,
  ClipboardList,
  FileCheck2,
  FileText,
  Paperclip,
  QrCode,
  ReceiptText,
  ShieldCheck,
  UsersRound
} from "lucide-react";

import { LandingMetadata } from "./LandingMetadata";
import "../../styles/landing.css";

function GitHubIcon({ size = 24 }: { size?: number }) {
  return (
    <svg
      aria-hidden="true"
      fill="currentColor"
      focusable="false"
      height={size}
      viewBox="0 0 24 24"
      width={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12" />
    </svg>
  );
}

const workflow = [
  {
    copy: "Defina o que se repete, o que varia e qual chave PIX recebe o pagamento.",
    heading: "Configure",
    Icon: ClipboardList
  },
  {
    copy: "Preencha os valores do mês e gere o PDF com vencimento e QR Code PIX.",
    heading: "Gere",
    Icon: FileCheck2
  },
  {
    copy: "Envie a fatura, atualize o status e guarde o comprovante no histórico.",
    heading: "Acompanhe",
    Icon: ReceiptText
  }
] as const;

const capabilities = [
  {
    copy: "Combine aluguel e condomínio fixos com água e luz variáveis. Reuse o modelo no mês seguinte.",
    heading: "Cobranças flexíveis",
    Icon: ClipboardList
  },
  {
    copy: "Entregue um documento organizado, com itens detalhados, vencimento e total formatado em reais.",
    heading: "Faturas em PDF",
    Icon: FileText
  },
  {
    copy: "Inclua um QR Code PIX gerado no padrão EMV para o inquilino pagar sem digitar os dados.",
    heading: "PIX com QR Code",
    Icon: QrCode
  },
  {
    copy: "Divida a operação entre admins, gestores e visualizadores com permissões próprias.",
    heading: "Organizações",
    Icon: UsersRound
  },
  {
    copy: "Anexe arquivos PDF, JPG ou PNG. O comprovante pode acompanhar a fatura final.",
    heading: "Comprovantes",
    Icon: Paperclip
  },
  {
    copy: "Consulte quando cada ação aconteceu, quem a realizou e qual era o estado anterior.",
    heading: "Registro de auditoria",
    Icon: ShieldCheck
  }
] as const;

function Brand() {
  return (
    <span className="landing-brand" translate="no">
      <span aria-hidden="true" className="landing-brand__mark">R</span>
      <span>rent<strong>ivo</strong></span>
    </span>
  );
}

function BillingJourneyPreview() {
  return (
    <section aria-label="Exemplo do fluxo de cobrança" className="landing-preview">
      <div className="landing-preview__masthead">
        <span>Exemplo de fatura</span>
        <time dateTime="2026-05">Maio de 2026</time>
      </div>

      <ol aria-label="Etapas exibidas" className="landing-preview__stages">
        <li className="is-complete"><Check aria-hidden="true" size={14} />Cobrança</li>
        <li className="is-current"><FileText aria-hidden="true" size={14} />PDF + PIX</li>
        <li><ReceiptText aria-hidden="true" size={14} />Pagamento</li>
      </ol>

      <div className="landing-preview__content">
        <div className="landing-preview__invoice">
          <div className="landing-preview__invoice-head">
            <div>
              <span>Cobrança</span>
              <strong>Apartamento 302</strong>
            </div>
            <span className="landing-preview__status">Pendente</span>
          </div>
          <dl className="landing-preview__items">
            <div><dt>Aluguel</dt><dd>R$&nbsp;2.500,00</dd></div>
            <div><dt>Condomínio</dt><dd>R$&nbsp;680,00</dd></div>
            <div><dt>Água</dt><dd>R$&nbsp;87,00</dd></div>
          </dl>
          <div className="landing-preview__total">
            <span>Total</span>
            <strong>R$&nbsp;3.267,00</strong>
          </div>
        </div>

        <div className="landing-preview__payment">
          <QrCode aria-hidden="true" size={88} strokeWidth={1.8} />
          <div>
            <span>PDF pronto</span>
            <strong>QR Code PIX incluído</strong>
          </div>
          <small>Exemplo ilustrativo</small>
        </div>
      </div>
    </section>
  );
}

export function LandingPage() {
  return (
    <div className="landing-page">
      <LandingMetadata />
      <a className="landing-skip-link" href="#conteudo">Pular para o conteúdo</a>

      <nav aria-label="Navegação principal" className="landing-nav">
        <div className="wrapper landing-nav__inner">
          <a aria-label="Rentivo, página inicial" className="landing-nav__brand" href="/">
            <Brand />
          </a>
          <div className="landing-nav__links">
            <a className="landing-nav__anchor" href="#como-funciona">Como funciona</a>
            <a className="landing-nav__anchor" href="#recursos">Recursos</a>
            <a className="landing-nav__login" href="/login">Entrar</a>
            <a className="btn btn--primary btn--sm" href="/signup">Criar conta</a>
          </div>
        </div>
      </nav>

      <main id="conteudo" tabIndex={-1}>
        <section className="landing-hero">
          <div className="wrapper landing-hero__inner">
            <div className="landing-hero__copy">
              <p className="landing-eyebrow">Gratuito e de código aberto</p>
              <h1>Cobranças de aluguel. <span>PIX em segundos.</span></h1>
              <p className="landing-hero__summary">
                Crie cobranças recorrentes, gere o PDF do mês e acompanhe cada pagamento em um único lugar.
              </p>
              <div className="landing-hero__actions">
                <a className="btn btn--primary btn--lg" href="/signup">
                  Criar conta <ArrowRight aria-hidden="true" size={18} />
                </a>
                <a className="btn btn--lg" href="#como-funciona">Ver como funciona</a>
              </div>
            </div>
            <BillingJourneyPreview />
          </div>
        </section>

        <div className="landing-proof">
          <ul aria-label="Recursos principais" className="wrapper landing-proof__list">
            <li><QrCode aria-hidden="true" size={18} /><span><span translate="no">PDF</span> com QR Code PIX</span></li>
            <li><GitHubIcon size={18} />Código aberto GPL-3.0</li>
            <li><UsersRound aria-hidden="true" size={18} />Equipes e permissões</li>
            <li><Paperclip aria-hidden="true" size={18} />Comprovantes na fatura</li>
          </ul>
        </div>

        <section className="landing-flow" id="como-funciona">
          <div className="wrapper">
            <div className="landing-section-heading">
              <h2>O aluguel segue um caminho claro</h2>
              <p>Você configura uma vez. Nos meses seguintes, só atualiza o que mudou.</p>
            </div>
            <ol aria-label="Fluxo mensal" className="landing-flow__list">
              {workflow.map(({ copy, heading, Icon }) => (
                <li key={heading}>
                  <Icon aria-hidden="true" size={24} strokeWidth={1.8} />
                  <div>
                    <h3>{heading}</h3>
                    <p>{copy}</p>
                  </div>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="landing-capabilities" id="recursos">
          <div className="wrapper landing-capabilities__layout">
            <div className="landing-capabilities__intro">
              <h2>Cada detalhe continua no mesmo lugar</h2>
              <p>
                A cobrança, o documento, o pagamento e o histórico permanecem conectados ao imóvel.
              </p>
            </div>
            <div className="landing-capabilities__ledger">
              {capabilities.map(({ copy, heading, Icon }) => (
                <article key={heading}>
                  <Icon aria-hidden="true" size={22} strokeWidth={1.8} />
                  <div>
                    <h3>{heading}</h3>
                    <p>{copy}</p>
                  </div>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="landing-open-source">
          <div className="wrapper landing-open-source__layout">
            <div>
              <h2>Aberto para você conferir</h2>
              <p>O Rentivo é gratuito e o código está disponível sob a licença GPL-3.0.</p>
              <a
                className="btn landing-open-source__button"
                href="https://github.com/jorgejr568/rentivo"
                rel="noopener noreferrer"
                target="_blank"
              >
                <GitHubIcon size={18} />GitHub
              </a>
            </div>
            <dl className="landing-open-source__facts">
              <div><dt>Dados</dt><dd>Armazenamento local ou em S3</dd></div>
              <div><dt>Histórico</dt><dd>Ações registradas por autor e data</dd></div>
              <div><dt>Operação</dt><dd>PIX, PDF, equipes e comprovantes</dd></div>
            </dl>
          </div>
        </section>

        <section className="landing-final-cta">
          <div className="wrapper landing-final-cta__inner">
            <div>
              <h2>Cobrar aluguel não precisa virar planilha</h2>
              <p>Organize o próximo mês com um fluxo simples, rastreável e gratuito.</p>
            </div>
            <a className="btn btn--lg" href="/signup">
              Criar conta <ArrowRight aria-hidden="true" size={18} />
            </a>
          </div>
        </section>
      </main>

      <footer className="landing-footer">
        <div className="wrapper landing-footer__inner">
          <div>
            <a aria-label="Rentivo, página inicial" className="landing-footer__brand" href="/">
              <Brand />
            </a>
            <p>Gestão de cobranças para imóveis.<br />Gratuito e de código aberto.</p>
          </div>
          <nav aria-label="Links do rodapé" className="landing-footer__links">
            <a href="/login">Entrar</a>
            <a href="/privacy">Privacidade</a>
            <a href="/terms">Termos</a>
            <a href="/support">Suporte</a>
            <a
              href="https://github.com/jorgejr568/rentivo"
              rel="noopener noreferrer"
              target="_blank"
            >GitHub</a>
          </nav>
        </div>
      </footer>
    </div>
  );
}
