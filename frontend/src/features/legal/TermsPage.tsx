import { useEffect } from "react";
import { Link } from "react-router";

import "./PrivacyPolicyPage.css";

const termsSections = [
  { href: "#o-servico", label: "O serviço" },
  { href: "#sua-conta", label: "Sua conta" },
  { href: "#conteudo-cadastrado", label: "Conteúdo cadastrado" },
  { href: "#pagamentos", label: "Pagamentos" },
  { href: "#uso-aceitavel", label: "Uso aceitável" },
  {
    href: "#disponibilidade-responsabilidade",
    label: "Disponibilidade e responsabilidade"
  },
  { href: "#encerramento", label: "Encerramento" },
  { href: "#alteracoes-contato-foro", label: "Alterações, contato e foro" }
];

export function TermsPage() {
  useEffect(() => {
    document.title = "Termos de Uso - Rentivo";
  }, []);

  return (
    <article aria-labelledby="terms-title" className="privacy-page terms-page">
      <a className="privacy-page__skip-link" href="#terms-content">
        Pular para o conteúdo
      </a>
      <nav aria-label="Navegação institucional" className="privacy-page__topbar">
        <Link
          aria-label="Rentivo, página inicial"
          className="privacy-page__brand"
          to="/"
          translate="no"
        >
          <span aria-hidden="true" className="privacy-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </Link>
        <Link className="privacy-page__back-link" to="/">Voltar ao início</Link>
      </nav>

      <div className="privacy-page__reader" id="terms-content" tabIndex={-1}>
        <header className="privacy-page__header">
          <div className="privacy-page__title-group">
            <h1 id="terms-title">Termos de Uso</h1>
          </div>
          <p className="privacy-page__updated">
            <span>Última atualização</span>
            <time dateTime="2026-07-23">23 de julho de 2026</time>
          </p>
          <p className="privacy-page__lede">
            Estes termos regem o uso do Rentivo, plataforma de gestão de
            cobranças de aluguel. Ao criar uma conta ou usar o serviço, você
            concorda com estes termos.
          </p>
        </header>

        <div className="privacy-page__layout">
          <aside className="privacy-page__spine">
            <nav aria-label="Nestes termos" className="privacy-page__toc">
              <p>Nestes termos</p>
              <ol>
                {termsSections.map((section) => (
                  <li key={section.href}>
                    <a href={section.href}>{section.label}</a>
                  </li>
                ))}
              </ol>
            </nav>
          </aside>

          <div className="privacy-page__document">
            <section id="o-servico">
              <h2>O serviço</h2>
              <p>
                O Rentivo permite criar e organizar cobranças de aluguel, gerar
                QR Codes PIX, emitir recibos e enviar comunicações por e-mail. O
                serviço é uma ferramenta de gestão: as relações de locação e os
                pagamentos ocorrem diretamente entre você e as pessoas que você
                cobra.
              </p>
            </section>

            <section id="sua-conta">
              <h2>Sua conta</h2>
              <p>
                Você é responsável por manter suas credenciais em segurança,
                por fornecer informações verdadeiras (incluindo sua chave PIX)
                e por toda atividade realizada na sua conta. Recomendamos ativar
                um segundo fator de autenticação.
              </p>
            </section>

            <section id="conteudo-cadastrado">
              <h2>Conteúdo cadastrado</h2>
              <p>
                Os dados que você cadastra (imóveis, cobranças, destinatários)
                permanecem seus. Ao cadastrar dados de terceiros, como nome e
                e-mail de inquilinos, você declara ter base legal para isso e
                para o envio das comunicações feitas em seu nome pela plataforma.
              </p>
            </section>

            <section id="pagamentos">
              <h2>Pagamentos</h2>
              <p>
                O Rentivo não é instituição de pagamento, não intermedeia nem
                custodia valores. Os QR Codes PIX gerados apontam para a chave
                PIX cadastrada por você, e os pagamentos são liquidados
                diretamente pelo arranjo PIX entre pagador e recebedor.
              </p>
            </section>

            <section id="uso-aceitavel">
              <h2>Uso aceitável</h2>
              <p>
                É proibido usar o serviço para atividade ilegal, para enviar
                comunicações não autorizadas (spam), para cobrar valores
                indevidos ou para tentar comprometer a segurança da plataforma
                ou de outras contas.
              </p>
            </section>

            <section id="disponibilidade-responsabilidade">
              <h2>Disponibilidade e responsabilidade</h2>
              <p>
                O serviço é fornecido &quot;como está&quot;. Trabalhamos para mantê-lo
                disponível e seguro, mas não garantimos operação ininterrupta.
                Na extensão permitida pela lei, o Rentivo não responde por
                perdas decorrentes de informações incorretas cadastradas por
                você ou por indisponibilidade de serviços de terceiros (como o
                arranjo PIX).
              </p>
            </section>

            <section id="encerramento">
              <h2>Encerramento</h2>
              <p>
                Você pode excluir sua conta a qualquer momento em Segurança
                &gt; Excluir conta. Podemos suspender ou encerrar contas que
                violem estes termos.
              </p>
            </section>

            <section id="alteracoes-contato-foro">
              <h2>Alterações, contato e foro</h2>
              <p>
                Podemos atualizar estes termos, indicando a data da última
                atualização nesta página. O tratamento de dados pessoais é
                descrito na <Link to="/privacy">Política de Privacidade</Link>.
                Dúvidas: <a href="mailto:suporte@rentivo.com.br">suporte@rentivo.com.br</a>.
                Estes termos são regidos pelas leis brasileiras.
              </p>
            </section>
          </div>
        </div>
      </div>
    </article>
  );
}
