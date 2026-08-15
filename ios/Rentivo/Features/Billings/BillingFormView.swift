import SwiftUI

private struct EditableBillingItem: Identifiable {
  let id: BillingItemID
  var description: String
  var centavos: Int
  var type: BillingItemType

  init(item: BillingItem) {
    id = item.id
    description = item.description
    centavos = item.type.normalizedTemplateAmount(item.amount.centavos)
    type = item.type
  }

  init(type: BillingItemType = .fixed) {
    id = BillingItemID(rawValue: UUID().uuidString)
    description = ""
    centavos = 0
    self.type = type
  }

  func domain(sortOrder: Int) -> BillingItem {
    BillingItem(
      id: id,
      description: description,
      amount: Money(centavos: centavos),
      type: type,
      sortOrder: sortOrder
    )
  }
}

private struct EditableRecipient: Identifiable {
  let id: RecipientID
  var name: String
  var email: String

  init(recipient: BillingRecipient) {
    id = recipient.id
    name = recipient.name
    email = recipient.email
  }

  init() {
    id = RecipientID(rawValue: UUID().uuidString)
    name = ""
    email = ""
  }

  var isBlank: Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func domain() -> BillingRecipient {
    BillingRecipient(
      id: id,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      email: email.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}

struct BillingFormView: View {
  private enum Step: CaseIterable {
    case essentials
    case items
    case pix
    case communication
    case review

    var title: String {
      switch self {
      case .essentials: "Essenciais"
      case .items: "Itens recorrentes"
      case .pix: "PIX"
      case .communication: "Comunicação"
      case .review: "Revisão"
      }
    }
  }

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  private let billing: Billing?
  private let onSaved: () async -> Void

  @State private var name: String
  @State private var billingDescription: String
  @State private var ownerID: WorkspaceID
  @State private var items: [EditableBillingItem]
  @State private var pixKey: String
  @State private var pixMerchantName: String
  @State private var pixMerchantCity: String
  @State private var recipients: [EditableRecipient]
  @State private var replyTo: [EditableRecipient]
  @State private var step: Step = .essentials
  @State private var validationIssues: [ValidationIssue] = []
  @State private var pixRecipientRequiredMessage: String?
  /// Server-side rejection (e.g. a 422) for the last submit. It lives here instead of in the
  /// global notice banner because this form is presented in a sheet, and the banner renders
  /// behind it — the user would never see it.
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @State private var organizations: [Organization] = []
  @State private var organizationsLoaded: Bool

  init(billing: Billing? = nil, onSaved: @escaping () async -> Void) {
    self.billing = billing
    self.onSaved = onSaved
    _name = State(initialValue: billing?.name ?? "")
    _billingDescription = State(initialValue: billing?.description ?? "")
    _ownerID = State(initialValue: billing?.owner.id ?? .personal)
    _items = State(initialValue: billing?.items.map(EditableBillingItem.init) ?? [])
    _pixKey = State(initialValue: billing?.pixOverride?.key ?? "")
    _pixMerchantName = State(initialValue: billing?.pixOverride?.merchantName ?? "")
    _pixMerchantCity = State(initialValue: billing?.pixOverride?.merchantCity ?? "")
    _recipients = State(initialValue: billing?.recipients.map(EditableRecipient.init) ?? [])
    _replyTo = State(initialValue: billing?.replyTo.map(EditableRecipient.init) ?? [])
    _organizationsLoaded = State(initialValue: billing != nil)
  }

  var body: some View {
    RentivoFormWizard(
      title: billing == nil ? "Nova cobrança" : "Editar cobrança",
      descriptors: Step.allCases.map { RentivoWizardStepDescriptor(id: $0, title: $0.title) },
      selectedStep: $step,
      isDirty: isDirty,
      isBusy: saving,
      primaryTitle: step == .review ? "Salvar cobrança" : "Continuar",
      onValidateAndAdvance: validateCurrentStep,
      onCommit: { Task { await save() } }
    ) { step in
      stepContent(step)
    }
    .interactiveDismissDisabled(saving)
    .task {
      guard billing == nil else { return }
      organizations = (try? await app.dependencies.organizations.listOrganizations()) ?? []
      organizationsLoaded = true
    }
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .essentials:
      RentivoWizardSection("Identificação", subtitle: "Defina a cobrança e seu responsável.") {
        TextField("Nome", text: $name)
          .accessibilityIdentifier("billing.form.name")
        TextField("Descrição", text: $billingDescription, axis: .vertical)
          .lineLimit(2...4)
        if billing == nil {
          Picker("Responsável", selection: $ownerID) {
            ForEach(ownerChoices, id: \.id) { owner in
              Text(owner.name).tag(owner.id)
            }
          }
        }
        validationPanel
      }

    case .items:
      RentivoWizardSection(
        "Itens recorrentes",
        subtitle: "Use valor zero para itens variáveis que serão preenchidos em cada fatura."
      ) {
        ForEach(Array(items.indices), id: \.self) { index in
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            HStack {
              Text("Item \(index + 1)")
                .font(.subheadline.weight(.semibold))
              Spacer()
              Button("Remover", role: .destructive) {
                items.remove(at: index)
              }
              .accessibilityIdentifier("billing.form.item.\(index).remove")
            }
            TextField("Descrição do item", text: $items[index].description)
              .accessibilityIdentifier("billing.form.item.\(index).description")
            Picker("Tipo", selection: $items[index].type) {
              ForEach(BillingItemType.allCases, id: \.self) { type in
                Text(type.label).tag(type)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("billing.form.item.\(index).type")
            .onChange(of: items[index].type) { _, type in
              items[index].centavos = type.normalizedTemplateAmount(items[index].centavos)
            }
            if items[index].type.showsTemplateAmount {
              CurrencyCentavosField("Valor do item", centavos: $items[index].centavos)
                .accessibilityIdentifier("billing.form.item.\(index).amount")
            }
          }
          .padding(.vertical, RentivoSpacing.tiny)
        }
        Button {
          items.append(EditableBillingItem())
        } label: {
          Label("Adicionar item", systemImage: "plus.circle.fill")
        }
        .accessibilityIdentifier("billing.form.items.add")
        HStack {
          Text("Subtotal fixo")
            .foregroundStyle(RentivoColors.secondaryInk)
          Spacer()
          MoneyText(money: fixedSubtotal)
        }
        validationPanel
      }

    case .pix:
      RentivoWizardSection("PIX opcional", subtitle: "Deixe em branco para herdar o PIX do responsável.") {
        TextField("Chave PIX própria", text: $pixKey)
          .textInputAutocapitalization(.never)
          .accessibilityIdentifier("billing.form.pix.key")
        if !pixKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          TextField("Nome do recebedor", text: $pixMerchantName)
            .accessibilityIdentifier("billing.form.pix.merchantName")
          TextField("Cidade do recebedor", text: $pixMerchantCity)
            .textInputAutocapitalization(.characters)
            .accessibilityIdentifier("billing.form.pix.merchantCity")
        }
        validationPanel
      }

    case .communication:
      Group {
        RentivoWizardSection("Destinatários", subtitle: "Todos os destinatários recebem as comunicações desta cobrança.") {
          ForEach(Array(recipients.indices), id: \.self) { index in
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              HStack {
                Text("Destinatário \(index + 1)")
                  .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Remover", role: .destructive) {
                  recipients.remove(at: index)
                }
                .accessibilityIdentifier("billing.form.recipient.\(index).remove")
              }
              TextField("Nome do destinatário", text: $recipients[index].name)
                .accessibilityIdentifier("billing.form.recipient.\(index).name")
              TextField("E-mail do destinatário", text: $recipients[index].email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("billing.form.recipient.\(index).email")
            }
            .padding(.vertical, RentivoSpacing.tiny)
          }
          Button {
            recipients.append(EditableRecipient())
          } label: {
            Label("Adicionar destinatário", systemImage: "plus.circle.fill")
          }
          .accessibilityIdentifier("billing.form.recipients.add")
        }

        RentivoWizardSection("Responder para", subtitle: "Opcionalmente, defina contatos que receberão as respostas.") {
          ForEach(Array(replyTo.indices), id: \.self) { index in
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              HStack {
                Text("Contato de resposta \(index + 1)")
                  .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Remover", role: .destructive) {
                  replyTo.remove(at: index)
                }
                .accessibilityIdentifier("billing.form.reply-to.\(index).remove")
              }
              TextField("Nome para resposta", text: $replyTo[index].name)
                .accessibilityIdentifier("billing.form.reply-to.\(index).name")
              TextField("E-mail para resposta", text: $replyTo[index].email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("billing.form.reply-to.\(index).email")
            }
            .padding(.vertical, RentivoSpacing.tiny)
          }
          Button {
            replyTo.append(EditableRecipient())
          } label: {
            Label("Adicionar contato de resposta", systemImage: "plus.circle.fill")
          }
          .accessibilityIdentifier("billing.form.reply-to.add")
          validationPanel
        }
      }

    case .review:
      RentivoWizardSection("Revise sua cobrança") {
        RentivoWizardReviewRow(label: "Nome", value: displayName)
        RentivoWizardReviewRow(label: "Responsável", value: selectedOwner?.name ?? "Não informado")
        RentivoWizardReviewRow(label: "Itens", value: ptBRCount(items.count, singular: "item", plural: "itens"))
        RentivoWizardReviewRow(label: "Subtotal fixo", value: fixedSubtotal.formatted())
        RentivoWizardReviewRow(
          label: "PIX",
          value: pixKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Herdado" : "Próprio"
        )
        RentivoWizardReviewRow(
          label: "Destinatários",
          value: ptBRCount(nonBlankRecipients.count, singular: "destinatário", plural: "destinatários")
        )
        RentivoWizardReviewRow(
          label: "Responder para",
          value: ptBRCount(nonBlankReplyTo.count, singular: "contato", plural: "contatos")
        )
        validationPanel
      }
    }
  }

  @ViewBuilder
  private var validationPanel: some View {
    if !validationIssues.isEmpty || pixRecipientRequiredMessage != nil || submitErrorMessage != nil {
      VStack(alignment: .leading, spacing: RentivoSpacing.small) {
        Text("Revise os campos")
          .font(.subheadline.weight(.semibold))
        ForEach(validationIssues, id: \.self) { issue in
          validationMessage(issue.message)
        }
        if let pixRecipientRequiredMessage { validationMessage(pixRecipientRequiredMessage) }
        if let submitErrorMessage { validationMessage(submitErrorMessage) }
      }
    }
  }

  private func validationMessage(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("billing.form.validation")
  }

  private var ownerChoices: [BillingOwner] {
    var owners: [BillingOwner] = [
      .user(id: app.currentUser.id, name: "Pessoal")
    ]
    let existingIDs = Set(owners.map(\.id))
    let organizationOwners = organizations
      .compactMap(\.billingOwnerForCreation)
      .filter { !existingIDs.contains($0.id) }
    owners.append(contentsOf: organizationOwners)
    return owners
  }

  private var selectedOwner: BillingOwner? {
    billing?.owner ?? ownerChoices.first(where: { $0.id == ownerID })
  }

  private var fixedSubtotal: Money {
    items.lazy
      .filter { $0.type == .fixed }
      .map { Money(centavos: $0.centavos) }
      .reduce(.zero, +)
  }

  private var nonBlankRecipients: [EditableRecipient] { recipients.filter { !$0.isBlank } }
  private var nonBlankReplyTo: [EditableRecipient] { replyTo.filter { !$0.isBlank } }

  private var displayName: String {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? "Não informado" : normalized
  }

  private var isDirty: Bool {
    if billing == nil {
      return !name.isEmpty || !billingDescription.isEmpty || ownerID != .personal || !items.isEmpty
        || !pixKey.isEmpty || !pixMerchantName.isEmpty || !pixMerchantCity.isEmpty
        || !recipients.isEmpty || !replyTo.isEmpty
    }
    guard let billing else { return false }
    return name != billing.name || billingDescription != billing.description
      || pixKey != (billing.pixOverride?.key ?? "")
      || pixMerchantName != (billing.pixOverride?.merchantName ?? "")
      || pixMerchantCity != (billing.pixOverride?.merchantCity ?? "")
      || items.count != billing.items.count
      || recipients.count != billing.recipients.count
      || replyTo.count != billing.replyTo.count
      || zip(items, billing.items).contains {
        $0.description != $1.description || $0.centavos != $1.type.normalizedTemplateAmount($1.amount.centavos)
          || $0.type != $1.type
      }
      || zip(recipients, billing.recipients).contains { $0.name != $1.name || $0.email != $1.email }
      || zip(replyTo, billing.replyTo).contains { $0.name != $1.name || $0.email != $1.email }
  }

  private func currentDraft() -> BillingDraft? {
    guard let selectedOwner else { return nil }
    let pix = pixKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return BillingDraft(
      name: name,
      description: billingDescription,
      owner: selectedOwner,
      items: items.enumerated().map { $0.element.domain(sortOrder: $0.offset) },
      pixOverride: pix.isEmpty
        ? nil
        : PixConfiguration(
          key: pix,
          merchantName: pixMerchantName.trimmingCharacters(in: .whitespacesAndNewlines),
          merchantCity: pixMerchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
      recipients: nonBlankRecipients.map { $0.domain() },
      replyTo: nonBlankReplyTo.map { $0.domain() }
    )
  }

  private func validateCurrentStep() -> Bool {
    submitErrorMessage = nil
    switch step {
    case .essentials: return validateEssentials()
    case .items: return validateItems()
    case .pix: return validatePIX()
    case .communication: return validateCommunication()
    case .review: return true
    }
  }

  private func validateEssentials() -> Bool {
    validate(fields: [.name, .description])
  }

  private func validateItems() -> Bool {
    validate(fields: [.items, .itemDescription, .itemAmount])
  }

  private func validatePIX() -> Bool {
    pixRecipientRequiredMessage = pixRecipientRequiredMessageForCurrentFields
    let isValid = validate(fields: [.pix])
    return isValid && pixRecipientRequiredMessage == nil
  }

  private func validateCommunication() -> Bool {
    validate(fields: [.recipient, .replyTo])
  }

  private func validate(fields: Set<ValidationField>) -> Bool {
    validationIssues = currentDraft()?.validate().filter { fields.contains($0.field) } ?? [
      ValidationIssue(field: .name, message: "Não foi possível confirmar o responsável.")
    ]
    return validationIssues.isEmpty
  }

  private var pixRecipientRequiredMessageForCurrentFields: String? {
    let pix = pixKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pix.isEmpty else { return nil }
    let merchantName = pixMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantCity = pixMerchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    guard merchantName.isEmpty || merchantCity.isEmpty else { return nil }
    return "Informe o nome e a cidade do recebedor para usar uma chave PIX própria."
  }

  private func save() async {
    submitErrorMessage = nil
    let owner: BillingOwner
    if let billing {
      owner = billing.owner
    } else if let selected = ownerChoices.first(where: { $0.id == ownerID }) {
      owner = selected
    } else {
      submitErrorMessage = "Não foi possível confirmar o responsável."
      return
    }
    // A wholly empty row is the user leaving the "Adicionar destinatário" placeholder untouched,
    // so it is dropped rather than reported as invalid. Partially filled rows still fail
    // validation below, because the update replaces the billing's whole recipient set.
    let draftRecipients = nonBlankRecipients.map { $0.domain() }
    let draftReplyTo = nonBlankReplyTo.map { $0.domain() }
    let pix = pixKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantName = pixMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantCity = pixMerchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    pixRecipientRequiredMessage = pixRecipientRequiredMessageForCurrentFields
    let draft = BillingDraft(
      name: name,
      description: billingDescription,
      owner: owner,
      items: items.enumerated().map { $0.element.domain(sortOrder: $0.offset) },
      pixOverride: pix.isEmpty
        ? nil
        : PixConfiguration(key: pix, merchantName: merchantName, merchantCity: merchantCity),
      recipients: draftRecipients,
      replyTo: draftReplyTo
    )
    validationIssues = draft.validate()
    guard validationIssues.isEmpty && pixRecipientRequiredMessage == nil else { return }
    saving = true
    defer { saving = false }
    do {
      if let billing {
        _ = try await app.dependencies.billings.updateBilling(id: billing.id, draft: draft)
      } else {
        _ = try await app.dependencies.billings.createBilling(draft)
      }
      await onSaved()
      app.showNotice(billing == nil ? "Cobrança criada." : "Cobrança atualizada.")
      dismiss()
    } catch {
      submitErrorMessage = DemoError(error).message
    }
  }
}
