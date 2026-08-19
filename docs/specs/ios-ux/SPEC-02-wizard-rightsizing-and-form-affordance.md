# SPEC-02 — Rightsizing de wizards e affordance de formulários

## Status e convenções

- Plataforma: Rentivo iOS, SwiftUI, iOS 17+.
- Copy visível ao cliente: português do Brasil.
- Identificadores, tipos e propriedades novos: inglês.
- Este documento especifica comportamento e contratos de UI; não contém implementação.
- Caminhos citados são relativos à raiz do repositório. A raiz do app é `ios/`.

## Goal

Reduzir atrito nos formulários pequenos e eliminar erros de digitação causados por campos sem limites visuais. Em especial, o usuário deve conseguir distinguir inequivocamente cada campo antes, durante e depois da edição; o valor `120000` deve aparecer como `R$ 1.200,00` enquanto é digitado; e etapas de revisão só devem existir quando permitem confirmar informação útil.

O resultado esperado é:

1. transformar “Alterar senha” em uma única tela com três campos e uma única ação de confirmação;
2. manter “Dados e PIX” em três etapas, mas fazer cada etapa justificar sua existência;
3. criar um padrão único de campo no DesignSystem e aplicá-lo a todos os formulários em wizard abrangidos por esta especificação;
4. adicionar tipo, máscara, teclado e validação coerentes para chaves PIX;
5. reduzir criação/edição de chave de API de cinco para quatro etapas;
6. preservar o chrome de wizard que funciona nos fluxos maiores;
7. garantir entrada monetária em centavos com formatação BRL contínua.

## Evidência no código atual

- `RentivoFormWizard` já fornece “Etapa N de M”, segmentos de progresso, `Voltar`/`Continuar`, confirmação de descarte e barra fixa inferior.
- `ChangePasswordView` possui as etapas `.current`, `.new` e `.review`; a última só informa que os valores estão ocultos.
- `ProfilePixView` possui `.key`, `.recipient` e `.review`, carregamento assíncrono com proteção contra sobrescrever uma edição local e uma revisão que hoje mostra `Ambiente`.
- Os formulários colocam `TextField` e `SecureField` diretamente dentro de `RentivoWizardSection`. Como o card é o único contorno visível, campos adjacentes parecem linhas contínuas.
- `CurrencyCentavosField` já mantém um `Int` em centavos e formata com `Money`, mas precisa receber o mesmo label persistente, borda, foco e erro do novo componente. Os textos “Valor em centavos” ainda expõem o detalhe de armazenamento ao usuário.
- A API persiste apenas `pix_key`, não o tipo. O backend classifica e normaliza CPF, CNPJ, e-mail, telefone brasileiro e UUID; o tipo deve continuar sendo estado derivado/de formulário, sem alteração de contrato de rede.

## Decisões de escopo

### Manter “Dados e PIX” em três etapas

“Dados e PIX” continuará como wizard de três etapas: `Chave`, `Recebedor`, `Revisão`.

Essa é a melhor opção para o código e para o risco do dado neste caso porque:

- a nova etapa `Chave` terá dois controles relacionados — tipo e chave —, com máscara e validação próprias;
- a etapa `Recebedor` continua agrupando os dois campos limitados pelo contrato de geração do PIX;
- a revisão passará a permitir conferir e revelar a chave normalizada, em vez de apenas repetir metadados;
- o fluxo atual já protege carregamento assíncrono, descarte, modo visualizador e foco no primeiro erro;
- remover uma configuração existente será uma ação destrutiva explícita, separada do salvamento.

A revisão de senha, por outro lado, não consegue revelar ou confirmar seu conteúdo e não possui valor informacional; por isso esse fluxo será colapsado.

### Fora de escopo

- Colapsar cobrança, fatura, despesa, organização, convite ou comunicação.
- Alterar os endpoints ou adicionar `pix_key_type` ao payload.
- Alterar o chrome dos wizards de tema e exportação, que não possuem os campos de texto problemáticos deste escopo.
- Refazer regras de negócio de cobrança, permissões, MFA ou expiração de chave de API.
- Adicionar modo escuro.

## Arquivos afetados

### Produção

| Caminho real | Alteração esperada |
| --- | --- |
| `ios/Rentivo/DesignSystem/RentivoFormField.swift` | Novo componente genérico de campo e wrappers de texto/senha. O grupo sincronizado do projeto Xcode inclui o arquivo automaticamente. |
| `ios/Rentivo/DesignSystem/RentivoCurrencyField.swift` | Incorporar o novo chrome; expor API com identificadores novos em inglês; manter armazenamento inteiro em centavos. |
| `ios/Rentivo/DesignSystem/RentivoFormWizard.swift` | Preservar o wizard existente; apenas ajustes mínimos de composição/acessibilidade se necessários para os novos campos. |
| `ios/Rentivo/Domain/FormRules.swift` | Adicionar tipo/draft/regras compartilhadas de chave PIX, normalização, inferência, máscara e mensagens por campo. |
| `ios/Rentivo/Domain/Models.swift` | Fazer `ProfilePIXForm` carregar/manter o tipo derivado e exigir uma configuração completa para salvar; remoção não será mais representada por formulário vazio. |
| `ios/Rentivo/Domain/AccountModels.swift` | Reusar as regras compartilhadas de PIX na validação de organização. |
| `ios/Rentivo/Domain/BillingModels.swift` | Validar formato da chave PIX além dos dados do recebedor, sem mudar `PixConfiguration` ou o wire format. |
| `ios/Rentivo/Features/Account/SecurityViews.swift` | Substituir o wizard de senha pela tela única e aplicar campos seguros com revelar/ocultar. |
| `ios/Rentivo/Features/Account/AccountView.swift` | Atualizar `ProfilePixView`: tipo de chave, campo padrão, revisão útil, reveal e remoção explícita. |
| `ios/Rentivo/Features/Account/APIKeyViews.swift` | Aplicar o padrão de campo e reduzir o wizard para quatro etapas. |
| `ios/Rentivo/Features/Billings/BillingFormView.swift` | Aplicar o padrão a identificação, itens, PIX, destinatários e contatos de resposta; adicionar tipo de chave PIX. |
| `ios/Rentivo/Features/Bills/BillViews.swift` | Aplicar o padrão a competência, vencimento, itens, valores e observações. |
| `ios/Rentivo/Features/Bills/BillingOperationsViews.swift` | Aplicar o padrão a despesa e comunicação, incluindo valor, assunto e corpo. |
| `ios/Rentivo/Features/Organizations/OrganizationViews.swift` | Aplicar o padrão e adicionar tipo/validação de chave PIX. |
| `ios/Rentivo/Features/Organizations/InvitationViews.swift` | Aplicar o padrão a e-mail e função. |

Não há mudança prevista em `ios/Rentivo/Data/API/RemoteDTOs.swift`: os requests continuam enviando somente a chave normalizada em `pix_key` e os dados atuais do recebedor.

### Testes e documentação

| Caminho real | Alteração esperada |
| --- | --- |
| `ios/RentivoTests/NativeFormContractTests.swift` | Cobrir regras compartilhadas de PIX e validação por contexto. |
| `ios/RentivoTests/AppModelProfileTests.swift` | Atualizar semântica de salvar versus remover PIX. |
| `ios/RentivoTests/ValidationTests.swift` | Cobrir PIX válido/inválido em cobrança e organização. |
| `ios/RentivoTests/MoneyTests.swift` | Preservar formatação BRL e limites em centavos. |
| `ios/RentivoTests/RentivoFormWizardTests.swift` | Fixar a contagem de quatro etapas da chave de API e preservar a política do chrome. |
| `ios/RentivoTests/PixKeyInputRulesTests.swift` | Novo arquivo para inferência, máscara, normalização, paste e mensagens por tipo. |
| `ios/RentivoUITests/OrganizationAccountWizardUITests.swift` | Atualizar PIX e adicionar cobertura de senha em uma tela. |
| `ios/RentivoUITests/BillingWizardUITests.swift` | Regressão da concatenação de campos e formatação monetária. |
| `ios/RentivoUITests/BillOperationsWizardUITests.swift` | Atualizar o nome acessível de valor e verificar formatação durante a digitação. |
| `docs/testing/ios-manual-test-flows.md` | Atualizar passos de senha, PIX, API key e exemplos de campo monetário. |

## DesignSystem: campo de formulário

### Anatomia visual

Todo controle de entrada textual, segura, monetária, de data ou de seleção dentro dos fluxos abrangidos deve usar o mesmo container visual:

1. label persistente acima do controle, nunca substituída por placeholder;
2. label com `RentivoTypography.metadata`, peso semibold, small caps visual e cor `RentivoColors.ink`;
3. área do controle com altura mínima de 48 pt, padding horizontal de 12 pt e vertical de 10–12 pt;
4. fundo creme `RentivoColors.paper`;
5. borda de 2 pt em `RentivoColors.ink`, raio de 12 pt;
6. distância de 6 pt entre label e controle e 6 pt entre controle e hint/erro;
7. campos multiline com altura mínima de 96 pt e conteúdo alinhado ao topo;
8. erro/hint abaixo da borda, dentro do grupo do campo, não solto no final do card.

O label pode ser renderizado em small caps, mas o valor acessível deve manter capitalização e pronúncia natural. Placeholders são opcionais e servem somente como exemplo de formato; um campo sem placeholder continua identificável.

### Estados

| Estado | Tratamento |
| --- | --- |
| Normal | Borda `ink` 2 pt e fundo `paper`. |
| Focado | Borda `emerald` 3 pt, desenhada por overlay sem alterar o layout. |
| Erro | Borda `coral` 2 pt; ícone `exclamationmark.circle.fill` e mensagem em `coral` abaixo do controle. `accessibilityValue`/`accessibilityHint` anunciam o erro. |
| Erro + foco | Manter a borda coral e adicionar anel externo emerald de 2 pt. Assim erro e foco não dependem da mesma cor. |
| Desabilitado | Manter limite visível; reduzir opacidade do conteúdo, não remover a borda. |

Não mostrar erro antes da primeira tentativa de `Continuar`/salvar ou antes de o usuário sair de um campo já editado. Depois da primeira tentativa, atualizar/remover o erro assim que o valor se tornar válido. Erros de servidor sem campo conhecido ficam em um banner inline da seção; erros mapeáveis devem ocupar o slot do campo correspondente.

### API SwiftUI proposta

O sketch abaixo define a interface pública esperada, não a implementação:

```swift
enum RentivoFormFieldState: Equatable {
  case normal
  case focused
  case invalid(message: String)
  case disabled
}

struct RentivoFormField<Control: View>: View {
  init(
    label: String,
    hint: String? = nil,
    state: RentivoFormFieldState = .normal,
    @ViewBuilder control: () -> Control
  )
}

struct RentivoTextFormField: View {
  init(
    label: String,
    text: Binding<String>,
    prompt: String? = nil,
    axis: Axis = .horizontal,
    errorMessage: String? = nil,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil,
    accessibilityIdentifier: String
  )
}

struct RentivoSecureFormField: View {
  init(
    label: String,
    text: Binding<String>,
    isRevealed: Binding<Bool>,
    errorMessage: String? = nil,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil,
    textContentType: UITextContentType,
    accessibilityIdentifier: String
  )
}

struct RentivoCurrencyField: View {
  init(
    label: String,
    amountInCents: Binding<Int>,
    errorMessage: String? = nil,
    isFocused: Binding<Bool>? = nil,
    isAccessibilityFocused: Binding<Bool>? = nil,
    accessibilityIdentifier: String
  )
}
```

Requisitos da composição:

- `RentivoFormField` aceita `TextField`, `SecureField`, `Picker`, `DatePicker`, `Stepper` ou outro controle como conteúdo.
- Wrappers especializados devem usar o mesmo container; não duplicar desenho de borda em cada tipo.
- Modificadores de teclado, capitalização e `textContentType` continuam configuráveis por contexto.
- O identificador existente deve permanecer no controle focável. Adicionar um identificador ao container não pode quebrar os UI tests atuais.
- `RentivoSecureFormField` inclui o botão trailing de reveal; ele não cria uma segunda label nem perde foco/valor ao alternar.
- O atual `CurrencyCentavosField` deve ser substituído/renomeado internamente para a API em inglês acima, sem duplicar o parser. Os modelos existentes podem continuar usando `centavos` para evitar um refactor de domínio fora de escopo.

### Matriz de adoção

| Fluxo | Controles que devem adotar o campo |
| --- | --- |
| Cobrança | Nome, descrição, responsável, descrição/tipo/valor de cada item, tipo/chave PIX/nome/cidade, nome/e-mail de cada destinatário e contato de resposta. |
| Fatura | Mês, ano, vencimento, descrição/valor de linhas editáveis e observações. Linhas fixas somente leitura continuam como review rows. |
| Despesa | Descrição, categoria, valor e data. |
| Organização | Nome, tipo/chave PIX, nome do recebedor e cidade. |
| Convite | E-mail e função. |
| Comunicação | Tipo, assunto, corpo e escolha de salvar modelo. A coleção de destinatários continua como toggles com label próprio. |
| Chave de API | Nome e expiração. Coleções de escopos e acessos continuam como toggles com label próprio. |
| Dados e PIX | Tipo, chave, nome do recebedor e cidade. |
| Alterar senha | Senha atual, nova senha e confirmação. |

Toggles, listas de toggles e review rows não recebem uma borda de text field. Eles devem continuar semanticamente separados por label/section e manter área de toque mínima de 44×44 pt.

## Comportamento por finding

### 1. “Alterar senha” em uma tela

Substituir `RentivoFormWizard` em `ChangePasswordView` por uma única `NavigationStack` apresentada em tela cheia, com o mesmo fundo, título e affordance de fechar. Não exibir “Etapa”, segmentos, `Voltar` ou `Continuar`.

A tela contém, nesta ordem:

1. `Senha atual`;
2. `Nova senha`;
3. `Confirmar nova senha`;
4. uma única CTA primária fixa no rodapé: `Alterar senha`.

Cada campo começa oculto e tem controle independente de mostrar/ocultar. Alternar visibilidade preserva conteúdo, foco, posição de edição e `textContentType`. `Senha atual` usa `.password`; nova senha e confirmação usam `.newPassword`. Return navega para o próximo campo; no terceiro campo, aciona a mesma validação da CTA quando possível.

Ao tocar `Alterar senha`:

- validar na ordem visual;
- mostrar a mensagem no slot do primeiro campo inválido e mover foco de teclado e VoiceOver para ele;
- usar `BcryptPasswordRules.limitMessage` sem alterar a regra de 72 bytes;
- mostrar falha não mapeável do servidor inline sob os campos, com o título `Não foi possível alterar`;
- durante o request, desabilitar campos, reveal buttons, fechar e CTA; a CTA mantém o texto e adiciona `ProgressView`;
- no sucesso, limpar os três valores, fechar e manter o aviso existente `Senha alterada com sucesso.`.

Se houver qualquer valor digitado, fechar pede a confirmação de descarte já usada pelo wizard. Não existe etapa de revisão e o texto de valores ocultos é removido.

### 2. “Dados e PIX” em três etapas úteis

#### Etapa 1 — Chave

- Exibir primeiro o campo de seleção `Tipo de chave` e depois `Chave PIX`.
- O tipo controla teclado, máscara, normalização e validação conforme a tabela de PIX abaixo.
- Continuar somente com chave não vazia e válida para o tipo.
- Substituir a instrução de deixar campos vazios pelo subtítulo: `Escolha o tipo e informe a chave usada para receber pagamentos.`
- Se o perfil carregado já tinha uma configuração, exibir `Remover chave` abaixo do grupo, separado visualmente e com role destrutiva. Não mostrar a ação para perfil sem chave, antes do carregamento, durante salvamento ou no modo visualizador.

`Remover chave` não limpa o draft para depois salvá-lo. Após confirmação, chama diretamente o fluxo atual de update com `nil`, mostra progresso, fecha no sucesso e mantém `PIX pessoal removido.`. Em falha, mantém a tela aberta e mostra o erro inline. Assim um formulário vazio nunca é um comando destrutivo implícito.

No modo visualizador, a navegação não exige corrigir uma configuração ausente ou legada que o usuário não pode editar: `Continuar` permanece disponível para consulta, sem habilitar salvamento nem remoção.

#### Etapa 2 — Recebedor

- Manter `Nome do recebedor` e `Cidade` no mesmo passo, ambos com o novo campo visual.
- Manter os limites atuais de 25 e 15 escalares Unicode e o comportamento de capitalização atual da cidade.
- Associar erro a cada campo, em vez de uma mensagem única solta abaixo dos dois.
- Manter a explicação de herança atual.

#### Etapa 3 — Revisão

- Manter a seção `Conta` com `E-mail`.
- Remover a row `Ambiente` em todos os modos.
- Na seção `PIX pessoal`, mostrar `Tipo da chave`, `Chave`, `Recebedor` e `Cidade`.
- `Chave` começa parcialmente mascarada e inclui o botão visível `Mostrar chave`; quando revelada, mostrar a chave normalizada e trocar o botão para `Ocultar chave`.
- Voltar e editar reoculta a chave. Reabrir o fluxo também começa oculto.
- A ação final é sempre `Salvar PIX` no modo editável. `Limpar PIX` deixa de existir; remoção só ocorre pela ação destrutiva explícita.
- No modo visualizador, preservar `Concluir`, campos desabilitados e ausência da ação destrutiva.

### 3. Affordance de campo em todos os wizards

Implementar o componente e os estados definidos em [DesignSystem: campo de formulário](#designsystem-campo-de-formulário) antes de migrar telas individuais. A migração é parte do mesmo change set e cobre integralmente a [matriz de adoção](#matriz-de-adoção).

Nenhum `TextField`, `SecureField`, campo monetário, `Picker`, `DatePicker` ou `Stepper` editável listado na matriz pode permanecer diretamente no card sem label persistente e contorno próprio. Review rows, toggles e coleções de toggles seguem as exceções já definidas. A validação deve alimentar o slot de erro do campo, preservando os focus rules atuais e removendo painéis agregados quando já existe um controle único para o problema.

### 4. Chave PIX: tipo, máscara, validação, revisão e remoção

Adicionar `PixKeyType` e `PixKeyInput`/equivalente ao domínio de formulário. Os casos de código são `.cpf`, `.cnpj`, `.email`, `.phone` e `.random`; os labels são PT-BR. `PixConfiguration` e os DTOs continuam sem propriedade de tipo.

| Tipo | Teclado | Edição/máscara | Normalizado enviado | Validação local |
| --- | --- | --- | --- | --- |
| CPF | `.numberPad` | `000.000.000-00`, máximo 11 dígitos | 11 dígitos | Exatamente 11 dígitos. Não adicionar checksum que o backend atual não aplica. |
| CNPJ | `.numberPad` | `00.000.000/0000-00`, máximo 14 dígitos | 14 dígitos | Exatamente 14 dígitos. Não adicionar checksum que o backend atual não aplica. |
| E-mail | `.emailAddress` | Sem máscara; capitalização e correção desativadas | Trim + lowercase | Um `@`, partes não vazias, domínio com ponto e nenhum espaço, em paridade com o backend. |
| Telefone | `.phonePad` | Prefixo `+55` e máscara dinâmica `+55 (00) 0000-0000` ou `+55 (00) 00000-0000` | `+55` + DDD + 8 ou 9 dígitos | 10 ou 11 dígitos nacionais; aceitar paste já iniciado por `+55`. O seletor elimina a ambiguidade de 11 dígitos com CPF. |
| Aleatória | `.asciiCapable` | UUID `00000000-0000-0000-0000-000000000000`; hífens automáticos; lowercase | UUID lowercase com hífens | 32 hex digits no formato UUID 8-4-4-4-12. |

Regras comuns:

- Digitação e paste ignoram separadores permitidos do tipo e nunca incorporam caracteres além do limite.
- A máscara é somente apresentação; o draft conserva valor canônico suficiente para não perder dígitos ao reformatar.
- Ao carregar uma chave existente, inferir na mesma ordem do backend: CPF, CNPJ, e-mail, telefone, aleatória. Um número canônico de 11 dígitos é CPF; telefone persistido começa em `+55`.
- Se uma chave legada não puder ser classificada, preservar o texto, selecionar `Aleatória` como fallback visual e exigir correção antes do próximo save; nunca apagar ou normalizar silenciosamente no load.
- Se o usuário tentar mudar o tipo com chave não vazia, pedir confirmação. Confirmar limpa somente a chave e foca seu campo; cancelar restaura o tipo anterior.
- As regras compartilhadas devem ser usadas por perfil, organização e override da cobrança. Nenhuma tela implementa regex própria.
- A configuração enviada usa somente a chave normalizada. O backend continua sendo a autoridade final.

Máscara inicial na revisão:

- CPF: `***.***.***-01`;
- CNPJ: `**.***.***/****-90`;
- e-mail: preservar primeiro e último caractere da parte local quando existirem e o domínio, por exemplo `a••••e@example.com`;
- telefone: `+55 (**) *****-4321` ou equivalente de 8 dígitos;
- aleatória: ocultar tudo exceto os quatro últimos caracteres.

O valor mascarado não deve ser a única representação acessível. VoiceOver anuncia `Chave PIX oculta, final <últimos caracteres>`; ao revelar, anuncia `Chave PIX exibida` e permite ler o valor normalizado.

Também incluir tipo e chave mascarada/revelável nas revisões de organização e cobrança quando elas usam PIX próprio. Isso permite detectar um tipo ou dígito incorreto antes do commit.

### 5. Chave de API em quatro etapas

Remover o caso/descriptor `.expiration` isolado e usar esta ordem:

1. `Identificação`;
2. `Escopos e validade`;
3. `Acessos`;
4. `Revisão`.

Na segunda etapa, manter `Escopos seguros` e adicionar abaixo uma segunda `RentivoWizardSection` chamada `Validade da chave`. Para criação, ela contém o `DatePicker` editável com label persistente `Expira em`. Para edição, mostra a data existente somente para leitura e mantém a explicação de que ela não pode ser alterada.

Justificativa: escopos e expiração são limites de segurança e dependem do mesmo `APIKeyOptions` já carregado pela tela. Agrupá-los elimina uma etapa com um único controle sem transformar a revisão em etapa editável. A revisão continua somente leitura e conserva nome, quantidade de escopos, acessos e data.

Validar primeiro a seleção de escopos e depois a disponibilidade/intervalo da data. Em erro, permanecer na etapa 2 e focar a primeira origem do erro. `Etapa N de M`, segmentos e barra inferior passam automaticamente a usar total 4.

### 6. Chrome dos wizards restantes

Preservar sem regressão:

- label `Etapa N de M`;
- um segmento por etapa e destaque até a etapa atual;
- título da etapa abaixo do progresso;
- `Voltar` em todas as etapas exceto a primeira;
- `Continuar` em todas as etapas exceto a última;
- CTA final específica do fluxo;
- barra inferior fixa acima da safe area;
- confirmação de descarte ao fechar depois da primeira etapa e/ou com alterações, conforme a política atual;
- botão `Voltar` disponível durante bloqueios que afetam somente o commit, como renderização do PDF.

Contagens após esta especificação:

| Fluxo | Etapas |
| --- | ---: |
| Cobrança | 5 |
| Fatura | 5 |
| Despesa | 3 |
| Comunicação | 5 |
| Organização | 3 |
| Convite | 3 |
| Dados e PIX | 3 |
| Chave de API | 4 |
| Alterar senha | Não é wizard |

### 7. Entrada monetária em centavos

`RentivoCurrencyField` é a única entrada editável de dinheiro nos fluxos abrangidos. Aplicar em:

- valor de item recorrente de cobrança;
- valor de item variável ou extra de fatura;
- valor de despesa.

Comportamento obrigatório:

- teclado numérico;
- binding inteiro em centavos, sem `Double` ou `Float`;
- valor formatado como BRL/`pt_BR` a cada tecla;
- dígitos entram da direita para a esquerda: `1` → `R$ 0,01`, `12` → `R$ 0,12`, `120000` → `R$ 1.200,00`;
- backspace remove o dígito menos significativo e reformata;
- paste de `120000` e de `R$ 1.200,00` resulta no mesmo `120_000` centavos;
- manter cursor no fim para evitar editar separadores de moeda;
- respeitar `Money.maximumPersistedCentavos` e as validações de total existentes;
- label visível `Valor` ou `Valor do item`, nunca `Valor em centavos`;
- VoiceOver anuncia label e valor monetário, por exemplo `Valor, mil e duzentos reais`, e não uma sequência crua de dígitos.

O subtotal/total deve reagir ao binding em cada tecla. Nenhum `TextField(value:format:)` numérico ou campo de string de valor pode permanecer nesses três caminhos.

## Copy PT-BR exata

Todo texto atual não listado abaixo permanece verbatim. Identificadores de acessibilidade não são customer copy e devem continuar em inglês.

### Novos textos

| Contexto | Copy exata |
| --- | --- |
| Tela única de senha — título da seção | `Defina sua nova senha` |
| Tela única de senha — subtítulo | `Informe a senha atual e escolha uma nova senha forte e exclusiva.` |
| Senha atual vazia | `Informe sua senha atual.` |
| Nova senha vazia | `Informe a nova senha.` |
| Confirmação vazia | `Confirme a nova senha.` |
| Reveal senha atual | `Mostrar senha atual` / `Ocultar senha atual` |
| Reveal nova senha | `Mostrar nova senha` / `Ocultar nova senha` |
| Reveal confirmação | `Mostrar confirmação da senha` / `Ocultar confirmação da senha` |
| Profile PIX — subtítulo da etapa chave | `Escolha o tipo e informe a chave usada para receber pagamentos.` |
| Seletor | `Tipo de chave` |
| Opções | `CPF`, `CNPJ`, `E-mail`, `Telefone`, `Aleatória` |
| Hints CPF/CNPJ | `Digite os 11 dígitos do CPF.` / `Digite os 14 dígitos do CNPJ.` |
| Hint telefone | `Informe DDD e número. O +55 será adicionado ao salvar.` |
| Hint aleatória | `Cole a chave aleatória no formato UUID.` |
| Chave vazia | `Informe a chave PIX.` |
| CPF inválido | `Informe um CPF com 11 dígitos.` |
| CNPJ inválido | `Informe um CNPJ com 14 dígitos.` |
| E-mail inválido | `Informe um e-mail válido.` |
| Telefone inválido | `Informe um telefone com DDD.` |
| Aleatória inválida | `Informe uma chave aleatória válida no formato UUID.` |
| Tipo incompatível/legado | `Esta chave não corresponde ao tipo selecionado.` |
| Nome do recebedor vazio | `Informe o nome do recebedor.` |
| Cidade do recebedor vazia | `Informe a cidade do recebedor.` |
| Nome do recebedor longo | `O nome do recebedor deve ter até 25 caracteres.` |
| Cidade do recebedor longa | `A cidade do recebedor deve ter até 15 caracteres.` |
| Troca de tipo — título | `Alterar tipo de chave?` |
| Troca de tipo — mensagem | `A chave digitada será apagada para evitar que seja interpretada no formato errado.` |
| Troca de tipo — ações | `Alterar e apagar` / `Cancelar` |
| Reveal PIX | `Mostrar chave` / `Ocultar chave` |
| PIX oculto no VoiceOver | `Chave PIX oculta, final <últimos caracteres>` |
| PIX revelado no VoiceOver | `Chave PIX exibida` |
| Estado inválido no VoiceOver | `Inválido` |
| Remoção PIX — botão e confirmação destrutiva | `Remover chave` |
| Remoção PIX — título | `Remover chave PIX?` |
| Remoção PIX — mensagem | `As cobranças pessoais que herdam esta configuração ficarão sem PIX até que outra chave seja cadastrada.` |
| API key — etapa 2 | `Escopos e validade` |
| Label monetária genérica | `Valor` |

### Textos removidos ou substituídos

- Remover os descriptors `Senha atual`, `Nova senha` e `Revisão` do fluxo de senha, bem como `Confirme sua identidade`, `Escolha a nova senha`, `Confirmação de segurança` e o texto que explica que os valores estão ocultos.
- Substituir `Informe e confirme a nova senha.` pelas mensagens específicas de campo acima.
- Remover `Deixe a chave e os dados do recebedor vazios para remover a configuração atual.`
- Substituir as mensagens combinadas de recebedor PIX pelas quatro mensagens específicas de campo acima.
- Remover a row e label `Ambiente` da revisão de Dados e PIX.
- Remover a CTA `Limpar PIX`.
- Substituir o descriptor de API key `Escopos` por `Escopos e validade` e remover o descriptor `Expiração`; os títulos internos atuais `Escopos seguros` e `Validade da chave` permanecem.
- Substituir todas as ocorrências de label editável `Valor em centavos` por `Valor`.

## Validação e roteamento de erros

- `Continuar` valida apenas a etapa atual; commit revalida todo o draft como defesa em profundidade.
- O primeiro campo inválido recebe foco visual, foco de teclado e `AccessibilityFocusState`.
- A mensagem aparece no `errorMessage` do campo que causou o erro. Painéis agregados podem permanecer apenas para erros de coleção sem controle único, como “Adicione ao menos um item recorrente”, e para falhas de servidor sem field path.
- Em listas repetíveis, associar o erro à primeira row inválida e manter os índices/IDs estáveis durante reordenação.
- Ao navegar para trás, preservar valores e erros; ao corrigir um erro, removê-lo sem apagar outros erros.
- Campo de PIX é validado antes de nome/cidade. Em seguida, nome e cidade mantêm os limites atuais.
- O request final sempre usa strings normalizadas, mas a normalização não pode concatenar conteúdo entre bindings nem mover texto de um campo para outro.

## Acessibilidade

- Cada controle tem uma label acessível persistente igual à label visual; placeholder não participa como única label.
- Label, controle, hint e erro formam um grupo sem fundir dois campos adjacentes em um único elemento.
- Erro usa texto e ícone além da cor, acrescenta `Inválido` ao valor acessível e é anunciado ao surgir.
- A ordem de foco segue a ordem visual, inclusive em items/destinatários repetíveis.
- Botões de reveal têm área mínima de 44×44 pt, estado selecionado e labels específicas. Não anunciar apenas “olho”.
- Conteúdo de senha nunca entra no label, valor acessível ou logs, mesmo revelado visualmente.
- Chave PIX mascarada não é anunciada como uma longa sequência de bullets; usar a frase de final conhecido definida acima.
- Dynamic Type até tamanhos de acessibilidade não pode truncar labels, mensagens, valores de review ou botões. Labels podem quebrar linha; campos e cards crescem verticalmente.
- O contraste dos estados deve atender WCAG AA no fundo `paper`; foco e erro também são distinguíveis sem cor.
- Campos mantêm área mínima de 48 pt e botões/toggles ao menos 44×44 pt.
- Com teclado aberto, o campo focado e sua mensagem permanecem visíveis; a barra inferior não cobre o erro. `ScrollView` deve rolar até o primeiro inválido.
- Teclados de e-mail, telefone e número não podem impedir o acesso a `Voltar`, `Continuar` ou à CTA final.

## Acceptance criteria

1. Ao abrir “Alterar senha”, os três campos estão na mesma tela, não existe texto `Etapa`, não existem segmentos nem botão `Continuar`, e existe somente uma CTA primária `Alterar senha`.
2. Cada campo de senha pode ser revelado/ocultado independentemente sem perder valor ou foco; a submissão inválida foca e marca somente o primeiro campo inválido.
3. Nenhuma revisão vazia ou texto de senha redigida permanece no app.
4. “Dados e PIX” continua exibindo `Etapa 1 de 3`, `Etapa 2 de 3` e `Etapa 3 de 3`; a primeira etapa possui tipo e chave, a segunda recebedor e cidade, e a terceira dados efetivamente conferíveis.
5. A revisão de PIX não exibe `Ambiente`; começa com chave parcialmente mascarada e alterna corretamente entre `Mostrar chave` e `Ocultar chave`.
6. `Remover chave` só aparece quando uma configuração de perfil persistida existe e nunca no modo visualizador. Confirmá-la envia remoção explícita; deixar campos vazios não remove nada.
7. CPF, CNPJ, e-mail, telefone e aleatória usam o teclado, máscara, validação, normalização e copy definidos. Perfil, organização e cobrança compartilham a mesma regra.
8. O payload de PIX continua usando os campos atuais e recebe a chave normalizada; não há mudança de OpenAPI/DTO.
9. Todo campo de entrada abrangido pela matriz possui label persistente e contorno próprio em repouso. Dois campos adjacentes nunca aparecem como duas linhas de texto nuas.
10. Foco e erro são visíveis conforme os estados do DesignSystem; a mensagem pertence ao campo correto e o primeiro erro recebe foco de teclado e VoiceOver.
11. O cenário de QA permite digitar `Apartamento 202`, `Aluguel e encargos apartamento 202`, `Aluguel` e `120000` em quatro controles distintos; a revisão/payload preserva exatamente as três strings e mostra `R$ 1.200,00`.
12. Digitar `120000` em qualquer campo monetário mostra `R$ 1.200,00` durante a edição e mantém `120_000` no binding. Nenhuma UI mostra o número cru nem a label `Valor em centavos`.
13. O wizard de chave de API mostra total 4, com `Escopos e validade` na etapa 2; a expiração não possui etapa isolada e a revisão permanece somente leitura.
14. Cobrança, fatura, despesa, comunicação, organização, convite, Dados e PIX e API key preservam `Etapa N de M`, segmentos e barra `Voltar`/`Continuar` conforme suas contagens.
15. Identificadores de acessibilidade existentes continuam resolvendo o controle correspondente ou são migrados com atualização explícita dos UI tests no mesmo change set.
16. O layout passa inspeção em iPhone SE e iPhone 15 Pro, portrait, com tamanho de texto padrão e pelo menos um tamanho de acessibilidade, sem corte ou sobreposição.

## Test plan

### Unit tests

1. `PixKeyInputRulesTests`
   - inferir cada um dos cinco tipos de uma chave persistida;
   - formatar e normalizar CPF/CNPJ com e sem pontuação;
   - rejeitar comprimentos incorretos com a mensagem exata;
   - normalizar e-mail com trim/lowercase e rejeitar espaço/domínio inválido;
   - aceitar telefone nacional de 10/11 dígitos no contexto `.phone`, prefixar `+55` e aceitar paste canônico;
   - preservar a regra de que 11 dígitos persistidos sem `+55` são inferidos como CPF;
   - inserir hífens e lowercase em UUID e rejeitar hexadecimal incompleto/inválido;
   - produzir as cinco máscaras de revisão sem expor mais caracteres que o definido;
   - preservar chave legada no load e bloqueá-la no save;
   - confirmar que trocar tipo com conteúdo requer limpeza explícita.
2. `NativeFormContractTests`/`ValidationTests`
   - perfil exige configuração completa para salvar;
   - `.inherit` continua válido para cobrança/organização quando o toggle de PIX próprio está desligado;
   - configuração própria rejeita chave incompatível antes dos dados do recebedor;
   - nome/cidade continuam respeitando 25/15 escalares;
   - `PixConfiguration` e DTOs permanecem wire-compatible.
3. `MoneyTests`
   - parser de `1`, `12`, `120000` e `R$ 1.200,00`;
   - backspace e zero;
   - overflow continua limitado por `Money.maximumPersistedCentavos`;
   - não há round-trip por floating point.
4. Regras de navegação
   - API key possui exatamente quatro descriptors na ordem definida;
   - política de título continua retornando `Continuar` antes do último passo e a CTA final no último;
   - senha não instancia `RentivoFormWizard`.

### UI tests automatizados

1. Senha
   - abrir Conta → Segurança → Alterar senha;
   - confirmar ausência de `Etapa 1 de 3` e presença simultânea dos três identificadores atuais;
   - validar foco/mensagem de cada campo vazio e mismatch;
   - alternar os três reveal buttons e verificar preservação do texto;
   - submeter com sucesso e verificar `Senha alterada com sucesso.`.
2. Dados e PIX
   - verificar `Etapa 1 de 3` e seletor de tipo;
   - para cada tipo, digitar/pastar uma chave, verificar texto mascarado e review normalizado;
   - confirmar que `Ambiente` não existe e que reveal reoculta ao voltar;
   - com chave persistida, confirmar ação e diálogo `Remover chave`; sem chave, confirmar ausência;
   - no modo visualizador, confirmar campos bloqueados e ausência de remoção.
3. Regressão de concatenação na cobrança
   - preencher nome com `Apartamento 202` e descrição com `Aluguel e encargos apartamento 202`;
   - adicionar item `Aluguel`, digitar `120000` no valor e confirmar `R$ 1.200,00` antes de sair do campo;
   - avançar e verificar review/objeto criado sem concatenação entre os quatro valores.
4. Fatura e despesa
   - atualizar o query do campo de despesa de `Valor em centavos` para label/identifier `Valor`;
   - digitar `1000` e verificar `R$ 10,00` antes de avançar;
   - testar ao menos uma linha de fatura com `120000` → `R$ 1.200,00`.
5. Comunicação, convite e organização
   - provocar erro em assunto/corpo, e-mail e nome/chave PIX; confirmar borda/erro associado e foco no controle correto;
   - confirmar que o chrome e as contagens existentes não mudaram.
6. Chave de API
   - confirmar `Etapa 1 de 4` ao abrir;
   - etapa 2 contém escopos e `Expira em`;
   - avançar diretamente de etapa 2 para `Acessos` e depois `Revisão`;
   - em edição, expiração é somente leitura.

### Verificação visual e manual

- Criar previews do campo nos estados normal, foco, erro, erro+foco, desabilitado, multiline, secure e currency.
- Inspecionar todos os fluxos da matriz em iPhone SE e iPhone 15 Pro, portrait.
- Repetir com tamanho de texto padrão e Accessibility Extra Extra Extra Large.
- Com VoiceOver, percorrer label → controle → hint/erro; confirmar que campos adjacentes não são combinados e que o primeiro inválido recebe foco.
- Verificar contraste de `ink`, `emerald` e `coral` sobre `paper` e distinção com “Diferenciar sem cor”.
- Testar hardware keyboard e teclados `.numberPad`, `.phonePad`, `.emailAddress` e `.asciiCapable`.
- Testar paste, backspace, mudança de tipo e rotação/reentrada do app sem vazamento de senha ou chave em logs/screenshots de estado.
- Rodar `make ios-test` e os UI tests do scheme `Rentivo` no simulador antes do merge.

## Definition of done

A mudança está pronta quando todos os acceptance criteria estão cobertos por teste automatizado ou por evidência manual registrada, nenhum fluxo abrangido contém campo de texto nu, a regressão de concatenação está reproduzida e protegida por teste, e não existe alteração no contrato de rede de PIX.
