import { useEffect } from "react";
import { Link } from "react-router";

import "./PrivacyPolicyPage.css";

const policySections = [
  { href: "#dados-coletados", label: "Dados que coletamos" },
  { href: "#uso-dos-dados", label: "Como usamos os dados" },
  { href: "#bases-legais", label: "Bases legais" },
  { href: "#compartilhamento", label: "Compartilhamento" },
  { href: "#seguranca-retencao", label: "Segurança e retenção" },
  { href: "#direitos-lgpd", label: "Seus direitos (LGPD)" },
  { href: "#alteracoes", label: "Alterações" }
];

export function PrivacyPolicyPage() {
  useEffect(() => {
    document.title = "Política de Privacidade - Rentivo";
  }, []);

  return (
    <article aria-labelledby="privacy-policy-title" className="privacy-page">
      <a className="privacy-page__skip-link" href="#privacy-content">
        Pular para o conteúdo
      </a>
      <nav aria-label="Navegação institucional" className="privacy-page__topbar">
        <Link aria-label="Rentivo, página inicial" className="privacy-page__brand" to="/">
          <span aria-hidden="true" className="privacy-page__brand-mark">R</span>
          <span>rent<em>ivo</em></span>
        </Link>
        <Link className="privacy-page__back-link" to="/">Voltar ao início</Link>
      </nav>

      <div className="privacy-page__reader" id="privacy-content" tabIndex={-1}>
        <header className="privacy-page__header">
          <div className="privacy-page__title-group">
            <p className="privacy-page__eyebrow">Privacidade no Rentivo</p>
            <h1 id="privacy-policy-title">Política de Privacidade</h1>
          </div>
          <p className="privacy-page__updated">
            <span>Última atualização</span>
            <time dateTime="2026-08-13">13 de agosto de 2026</time>
          </p>
          <p className="privacy-page__lede">
            O Rentivo é uma plataforma de gestão de cobranças de aluguel. Esta
            política explica quais dados pessoais tratamos, por que tratamos e
            quais são os seus direitos, em conformidade com a Lei Geral de
            Proteção de Dados (LGPD, Lei nº 13.709/2018).
          </p>
        </header>

        <div className="privacy-page__layout">
          <aside className="privacy-page__spine">
            <nav aria-label="Nesta política" className="privacy-page__toc">
              <p>Nesta política</p>
              <ol>
                {policySections.map((section) => (
                  <li key={section.href}><a href={section.href}>{section.label}</a></li>
                ))}
              </ol>
            </nav>
          </aside>

          <div className="privacy-page__document">
            <section id="dados-coletados">
              <h2>Dados que coletamos</h2>
              <div className="privacy-page__data-list">
                <p>
                  <strong>Dados de conta:</strong> e-mail e senha (armazenada apenas
                  como hash criptográfico). Se você entrar com o Google, recebemos o
                  e-mail associado à sua conta Google.
                </p>
                <p>
                  <strong>Dados de segurança:</strong> chaves de acesso (passkeys),
                  configuração de autenticação por aplicativo (TOTP), códigos de
                  recuperação e dispositivos conhecidos, usados para proteger sua
                  conta.
                </p>
                <p>
                  <strong>Dados de recebimento:</strong> chave PIX, nome e cidade do
                  recebedor, usados para gerar as cobranças que você cria.
                </p>
                <p>
                  <strong>Conteúdo de cobranças:</strong> os dados que você cadastra
                  sobre imóveis, cobranças, despesas, recibos, comunicações e
                  destinatários (como nome e e-mail de inquilinos). Você é responsável
                  por ter base legal para cadastrar dados de terceiros.
                </p>
                <p>
                  <strong>Registros técnicos:</strong> endereço IP, identificação do
                  navegador e registros de auditoria de ações na conta, mantidos por
                  segurança. Usamos cookies essenciais de sessão e métricas de uso do
                  site.
                </p>
              </div>
            </section>

            <section id="uso-dos-dados">
              <h2>Como usamos os dados</h2>
              <p>
                Usamos seus dados para operar o serviço (gerar cobranças PIX, enviar
                e-mails de cobrança e recibos), proteger sua conta, enviar
                comunicações transacionais (como avisos de segurança), analisar a
                segurança do conteúdo das comunicações e entender o uso do produto
                para melhorá-lo. Não vendemos dados pessoais.
              </p>
            </section>

            <section id="bases-legais">
              <h2>Bases legais</h2>
              <p>
                Tratamos dados com base na execução de contrato (operar sua conta),
                no cumprimento de obrigação legal (registros fiscais e de auditoria),
                no legítimo interesse (segurança e prevenção a fraudes) e no
                consentimento, quando aplicável.
              </p>
            </section>

            <section id="compartilhamento">
              <h2>Compartilhamento</h2>
              <p>
                Usamos operadores para funcionar: Amazon Web Services (hospedagem,
                armazenamento de arquivos e envio de e-mails), Cloudflare (proteção
                contra abuso no cadastro), Google (login opcional e métricas de uso)
                e OpenRouter (análise opcional de segurança do conteúdo de
                comunicações, quando o processamento externo estiver habilitado).
                Esses operadores tratam dados conforme nossos contratos e suas
                próprias políticas. Não compartilhamos dados com terceiros para fins
                de publicidade.
              </p>
            </section>

            <section id="seguranca-retencao">
              <h2>Segurança e retenção</h2>
              <p>
                Dados sensíveis são criptografados em repouso com chaves gerenciadas
                (KMS), senhas são armazenadas apenas como hash e todo o tráfego usa
                HTTPS. Mantemos seus dados enquanto sua conta existir. Após a
                exclusão da conta, registros de cobranças e de auditoria podem ser
                retidos pelo prazo exigido por obrigações legais e fiscais.
              </p>
            </section>

            <section id="direitos-lgpd">
              <h2>Seus direitos (LGPD)</h2>
              <p>
                Você pode solicitar acesso, correção, portabilidade e exclusão dos
                seus dados, além de informações sobre o tratamento. Você pode
                excluir sua conta diretamente em Segurança &gt; Excluir conta (no
                site ou no aplicativo). Para outras solicitações, fale com{" "}
                <a href="mailto:suporte@rentivo.com.br">suporte@rentivo.com.br</a>.
              </p>
            </section>

            <section id="alteracoes">
              <h2>Alterações</h2>
              <p>
                Podemos atualizar esta política e indicaremos a data da última
                atualização nesta página. O uso do serviço também é regido pelos{" "}
                <Link to="/terms">Termos de Uso</Link>.
              </p>
            </section>
          </div>
        </div>
      </div>
    </article>
  );
}
