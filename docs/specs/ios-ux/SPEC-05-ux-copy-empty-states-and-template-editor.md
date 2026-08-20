# SPEC-05 — Copy de UX, estados vazios e editor de modelo de comunicação

## Status e convenções

- Produto: Rentivo iOS.
- UI: SwiftUI, iOS 17+.
- Copy visível ao cliente: português do Brasil, em tom simples, direto e útil.
- Código, tipos, propriedades, identificadores de acessibilidade e nomes de testes: inglês.
- Este documento define comportamento, copy e contratos de UX; não contém código de implementação.
- Caminhos são relativos à raiz do repositório. A raiz do app é `ios/`.
- Esta especificação altera a copy de alguns toasts, mas não substitui posição, duração, ownership ou animação definidos em `SPEC-03-toast-system-and-home-empty-state.md`.

## Goal

Eliminar copy genérica e jargão técnico dos fluxos de cobrança, fatura, comunicação, exportação, organização e chave de integração. Cada tela vazia deve explicar o que falta e oferecer a próxima ação possível; cada falha deve dizer o que não aconteceu e como o usuário pode prosseguir; e o editor de comunicação deve permitir editar o modelo bruto sem obrigar o usuário a interpretar tokens ou Markdown para entender o resultado.

O resultado esperado é:

1. nenhum estado vazio de lista usar “item” como nome genérico do objeto;
2. Despesas, Arquivos, Faturas, chaves de integração, Organizações e Cobranças terem copy própria e CTA inline quando a permissão permitir a ação;
3. nenhum toast de produção usar “enfileirado”, “metadados” ou outro termo interno sem explicar o resultado para o usuário;
4. erros da API não chegarem diretamente à interface nos fluxos abrangidos;
5. o editor de comunicação oferecer inserção assistida de variáveis, prévia renderizada e contagem em caracteres;
6. etapas sem decisão serem removidas do wizard de envio;
7. o convite de membro explicar os três papéis reais antes da escolha;
8. instruções de wizard aparecerem sempre antes dos controles aos quais se aplicam.

## Evidência no código atual

### Localização e strings

Não existe `Localizable.xcstrings`, `.strings` ou `.stringsdict` em `ios/`. A copy é escrita diretamente nos arquivos Swift, inclusive nos modelos de domínio que expõem labels. Esta entrega mantém o mecanismo atual: a copy PT-BR será atualizada nos call sites e tipos existentes. Criar ou migrar para um catálogo de strings é uma iniciativa separada e não deve ser misturada a esta correção.

### Estados vazios

- `PageStateView` em `ios/Rentivo/DesignSystem/RentivoComponents.swift` possui defaults `Nada por aqui ainda` e `Crie o primeiro item para começar.`.
- `ExpenseListView` e `AttachmentListView`, ambos em `ios/Rentivo/Features/Bills/BillingOperationsViews.swift`, usam esses defaults e dependem do pequeno botão `+` da toolbar.
- `BillingDetailView` mostra apenas `Nenhuma fatura foi gerada para esta cobrança.`; a criação fica num ícone `plus.circle.fill`, que pode ainda estar desabilitado por falta de PIX.
- `APIKeyListView`, `OrganizationListView` e `BillingListView` já passam título, descrição e ação próprios para `PageStateView`. Cobranças e Organizações são a referência a preservar; a descrição da chave ainda usa “escopos”.
- `PageStateView` já aceita `emptyActionTitle` e `emptyAction`, portanto Despesas, Arquivos e chaves não precisam de um segundo mecanismo de apresentação.

### Toasts

Os toasts globais são disparados por `AppModel.showNotice`. A varredura encontrou `Comunicação enfileirada para envio.`, `Exportação CSV enfileirada.` e `Documento enfileirado para regeneração.`, além de `Metadados da chave atualizados.` e `Herança de tema restaurada.`. Falhas dinâmicas usam `DemoError(error).message` e são tratadas na seção de erros deste documento.

A exportação merece uma correção factual: `backend/rentivo/jobs/handlers/export.py` gera um arquivo temporário, envia-o como anexo ao e-mail da conta solicitante e agenda a exclusão do objeto. Ela não cria um `Attachment` e não aparece na tela `Arquivos`. A confirmação deve mencionar o e-mail; afirmar que o arquivo aparecerá em `Arquivos` seria incorreto sem uma mudança de produto/backend que não faz parte deste escopo.

### Erros

`LiveAPIClient` preserva `problemCode`, `statusCode` e o `detail` do problem document em `LiveAPIError.server`. `DemoError.init(_:)` converte qualquer `LocalizedError` na respectiva `errorDescription`; em seguida, os arquivos de Billings, Bills, Organizations e Communications mostram essa mensagem diretamente em estado de página, toast ou erro inline. Isso permite vazar copy de transporte como `Recurso não encontrado.`, `A chave não possui o escopo necessário.`, `Transição de status inválida.`, `Billing ownership changed` ou mensagens agregadas de campos da API.

O mapeamento amigável desta especificação deve acontecer na camada de apresentação. `LiveAPIClient` continua preservando a resposta bruta para diagnóstico e para fluxos de autenticação já cobertos por outra especificação.

### Editor de comunicação

`CommunicationComposerView`, hoje dentro de `ios/Rentivo/Features/Bills/BillingOperationsViews.swift`, possui cinco etapas fixas: `Canal`, `Destinatários`, `Mensagem`, `Modelo` e `Revisar envio`.

- Quando só um tipo está disponível, `Canal` contém apenas `Tipo: Fatura` ou `Tipo: Recibo de pagamento` em uma linha somente leitura.
- `Mensagem` lista os tokens brutos no subtítulo, usa `Corpo (Markdown — HTML não é permitido)` como label e mostra os asteriscos do Markdown somente no editor bruto.
- O contador usa `lengthOfBytes(using: .utf8)` e exibe `bytes`.
- `Modelo` contém apenas um picker de persistência do modelo.
- A revisão mostra assunto, mas não mostra o corpo renderizado.
- O repositório possui `previewCommunication`, porém o endpoint correspondente é `deprecated`, é rate-limited e não substitui variáveis. Uma prévia realmente ao vivo não deve depender dele.

Há duas regras duplicadas para o limite do corpo: `CommunicationFormRules` em `Domain/FormRules.swift` e `CommunicationContent` em `Domain/BillingModels.swift`. Ambas validam 4.096 bytes UTF-8.

### Papéis de organização

Os papéis reais, definidos por `OrganizationRole` em `ios/Rentivo/Domain/AccountModels.swift`, são:

- `admin` → `Administrador`;
- `manager` → `Gerente`;
- `viewer` → `Visualizador`.

Não existe o papel `Gestor` no contrato. `InviteMemberView` mostra os três nomes num `Picker("Função")`, sem explicar a diferença. As capabilities e as regras da API confirmam que Administrador gerencia organização/membros, Gerente gerencia o trabalho de cobrança sem administrar membros/configurações, e Visualizador não altera dados.

### Instruções de wizard

`RentivoWizardSection` renderiza `subtitle` imediatamente abaixo do título e antes de `content`. Os wizards atuais usam esse slot de forma consistente. A frase `Use valor zero para itens variáveis que serão preenchidos em cada fatura.` já está no lugar correto e deve ser mantida sem alteração. Mensagens posteriores aos campos são justificadas apenas quando são erro, estado ou ajuda de um controle específico.

## Escopo

### Incluído

- Empty states e CTAs das seis áreas pedidas.
- Auditoria de todos os textos literais usados em `showNotice`/`AppNotice` no app iOS; mudança somente onde há jargão, ambiguidade ou ausência de recuperação.
- Mapeamento de erro para billings, bills, expenses/files relacionados, communications, exports, organizations e invitations.
- Editor e prévia de comunicação.
- Composição dinâmica das etapas do wizard de comunicação.
- Seleção explicada dos papéis no convite.
- Regra de posicionamento de instruções nos wizards afetados.

### Fora de escopo

- Revisar erros de login, MFA/TOTP, passkey ou desafio de autenticação. Os dois toasts de organização que encaminham o usuário para Segurança mudam apenas para remover siglas; a lógica de autenticação continua fora deste documento.
- Criar catálogo de localização ou traduzir o app para outro idioma.
- Mudar o destino da exportação de e-mail para `Arquivos`.
- Redesenhar o sistema visual de toast definido em SPEC-03.
- Adicionar um novo editor WYSIWYG ou uma dependência de Markdown.
- Alterar papéis, capabilities ou autorização do backend.
- Aplicar as mesmas mudanças ao Android, macOS ou web nesta entrega.

## Arquivos afetados

### Produção iOS

| Caminho real | Alteração esperada |
| --- | --- |
| `ios/Rentivo/DesignSystem/RentivoComponents.swift` | Extrair/reusar um empty state configurável; remover os defaults com “item”; manter suporte a ação inline e estados de erro/retry. |
| `ios/Rentivo/DesignSystem/UserFacingError.swift` | Novo mapper de apresentação com contexto da operação, `problemCode`, status e fallbacks PT-BR. O grupo sincronizado do Xcode inclui o arquivo automaticamente. |
| `ios/Rentivo/Domain/AccountModels.swift` | Manter os três labels reais e adicionar descrições de convite, sem mudar raw values ou capabilities. |
| `ios/Rentivo/Domain/FormRules.swift` | Unificar a validação visível da mensagem em caracteres e adicionar validação dos tokens suportados. |
| `ios/Rentivo/Domain/BillingModels.swift` | Eliminar a segunda regra divergente de tamanho ou fazê-la delegar para a mesma fonte de verdade; preservar normalização e wire values. |
| `ios/Rentivo/Features/Account/APIKeyViews.swift` | Simplificar a descrição do empty state e trocar “metadados” no toast. |
| `ios/Rentivo/Features/Billings/BillingListView.swift` | Preservar o empty state aprovado e usar erros contextualizados em carregamento/refresh. |
| `ios/Rentivo/Features/Billings/BillingDetailView.swift` | Transformar o vazio de Faturas em bloco com título, descrição e CTA; oferecer caminho para configurar PIX; usar erros contextualizados. |
| `ios/Rentivo/Features/Billings/BillingFormView.swift` | Permitir abrir a edição diretamente na etapa PIX a partir do empty state; manter a instrução dos itens no topo; usar erro contextualizado ao salvar/carregar organizações. |
| `ios/Rentivo/Features/Bills/BillingOperationsViews.swift` | Configurar empties de Despesas/Arquivos, trocar copy da exportação e aplicar o mapper de erro. O composer pode ser removido deste arquivo após a extração. |
| `ios/Rentivo/Features/Bills/CommunicationComposerView.swift` | Novo arquivo extraído para o wizard dinâmico, inserção de variáveis, editor bruto, prévia, contador e toggle de modelo. |
| `ios/Rentivo/Features/Bills/BillViews.swift` | Atualizar copy de regeneração e avisos de arquivo; mapear erros; atualizar o histórico logo após solicitar um envio. |
| `ios/Rentivo/Features/Organizations/OrganizationViews.swift` | Preservar o empty state aprovado, trocar a sigla no toast de segurança e mapear erros por operação. |
| `ios/Rentivo/Features/Organizations/InvitationViews.swift` | Renderizar papéis como cards selecionáveis com descrição, trocar a sigla no encaminhamento para Segurança e mapear falhas de convite. |

`ios/Rentivo/Data/API/LiveAPIClient.swift` não deve começar a substituir `detail` globalmente. O mapper de UI precisa de `problemCode` e `statusCode` que já existem; auth e outros consumidores podem continuar usando o contrato atual até suas próprias revisões.

### Dependência externa para “caracteres”

O contrato atual rejeita corpo com mais de 4.096 bytes UTF-8 em `backend/rentivo/api/schemas/billings.py`, mesmo quando há menos de 4.096 caracteres visíveis. O iOS não pode renomear esse orçamento de bytes como “caracteres”: uma mensagem em português com acentos poderia aparecer abaixo do limite e ainda ser recusada.

Antes de liberar o contador `N de 4.096 caracteres`, o contrato de envio e salvamento de modelos deve aceitar 4.096 caracteres percebidos pelo usuário, usando segmentação equivalente a `Swift.String.count`, e deixar de impor o limite menor de 4.096 bytes. Se essa dependência não for aprovada, o contador em caracteres fica bloqueado e a copy de bytes atual não pode apenas ser relabelada.

Uma mudança desse contrato exige revisar, no mínimo:

- `backend/rentivo/api/schemas/billings.py` e seus testes de limite;
- `frontend/openapi.json`, `ios/Rentivo/openapi.json` e `android/app/openapi.json`, se descrição/schema mudar;
- os clientes web/Android que hoje validam bytes, para que não existam limites conflitantes.

### Testes e documentação

| Caminho real | Alteração esperada |
| --- | --- |
| `ios/RentivoTests/NativeFormContractTests.swift` | Trocar os casos de bytes por caracteres, cobrir graphemes/acentos e tokens desconhecidos. |
| `ios/RentivoTests/ValidationTests.swift` | Manter `CommunicationContent` e `CommunicationFormRules` na mesma fronteira. |
| `ios/RentivoTests/ModelsTests.swift` | Fixar labels e descrições dos três papéis. |
| `ios/RentivoTests/UXCopyRulesTests.swift` | Novo arquivo app-only para composição de passos, substituição/prévia e mapeamento de erro. |
| `ios/RentivoUITests/BillOperationsWizardUITests.swift` | Atualizar toast de exportação; cobrir wizard reduzido, prévia, variável, contador e envio. |
| `ios/RentivoUITests/OrganizationAccountWizardUITests.swift` | Atualizar copy de aparência e cobrir cards de papel do convite. |
| `ios/RentivoUITests/EmptyStateCopyUITests.swift` | Novo arquivo para copy e CTA dos empties, inclusive variações sem permissão e PIX pendente. |
| `docs/testing/ios-manual-test-flows.md` | Atualizar exportação por e-mail, comunicação, convites e cenários vazios. |

## Empty states

### Componente e regra comum

`PageStateView` não deve possuir fallback customer-facing que use “item”. Introduzir uma configuração de empty state com título, mensagem, símbolo e ação opcional. A configuração pode ser omitida somente em telas de detalhe que nunca produzem `.empty`; em DEBUG, chegar a `.empty` sem configuração deve falhar de forma visível para o time, não publicar copy genérica silenciosamente.

O mesmo conteúdo visual deve poder ser usado dentro da seção Faturas, sem forçar a página inteira a `.empty`. O bloco inline deve usar o mesmo título, descrição e botão de `PageStateView`, mas ajustar altura/padding ao `ScrollView` de detalhe.

Regras:

1. O título nomeia o objeto ausente no singular/plural natural.
2. A descrição explica por que a primeira ação é útil; não repete o título.
3. O botão inline é a ação primária e usa texto explícito, nunca apenas `+`.
4. O `+` da toolbar pode permanecer como atalho, mas deve ter o mesmo nome acessível e disparar exatamente a mesma ação.
5. Quando a capability não permite criar, adicionar ou enviar, omitir o CTA e usar descrição que não instrui uma ação impossível.
6. Vazio de dados e zero resultados de busca continuam estados diferentes. `ContentUnavailableView.search` permanece no filtro de Cobranças.

### Copy final por feature

| Feature/condição | Título | Mensagem | CTA inline |
| --- | --- | --- | --- |
| Despesas, `canWrite == true` | `Nenhuma despesa registrada` | `Registre a primeira despesa para acompanhar os custos desta cobrança.` | `Adicionar despesa` |
| Despesas, sem escrita | `Nenhuma despesa registrada` | `Não há despesas registradas nesta cobrança.` | Nenhum |
| Arquivos, `canWrite == true` | `Nenhum arquivo adicionado` | `Adicione documentos ou imagens para encontrá-los junto desta cobrança.` | `Adicionar arquivo` |
| Arquivos, sem escrita | `Nenhum arquivo adicionado` | `Não há arquivos nesta cobrança.` | Nenhum |
| Faturas, pode gerar e PIX pronto | `Nenhuma fatura gerada` | `Gere a primeira fatura desta cobrança.` | `Gerar fatura` |
| Faturas, pode gerar e PIX pendente | `Nenhuma fatura gerada` | `Configure os dados do PIX antes de gerar a primeira fatura.` | `Configurar PIX` |
| Faturas, sem permissão de criar | `Nenhuma fatura gerada` | `Ainda não há faturas nesta cobrança.` | Nenhum |
| Chaves de integração, criação liberada | `Nenhuma chave de integração` | `Crie uma chave para conectar outro serviço ao Rentivo e escolher o que ele pode acessar.` | `Criar chave` |
| Chaves de integração, demo visualizador | `Nenhuma chave de integração` | `Não há chaves de integração nesta conta.` | Nenhum |
| Organizações, criação liberada | `Nenhuma organização ainda` | `Organizações reúnem cobranças e membros sob papéis e permissões compartilhados. Crie uma para colaborar com sua equipe.` | `Criar organização` |
| Organizações, sem criação | `Nenhuma organização ainda` | `As organizações das quais você participa aparecerão aqui.` | Nenhum |
| Cobranças, criação liberada | `Nenhuma cobrança ainda` | `Crie sua primeira cobrança para começar a gerar faturas.` | `Nova cobrança` |
| Cobranças, sem criação | `Nenhuma cobrança ainda` | `As cobranças que você pode consultar aparecerão aqui.` | Nenhum |

`Configurar PIX` abre `BillingFormView` para a cobrança atual já posicionado na etapa `PIX`; depois de salvar, a tela de detalhe recarrega e passa a oferecer `Gerar fatura`. Não usar um botão desabilitado como única próxima ação.

## Toasts e confirmações

### Regra de conteúdo

Um toast de sucesso de trabalho assíncrono não deve afirmar que o resultado final já aconteceu. Ele deve dizer:

1. qual solicitação foi aceita/iniciada;
2. onde o usuário encontrará o resultado ou acompanhará o status.

Evitar `fila`, `job`, `worker`, `request`, `payload`, `metadata`, `scope`, `TOTP` e `passkey` em confirmações gerais. Siglas podem continuar em telas especializadas cobertas por outra especificação, mas não são necessárias nos toasts de encaminhamento desta entrega.

### Auditoria dos textos alterados

| Contexto | Atual | Proposto |
| --- | --- | --- |
| Aparência salva | `Tema atualizado.` | `Aparência atualizada.` |
| Aparência restaurada | `Herança de tema restaurada.` | `A aparência padrão foi restaurada.` |
| Chave de integração editada | `Metadados da chave atualizados.` | `Informações da chave atualizadas.` |
| Regeneração de documento | `Documento enfileirado para regeneração.` | `Novo documento solicitado. Ele aparecerá aqui quando estiver pronto.` |
| Comunicação aceita | `Comunicação enfileirada para envio.` | `Envio iniciado. Acompanhe o status em Comunicações.` |
| Exportação aceita | `Exportação {FORMATO} enfileirada.` | `Seu arquivo {FORMATO} está sendo preparado. Você o receberá no e-mail da sua conta.` |
| Convite aceito em organização com segurança obrigatória | `Sua nova organização exige MFA. Abra Segurança para configurar TOTP ou uma passkey.` | `Sua nova organização exige verificação em duas etapas. Em Conta, abra Segurança para configurar.` |
| Política da organização passou a exigir segurança | `MFA passou a ser obrigatório. Abra Segurança para cadastrar um método.` | `A verificação em duas etapas agora é obrigatória. Em Conta, abra Segurança para configurar.` |
| Falha ao usar câmera | `Não foi possível usar a foto capturada.` | `Não foi possível usar a foto. Tire outra foto ou escolha um arquivo.` |
| Falha ao ler arquivo de comprovante | `Não foi possível ler o arquivo selecionado.` | `Não foi possível abrir o arquivo. Escolha outro e tente novamente.` |
| Falha ao preparar foto capturada | `Não foi possível preparar a foto do comprovante.` | `Não foi possível preparar a foto. Tire outra foto ou escolha um arquivo.` |
| Falha ao ler foto da biblioteca | `Não foi possível ler a foto selecionada.` | `Não foi possível abrir a foto. Escolha outra e tente novamente.` |
| Arquivo vazio | `O arquivo selecionado está vazio.` | `O arquivo está vazio. Escolha outro e tente novamente.` |
| Comprovante acima do limite | `O comprovante excede o limite de {LIMITE}.` | `O comprovante é maior que {LIMITE}. Escolha um arquivo menor e tente novamente.` |

Após `Envio iniciado…`, `BillDetailView` deve recarregar silenciosamente a fatura para que a linha com status `Na fila` esteja visível em `Comunicações`. A copy não pode prometer um lugar que continua desatualizado.

### Textos auditados e mantidos

Os textos abaixo já são simples, específicos e verdadeiros; permanecem iguais. As variantes na mesma célula representam todos os literais encontrados.

| Área | Copy mantida |
| --- | --- |
| Conta/PIX | `PIX pessoal removido.`; `PIX pessoal atualizado.` |
| Segurança/auth, fora deste escopo | `Senha alterada com sucesso.`; `Sessão conectada ao Rentivo.`; `Sua sessão expirou. Entre novamente para continuar.`; `Não foi possível restaurar sua sessão. Entre novamente.`; `Sua conta foi excluída.` |
| Chave de integração | `Chave revogada.` |
| Cobrança | `Cobrança criada.`; `Cobrança atualizada.`; `Cobrança excluída.` |
| Organização/convite | `Organização criada.`; `Organização atualizada.`; `Convite enviado.`; `Convite aceito.`; `Convite recusado.` |
| Fatura | `Fatura criada como rascunho.`; `Fatura atualizada.`; `Fatura marcada como {status}.` |
| Arquivo | `Arquivo enviado.` |
| Demonstração | `Bem-vinda à demonstração do Rentivo.`; `A próxima operação falhará de forma controlada.`; `Demonstração restaurada.` |

Literals usados apenas nos `#Preview` de componentes não são copy de runtime e não entram como requisito de produto. Toda chamada dinâmica `showNotice(DemoError(error).message, kind: .warning)` nas features incluídas deve ser substituída pelo padrão de erro abaixo.

## Erros amigáveis sem passthrough da API

### Contrato de apresentação

Criar um mapper de UI que receba a operação em andamento e o `Error`. O resultado deve conter uma primeira frase específica sobre o que falhou e uma segunda frase com a recuperação. O mapper usa, nesta ordem:

1. estado global de sessão, que continua sob responsabilidade de `AppModel`;
2. `LiveAPIError.problemCode` para casos que possuem recuperação própria;
3. `LiveAPIError.statusCode` para categorias comuns;
4. um fallback específico da operação.

Nunca usar `LiveAPIError.errorDescription`, `DemoError(error).message`, `detail`, `fields`, request ID, status HTTP ou machine code diretamente como copy de UI nos fluxos deste escopo. Erros locais tipados e escritos pelo próprio app, como formato/tamanho de upload antes da rede, podem manter mensagens aprovadas desta especificação.

O mapper precisa diferenciar pelo menos estas operações:

| Grupo | Operações |
| --- | --- |
| Cobranças | carregar lista, carregar detalhe, salvar, excluir, transferir |
| Faturas | carregar, gerar/salvar, excluir, alterar status, regenerar, baixar documento |
| Despesas e arquivos | carregar, adicionar, excluir, baixar |
| Comunicações | enviar comunicação |
| Exportações | solicitar exportação |
| Organizações | carregar lista/detalhe, salvar, excluir, atualizar/remover membro, mudar segurança, transferir cobrança |
| Convites | carregar, enviar, aceitar, recusar |

### Fallbacks por operação

| Operação | Copy proposta |
| --- | --- |
| Carregar uma lista | `Não foi possível carregar {objetos}. Verifique sua conexão e tente novamente.` |
| Carregar um detalhe | `Não foi possível carregar {este objeto}. Verifique sua conexão e tente novamente.` |
| Salvar | `Não foi possível salvar {o objeto}. Revise os dados e tente novamente.` |
| Excluir | `Não foi possível excluir {o objeto}. Atualize a tela e tente novamente.` |
| Alterar status | `Não foi possível alterar o status da fatura. Atualize a tela e tente novamente.` |
| Regenerar documento | `Não foi possível solicitar um novo documento. Tente novamente em alguns instantes.` |
| Baixar/abrir arquivo | `Não foi possível abrir o arquivo. Verifique sua conexão e tente novamente.` |
| Enviar comunicação | `Não foi possível iniciar o envio. Revise os dados e tente novamente.` |
| Solicitar exportação | `Não foi possível preparar a exportação. Tente novamente em alguns instantes.` |
| Atualizar membro/política/transferência | `Não foi possível concluir a alteração. Atualize a organização e tente novamente.` |
| Enviar convite | `Não foi possível enviar o convite. Confira o e-mail e tente novamente.` |
| Aceitar/recusar convite | `Não foi possível responder ao convite. Atualize a lista e tente novamente.` |

Os placeholders acima são resolvidos pelo contexto antes de chegar à tela; nunca mostrar chaves como `{objeto}` ao cliente.

### Overrides por problem code/status

| Sinal atual da API | Atual que pode aparecer | Copy proposta |
| --- | --- | --- |
| `not_found`/404 em lista ou detalhe | `Recurso não encontrado.` | `Este conteúdo não está mais disponível. Volte e atualize a lista.` |
| 403, `missing_scope` ou `insufficient_role` | `A chave não possui o escopo necessário.` ou detail equivalente | `Você não tem permissão para fazer esta alteração. Peça ajuda a um administrador da organização.` |
| 429 | detail variável | `Muitas tentativas em pouco tempo. Aguarde alguns minutos e tente novamente.` |
| 5xx, resposta inválida ou erro desconhecido | `Não foi possível interpretar a resposta do Rentivo.` ou detail variável | Fallback da operação, terminando em `Tente novamente em alguns instantes.` |
| `pix_setup_required` | `Configure a chave PIX, o nome e a cidade do recebedor antes de continuar.` | `Não foi possível gerar a fatura. Configure os dados do PIX da cobrança e tente novamente.` |
| `validation_error`, `invalid_billing` ou `invalid_billing_item` ao salvar cobrança | detail/fields variáveis | `Não foi possível salvar a cobrança. Revise os campos e tente novamente.` |
| `invalid_variable_amounts`/`invalid_total_amount` | detail variável | `Não foi possível salvar a fatura. Revise os valores dos itens e tente novamente.` |
| `stale_bill_status` | `O status da fatura foi alterado. Atualize a página e tente novamente.` | Manter exatamente a mensagem atual, agora como copy controlada pelo cliente. |
| `invalid_status_transition` | `Transição de status inválida.` | `Essa alteração de status não está mais disponível. Atualize a fatura e escolha outra ação.` |
| `stale_bill_delete` | `A fatura já foi excluída por outra operação.` | `Esta fatura já foi excluída. Volte para a cobrança e atualize a lista.` |
| `invoice_not_ready`/`recibo_not_ready` | `A fatura/O recibo ainda está sendo gerado.` | `O documento ainda está sendo preparado. Aguarde e tente novamente.` |
| `invoice_unavailable` | `Gere o PDF da fatura antes de enviar a comunicação.` | `O PDF da fatura ainda não está disponível. Gere o documento e tente novamente.` |
| `receipt_unavailable`/`recibo_unavailable` | detail variável | `O recibo fica disponível depois que a fatura é marcada como paga.` |
| `invalid_recipients` | `Selecione somente destinatários desta cobrança.` | `Um destinatário não está mais disponível. Atualize os destinatários da cobrança e tente novamente.` |
| `communication_blocked` | `A mensagem contém conteúdo não permitido e não pode ser enviada.` | `A mensagem contém conteúdo que não pode ser enviado. Revise o texto e tente novamente.` |
| `billing_transfer_conflict` | detail que pode incluir inglês | `Não foi possível transferir a cobrança porque os dados mudaram. Atualize e tente novamente.` |
| `organization_has_billings` | `Transfira ou exclua as cobranças vinculadas antes de excluir a organização.` | `Esta organização ainda possui cobranças. Transfira ou exclua essas cobranças e tente novamente.` |
| `membership_conflict` | `A associação do membro foi alterada ou removida.` | `Os dados deste membro mudaram. Atualize a organização e tente novamente.` |
| `invite_conflict` | `Não foi possível criar este convite.` | `Não foi possível enviar o convite. Confira se a pessoa já é membro ou tem um convite pendente.` |

### Local de apresentação e recuperação

- Falha inicial de carregamento: estado de página com título contextual, orientação e `Tentar novamente`.
- Falha de refresh com conteúdo já visível: manter conteúdo e mostrar toast de warning com o mapper.
- Falha de formulário/modal: manter o modal aberto e mostrar as duas frases inline na etapa atual ou na revisão; o toast global continua proibido atrás de sheet/full-screen cover.
- Validação local conhecida: selecionar a etapa, focar o primeiro campo inválido e usar a mensagem específica do campo.
- 404 de detalhe: além da mensagem, o retry pode continuar disponível; se o segundo fetch confirmar 404, oferecer `Voltar` em vez de um loop sem saída.
- 403: não oferecer retry imediato como única ação; preservar os dados visíveis e orientar o contato com administrador.

## Editor de comunicação

### Etapas dinâmicas

Uma etapa somente leitura não justifica um avanço. Os descriptors passam a ser construídos a partir das decisões reais:

| Situação | Etapas finais |
| --- | --- |
| Um único tipo disponível, caso normal | `Destinatários` → `Mensagem` → `Revisar envio` |
| Fatura e recibo disponíveis | `O que enviar` → `Destinatários` → `Mensagem` → `Revisar envio` |
| Nenhum tipo disponível | Não abrir o wizard; manter o entry point desabilitado e explicar `Esta fatura ainda não está pronta para envio.` |

Se houver dois tipos, `O que enviar` apresenta escolha entre `Fatura` e `Recibo de pagamento`. `Canal` deixa de ser usado porque o controle atual escolhe conteúdo/tipo, não canal de entrega.

A etapa `Modelo` é removida sempre. A revisão continua existindo porque confirma destinatários, anexo e conteúdo renderizado, e passa a conter a decisão de salvar modelo. O progresso deve refletir três ou quatro etapas sem segmentos vazios, e Voltar deve retornar à etapa visível anterior.

Regra geral para wizards: omitir etapas que contenham apenas informação somente leitura ou uma única opção inevitável. Etapas de revisão são exceção quando permitem confirmar impacto ou tomar uma decisão final.

### Edição bruta e inserção de variáveis

A etapa `Mensagem` mantém os campos brutos `Assunto` e `Mensagem`. O corpo continua aceitando Markdown e os tokens continuam armazenados/enviados no formato atual; isso preserva edição avançada e compatibilidade com os modelos existentes.

Substituir a lista textual de tokens por um controle `Inserir dado` que ofereça nomes humanos:

| Label do menu/chip | Token inserido |
| --- | --- |
| `Nome do inquilino` | `{{nome_inquilino}}` |
| `Unidade` | `{{unidade}}` |
| `Mês de referência` | `{{mes}}` |
| `Vencimento` | `{{vencimento}}` |
| `Valor total` | `{{total}}` |

O controle insere o token na posição atual do cursor do último campo focado. Se nenhum campo foi focado, insere no corpo e move o foco para ele. O label acessível deve incluir o destino atual, por exemplo `Inserir dado na mensagem`; o usuário não precisa conhecer chaves ou chaves duplas para usar o menu.

Tokens digitados manualmente continuam permitidos. Um token que corresponda ao formato `{{identificador}}` mas não esteja na lista suportada deve ser mostrado sem substituição na prévia, produzir `Revise a variável não reconhecida: {TOKEN}.` e impedir `Continuar`/enviar. Isso evita que uma variável bruta chegue ao destinatário.

### Prévia ao vivo

Abaixo do editor bruto, mostrar um card `Prévia da mensagem`, expandido e visível por padrão. Ele atualiza localmente a cada alteração de assunto, mensagem, tipo ou seleção de destinatário; não há botão “Gerar prévia”, spinner, debounce de rede ou chamada ao endpoint deprecated.

A prévia usa o primeiro destinatário selecionado na ordem da cobrança como exemplo e os dados da fatura atual:

| Token | Valor da prévia |
| --- | --- |
| `{{nome_inquilino}}` | Nome do primeiro destinatário selecionado |
| `{{unidade}}` | `billing.name` |
| `{{mes}}` | `bill.referenceMonth.displayFormatted` |
| `{{vencimento}}` | `bill.dueDate.displayFormatted`; string vazia quando não há vencimento, igual ao servidor |
| `{{total}}` | `bill.effectiveTotal.formatted()` |

Quando mais de um destinatário estiver selecionado, mostrar `Prévia para {NOME}. Cada destinatário receberá a mensagem com seus próprios dados.`. Sem destinatário selecionado, usar `Nome do inquilino` como valor demonstrativo e manter o erro de seleção da etapa Destinatários.

O assunto da prévia aplica apenas substituição de variáveis. O corpo aplica substituição e renderiza Markdown: negrito não mostra `**`, itálico não mostra `_`, links têm label legível, listas mantêm estrutura e HTML bruto aparece como texto inerte. Usar APIs nativas (`AttributedString`/SwiftUI) e cobrir paridade dos elementos suportados; não adicionar WebView nem pacote de terceiros. Se uma construção não puder ser renderizada, mostrar texto escapado em vez de executar HTML ou ocultar conteúdo.

A mesma apresentação renderizada é reutilizada na etapa `Revisar envio`, junto de destinatários e anexo. O conteúdo bruto permanece editável na etapa anterior e não é descartado ao navegar.

### Contador em caracteres

Depois de cumprida a dependência de contrato, o contador visível usa `Swift.String.count` e a formatação numérica PT-BR:

- normal: `{N} de 4.096 caracteres`;
- acima do limite: mesma frase em coral, erro `A mensagem deve ter no máximo 4.096 caracteres.` e envio desabilitado;
- nunca mostrar `bytes`, `UTF-8`, `unicodeScalars`, `NSString.length` ou unidades técnicas.

O limite e a mensagem devem ter uma única fonte de verdade compartilhada por `CommunicationFormRules`, `CommunicationContent`, mock e composer. A contagem inclui espaços e quebras de linha, como o conteúdo efetivamente enviado, antes do trim usado na normalização final.

### Salvar como modelo na revisão

Adicionar à revisão um toggle, desligado por padrão:

`Salvar como modelo para próximos envios`

Com o toggle desligado, `saveScope` é `nil`. Ligado:

- se apenas o escopo da cobrança estiver disponível, selecionar `.billing` sem mostrar outro picker;
- se o usuário puder salvar no owner, mostrar `Usar o modelo em` com `Somente nesta cobrança` e uma opção de owner;
- owner organização: `Todas as cobranças desta organização`;
- owner pessoal: `Todas as minhas cobranças`.

Mostrar abaixo: `O assunto e a mensagem substituirão o modelo atual.`. O estado do toggle/escopo faz parte de `isDirty`, é preservado ao voltar e só é persistido junto do envio bem-sucedido.

## Convite: papéis explicados

Substituir o picker compacto da etapa `Permissão` por três cards selecionáveis. O card inteiro é acionável, mostra nome, descrição e checkmark/radio de seleção. O default continua `Visualizador`.

| Papel | Descrição final |
| --- | --- |
| `Administrador` | `Gerencia a organização, os membros e a segurança. Também cria e administra cobranças.` |
| `Gerente` | `Pode criar cobranças e gerenciar faturas, despesas, comprovantes e envios. Não gerencia membros nem configurações da organização.` |
| `Visualizador` | `Pode consultar a organização e as cobranças, sem criar nem alterar dados.` |

As descrições explicam o papel atribuído a uma pessoa com sessão normal; as capabilities retornadas pelo servidor continuam sendo a autoridade em runtime. Não inferir permissão pelo label para habilitar ações.

A revisão usa `Nível de acesso` em vez de `Função`. MFA obrigatório/opcional permanece como informação separada, com a terminologia de segurança que vier da especificação de auth.

## Posicionamento de instruções nos wizards

Manter `RentivoWizardSection.subtitle` como o único slot para instrução geral de uma seção:

1. título da seção;
2. uma frase de contexto/efeito, antes do primeiro controle;
3. controles;
4. hints específicos de campo e erros junto do campo correspondente.

Uma instrução deve explicar consequência, formato ou motivo; não repetir o título nem dizer apenas `Opcional` quando o próprio label pode fazê-lo. Warnings condicionais podem aparecer depois do controle que os causou. Revisões não precisam de subtítulo salvo quando há uma consequência final importante.

A frase de Itens recorrentes permanece exatamente `Use valor zero para itens variáveis que serão preenchidos em cada fatura.` e continua acima da primeira linha de item. O novo editor usa `Personalize o texto e confira a prévia antes de enviar.` no subtítulo de Mensagem. A etapa de convite usa `Escolha o que esta pessoa poderá fazer. Você pode alterar o nível de acesso depois.` acima dos cards.

## Copy table — fonte de verdade das mudanças

As tabelas de empty state, toast e error mapping acima fazem parte desta fonte de verdade. As demais strings alteradas estão consolidadas aqui.

### Editor e wizard de comunicação

| Atual | Proposto |
| --- | --- |
| Etapa `Canal` com uma linha `Tipo: Fatura/Recibo de pagamento` | Remover a etapa quando há uma opção; usar etapa `O que enviar` somente quando há duas opções. |
| Etapa `Modelo` | Remover; mover a decisão para a revisão. |
| `Variáveis: {{nome_inquilino}}, {{unidade}}, {{mes}}, {{vencimento}}, {{total}}.` | `Personalize o texto e confira a prévia antes de enviar.` + controle `Inserir dado`. |
| `Corpo (Markdown — HTML não é permitido)` | `Mensagem` |
| `{N}/4096 bytes` | `{N} de 4.096 caracteres` |
| `A mensagem deve ter no máximo 4096 bytes.` | `A mensagem deve ter no máximo 4.096 caracteres.` |
| `Modelo` / `O modelo salvo preenche automaticamente as próximas comunicações.` | Remover a seção independente. |
| `Salvar modelo` | `Salvar como modelo para próximos envios` |
| `Não salvar como modelo` | Estado desligado do toggle, sem label adicional. |
| `Salvar para esta cobrança` | `Somente nesta cobrança` |
| `Salvar para a organização` | `Todas as cobranças desta organização` |
| `Salvar para minha conta` | `Todas as minhas cobranças` |
| Nenhuma orientação de sobrescrita | `O assunto e a mensagem substituirão o modelo atual.` |
| Seção de revisão `Prévia` que mostra somente o assunto | Prévia renderizada de assunto e mensagem. |
| Review row `Canal` | `Tipo` |
| Destinatários na revisão como número isolado, por exemplo `2` | `2 destinatários` (ou `1 destinatário`). |
| Nenhuma identificação da pessoa usada na prévia | `Prévia para {NOME}. Cada destinatário receberá a mensagem com seus próprios dados.` quando houver vários. |
| Token desconhecido sem validação | `Revise a variável não reconhecida: {TOKEN}.` |

### Convite e instruções

| Atual | Proposto |
| --- | --- |
| Etapa `Permissão` | `Nível de acesso` |
| `Permissão na organização` | `Escolha o nível de acesso` |
| `Escolha o que esta pessoa poderá consultar e alterar.` | `Escolha o que esta pessoa poderá fazer. Você pode alterar o nível de acesso depois.` |
| Picker `Função` sem explicação | Cards `Administrador`, `Gerente` e `Visualizador` com as descrições desta especificação. |
| Review row `Função` | `Nível de acesso` |

### Empty states adicionais

| Atual | Proposto |
| --- | --- |
| Default `Nada por aqui ainda` | Remover o default; usar o título específico da feature. |
| Default `Crie o primeiro item para começar.` | Remover o default; usar a mensagem específica da feature/permissão. |
| Toolbar de Despesas `Adicionar` | `Adicionar despesa` como label acessível e CTA inline. |
| Toolbar de Arquivos `Adicionar` | `Adicionar arquivo` como label acessível e CTA inline. |
| `Nenhuma fatura foi gerada para esta cobrança.` | `Nenhuma fatura gerada` + mensagem e CTA condicionais da tabela de empty states. |
| API key: `Crie uma chave de API para conectar integrações externas com escopos e acessos controlados.` | `Crie uma chave para conectar outro serviço ao Rentivo e escolher o que ele pode acessar.` |

## Acessibilidade

### Empty states e ações

- `ContentUnavailableView`/componente equivalente deve expor título, mensagem e ação nessa ordem.
- CTA inline e toolbar podem coexistir, mas ambos têm o mesmo nome acessível específico e a mesma disponibilidade.
- Botões e cards têm área mínima de 44 × 44 pt e não dependem do ícone `+` para comunicar a ação.
- Estado sem permissão não anuncia ação desabilitada; ele omite a ação.
- Título, mensagem e CTA refluem em Dynamic Type sem truncamento e sem largura fixa.

### Editor e prévia

- `Inserir dado` é um botão/menu nomeado, não uma fileira de símbolos sem label. Cada opção anuncia o nome humano e o destino, não apenas o token bruto.
- O foco permanece no campo e volta à posição de inserção depois de escolher uma variável.
- Editor bruto e prévia são grupos distintos com headings acessíveis. A prévia não deve ser anunciada inteira a cada tecla; o usuário a explora quando quiser.
- O contador não dispara announcement a cada caractere. Anunciar somente ao cruzar 90%, ao exceder 4.096 e ao voltar para o limite válido.
- Links renderizados conservam trait de link. Negrito/itálico não são comunicados apenas por diferença de cor.
- Erro de token ou limite move foco de acessibilidade para o primeiro problema quando o usuário toca `Continuar`.
- A prévia deve funcionar com VoiceOver sem ler asteriscos de Markdown; os asteriscos continuam acessíveis apenas no campo bruto.

### Papéis

- Cada card de papel é um único elemento com label, descrição e trait/value `Selecionado` quando ativo.
- Checkmark e tratamento de cor são redundantes; seleção não depende apenas de cor.
- A ordem de leitura é Administrador, Gerente, Visualizador, seguida do aviso de segurança da organização.
- A descrição pode ocupar várias linhas e não deve ser truncada no maior tamanho de texto.

### Erros e toasts

- “O que aconteceu” e “como corrigir” são lidos como uma unidade, sem machine code ou status HTTP.
- Falhas inline recebem foco após submit; falha de refresh não rouba foco do conteúdo que permaneceu na tela.
- Os novos textos de toast usam o announcement/lifecycle da SPEC-03 e preservam o botão `Fechar aviso`.
- Não usar cor como único indicador de erro, warning, seleção ou status assíncrono.

## Acceptance criteria

### Empty states

1. Nenhum runtime call site de `PageStateView` mostra `Nada por aqui ainda`, `Crie o primeiro item para começar.` ou qualquer CTA chamado apenas `Adicionar` no estado vazio abrangido.
2. Despesas e Arquivos mostram exatamente a copy final e um botão inline quando `canWrite` é verdadeiro.
3. Os CTAs inline de Despesas/Arquivos abrem o mesmo formulário/importer dos botões da toolbar.
4. Faturas mostra um bloco inline, não uma linha solta. Com PIX pronto, `Gerar fatura` abre o wizard; com PIX pendente, `Configurar PIX` abre o editor na etapa PIX; sem capability, não há CTA.
5. Chaves de integração não mostra “escopos” no empty state e preserva `Criar chave` quando permitido.
6. Cobranças e Organizações preservam a copy aprovada no caso editável e omitem instruções impossíveis no caso sem permissão.
7. Busca sem resultado em Cobranças continua sendo estado de busca, não first-use empty state.

### Toasts e erros

8. Não existe `enfileirad`, `Metadados da chave` ou `Herança de tema` em copy de runtime iOS.
9. A exportação bem-sucedida informa que o arquivo chegará por e-mail; não menciona `Arquivos`.
10. O envio bem-sucedido informa que foi iniciado e o histórico é recarregado para mostrar status `Na fila`.
11. Regeneração não afirma que o documento está pronto; a tela continua exibindo `Renderizando…` até o polling concluir.
12. Todos os catches nos arquivos de features abrangidos usam o mapper contextual ou uma validação local tipada; nenhum mostra `DemoError(error).message`/`error.localizedDescription` diretamente.
13. 403, 404, 409 conhecido, 422 conhecido, 429, offline/timeout, 5xx e resposta inválida produzem copy aprovada com recuperação.
14. Um `detail` sintético em inglês ou contendo endpoint/UUID não aparece em page state, toast ou form error.
15. Modal com falha permanece aberto; página com refresh falho preserva conteúdo; validação local retorna à etapa/campo acionável.

### Comunicação

16. Com um tipo disponível, o wizard inicia em `Destinatários` e mostra `Etapa 1 de 3`; não existe etapa `Canal` nem `Modelo`.
17. Com dois tipos, existe `O que enviar` e o wizard mostra quatro etapas. Com zero tipos, o wizard não abre.
18. `Inserir dado` oferece os cinco labels e insere o token correto no cursor do campo alvo.
19. Assunto e mensagem brutos continuam editáveis; modelos existentes com tokens e Markdown carregam sem perda.
20. A prévia atualiza sem request de rede e renderiza assunto, corpo, cinco variáveis, negrito, itálico, listas, links e HTML como texto inerte.
21. A prévia usa o primeiro destinatário selecionado e os valores da fatura; vários destinatários recebem a explicação de personalização individual.
22. Token desconhecido é visível, gera a mensagem aprovada e bloqueia o avanço.
23. Após a mudança de contrato, o contador usa `String.count`, separador PT-BR, `caracteres` e a fronteira exata de 4.096. Mensagens com acentos/emoji abaixo do limite não são recusadas por uma regra oculta de bytes.
24. `Salvar como modelo para próximos envios` fica na revisão, inicia desligado, mapeia para o `saveScope` correto e preserva a escolha ao navegar para trás.
25. O corpo renderizado é mostrado também na revisão; a contagem de destinatários inclui a unidade (`destinatário(s)`).

### Convite e instruções

26. A etapa de convite mostra exatamente Administrador, Gerente e Visualizador; não mostra Gestor.
27. Cada papel possui a descrição final desta especificação e o default continua Visualizador.
28. A revisão usa `Nível de acesso` e mostra o papel escolhido.
29. Instruções gerais aparecem entre o título da seção e o primeiro controle nos wizards afetados.
30. `Use valor zero para itens variáveis que serão preenchidos em cada fatura.` permanece inalterada e acima dos campos dos itens.

### Acessibilidade

31. Empty CTAs, variable menu, role cards, preview, contador, erros e toasts atendem às notas de acessibilidade deste documento no maior Dynamic Type e com VoiceOver.
32. UI tests localizam novos elementos por identifiers em inglês; assertions de copy verificam o PT-BR exato quando a copy é o requisito testado.

## Test plan

### Unit tests de domínio

1. Validar 0, 1, 4.095, 4.096 e 4.097 `Character`s, incluindo `á`, emoji simples e grapheme composto; 4.096 válidos e 4.097 inválidos.
2. Confirmar que `CommunicationFormRules` e `CommunicationContent` devolvem a mesma mensagem/fronteira.
3. Substituir cada token no assunto e corpo, tokens repetidos e tokens com whitespace compatível com o servidor.
4. Preservar texto comum e Markdown no conteúdo bruto.
5. Detectar token desconhecido sem confundir chaves comuns que não formam `{{identificador}}`.
6. Fixar labels/raw values e descrições de `admin`, `manager` e `viewer`.

### Unit tests do app

1. Composer com `[.billReady]` gera três descriptors; com os dois tipos gera quatro; com nenhum tipo informa indisponibilidade.
2. Inserção no início, meio, fim e seleção substituída preserva a posição do cursor.
3. Preview context escolhe o primeiro destinatário selecionado na ordem original e usa os cinco valores corretos, inclusive vencimento vazio.
4. Markdown renderiza os elementos definidos e escapa HTML bruto.
5. Toggle desligado produz `nil`; ligado produz `.billing`; opção de owner produz `.owner`; mudanças entram em `isDirty`.
6. Mapper cobre cada operation fallback e cada override de problem code/status da tabela.
7. Passar `LiveAPIError.server(message: "Billing ownership changed /api/v1/... UUID", ...)` prova que o detail não chega ao resultado.
8. Refresh com conteúdo escolhe toast; carregamento inicial escolhe page state; formulário escolhe erro inline.

### UI tests

1. Ativar empty mode e abrir Despesas, Arquivos, Cobranças, Organizações e chaves. Verificar título/mensagem; tocar o CTA e confirmar o destino correto.
2. Repetir empty states em viewer mode e confirmar ausência de CTA/instrução impossível.
3. Abrir cobrança sem faturas com PIX pronto e gerar a primeira fatura pelo CTA inline.
4. Abrir cobrança sem faturas com PIX pendente, tocar `Configurar PIX` e confirmar que a etapa PIX está ativa.
5. Abrir Enviar fatura com um tipo e confirmar `Etapa 1 de 3`; avançar até Mensagem sem encontrar `Canal` ou `Modelo`.
6. Inserir `Nome do inquilino`, digitar `**importante**` e confirmar token bruto no editor, nome/negrito na prévia e ausência dos asteriscos na prévia.
7. Digitar token desconhecido e confirmar erro/foco/bloqueio; corrigir e confirmar recuperação.
8. Confirmar contador PT-BR e estados de limite com fixture longa.
9. Na revisão, ligar `Salvar como modelo…`, escolher escopo, voltar e avançar para confirmar persistência.
10. Solicitar envio; confirmar toast novo, retorno ao detalhe e comunicação `Na fila`.
11. Solicitar CSV e XLSX; confirmar texto com formato e destino por e-mail.
12. Abrir convite, navegar até `Nível de acesso`, selecionar cada card e confirmar a revisão.
13. Stubbar respostas 403/404/409/422/429/500 e texto técnico em inglês; confirmar copy contextual e que o modal não fecha.

### Testes manuais

- iPhone compacto, iPhone com Dynamic Island e iPad.
- iOS 17 e runtime atual de distribuição.
- Dynamic Type padrão e maior tamanho de acessibilidade.
- VoiceOver, Switch Control, Reduce Motion e Increase Contrast.
- Teclado aberto no assunto e no corpo; cursor no início/meio/fim durante inserção de variável.
- Um, vários e nenhum destinatário selecionado.
- Fatura e recibo; com e sem vencimento; valores grandes formatados em BRL.
- Markdown com parágrafos, quebra de linha, negrito, itálico, lista, link, HTML bruto e token desconhecido.
- Offline, timeout, sessão expirada, sem permissão, recurso removido por outra sessão e erro 5xx.
- Empty state com e sem capability, incluindo PIX pendente.
- Conferir no ambiente real que o e-mail de exportação chega com anexo e que nenhum arquivo novo aparece em `Arquivos`.

### Comandos de verificação

- `make ios-test` para Domain/Data.
- Rodar o target Xcode `RentivoTests` no simulador, como a action de CI, para testes app-only de DesignSystem/Features.
- Rodar `RentivoUITests/BillOperationsWizardUITests`, `RentivoUITests/OrganizationAccountWizardUITests` e `RentivoUITests/EmptyStateCopyUITests` em simulador determinístico com `--ui-testing`.
- `make macos-test` quando `ios/Rentivo/Domain/` mudar, conforme a regra do repositório para `RentivoCore` compartilhado.
- Se a dependência backend de caracteres entrar no mesmo conjunto de mudanças: testes específicos de comunicação do backend, `make test`, sync/check dos OpenAPI móveis e checks dos clientes que também validam o limite.

## Sequenciamento recomendado

1. Resolver e testar o contrato de 4.096 caracteres; não relabelar bytes antes disso.
2. Introduzir empty state configurável e mapper de erro, com testes puros.
3. Aplicar copy/ações às listas e ao detalhe de cobrança.
4. Extrair e refazer o composer, incluindo preview, passos dinâmicos e refresh pós-envio.
5. Aplicar cards de papel e regra de instruções.
6. Atualizar todos os toasts e UI tests que verificam copy literal.
7. Executar testes automáticos e a matriz manual de acessibilidade.

## Adendo (2026-08-19, segunda leva de screenshots QA)

Achados adicionais da rodada H5–H8 do passe manual; tratam-se de copy e microUX no mesmo escopo desta spec:

1. **Erro de lockout MFA dentro de formulários (H6a-02).** Quando a organização passa a exigir MFA e o usuário ainda não configurou, chamadas 403 aparecem como erro de campo em formulários (ex.: wizard Dados e PIX) com a mensagem `Sua organização exige a configuração da autenticação multifator.` e uma ação `Tentar novamente` que não resolve nada. Especificar: nesse caso o erro deve oferecer a ação `Configurar autenticador` que navega para Conta → Segurança (ou apresenta a tela `security.mfa.setup-required`), em vez de (ou além de) `Tentar novamente`.
2. **Confirmação da política de MFA (H6-01).** O popover atual diz apenas `A política será aplicada a todos os membros desta organização.` Quando o próprio administrador ainda não tem MFA configurado, acrescentar aviso explícito de que ele será bloqueado até configurar (copy sugerida: `Você ainda não configurou a autenticação em duas etapas. Ao confirmar, será necessário configurá-la para continuar usando o Rentivo.`). Descobrir no código se o estado MFA do usuário atual está disponível nessa tela; se não estiver, especificar a variante incondicional mais informativa.
3. **Wizard de Aparência/tema (H8).** Etapa Tipografia mostra dois pickers idênticos sem rótulo (`Montserrat ⌄` duas vezes) — aplicar labels persistentes `Fonte de títulos` e `Fonte de texto` (mesmo padrão RentivoFormField). Na Revisão, `Cor primária #8A4C94` deve exibir um swatch da cor ao lado do hex. A copy de herança `Este nível herda o tema de padrão rentivo.` deve virar algo claro e com marca correta, ex.: `Este nível herda o tema padrão do Rentivo.`; avaliar também o rótulo `Origem efetiva` (jargão) → `Tema aplicado`.
4. **Menu de papel do membro (H5-01).** O menu (Administrador / Gerente / Remover) não indica o papel atual do membro — marcar o papel atual (checkmark) e garantir que a opção do papel corrente não dispare request redundante. O ícone de coroa do dono precisa de accessibilityLabel (`Dono da organização`).

Critérios de aceite adicionais: cada item acima tem copy PT-BR final aplicada, os dois pickers de tipografia têm rótulos visíveis e acessíveis distintos, o swatch da cor primária aparece na revisão do tema, o erro 403 de MFA em formulários oferece navegação para a configuração, e o menu de papel indica o papel atual.
