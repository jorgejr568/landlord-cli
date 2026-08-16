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

enum BillingWizardFocusRules {
  enum ItemTarget: Equatable {
    case addItem
  }

  enum PIXTarget: Equatable {
    case key
    case merchantName
    case merchantCity
  }

  enum ContactTarget: Equatable {
    case name
    case email
  }

  struct ItemAmount: Equatable {
    let type: BillingItemType
    let centavos: Int
  }

  static func pixTarget(key: String, merchantName: String, merchantCity: String) -> PIXTarget {
    if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .key }

    let normalizedMerchantName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedMerchantName.isEmpty || normalizedMerchantName.unicodeScalars.count > 25 {
      return .merchantName
    }

    let normalizedMerchantCity = merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedMerchantCity.isEmpty || normalizedMerchantCity.unicodeScalars.count > 15 {
      return .merchantCity
    }
    return .key
  }

  static func contactTarget(name: String, email: String) -> ContactTarget {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedName.isEmpty || normalizedName.unicodeScalars.count > 255 { return .name }
    return .email
  }

  static func firstFixedOverflowIndex(in items: [ItemAmount]) -> Int? {
    var fixedTotal = 0
    for (index, item) in items.enumerated() where item.type == .fixed {
      guard item.centavos >= 0 else { continue }
      if item.centavos > Money.maximumPersistedCentavos
        || fixedTotal > Money.maximumPersistedCentavos - item.centavos {
        return index
      }
      fixedTotal += item.centavos
    }
    return nil
  }

  static func itemTarget(issues: [ValidationIssue], items: [ItemAmount]) -> ItemTarget? {
    issues.contains(where: { $0.field == .items }) && items.isEmpty ? .addItem : nil
  }
}

enum BillingWizardReordering {
  enum Direction {
    case up
    case down
  }

  @discardableResult
  static func move<Element: Identifiable>(
    id: Element.ID,
    direction: Direction,
    in elements: inout [Element]
  ) -> Bool {
    guard let index = elements.firstIndex(where: { $0.id == id }) else { return false }
    let destination = direction == .up ? index - 1 : index + 1
    guard elements.indices.contains(destination) else { return false }
    elements.swapAt(index, destination)
    return true
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

  private enum FocusedField: Hashable {
    case name
    case description
    case itemDescription(Int)
    case itemAmount(Int)
    case addItem
    case pixKey
    case pixMerchantName
    case pixMerchantCity
    case recipientName(Int)
    case recipientEmail(Int)
    case replyToName(Int)
    case replyToEmail(Int)
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
  @FocusState private var focusedField: FocusedField?
  @AccessibilityFocusState private var accessibilityFocusedField: FocusedField?

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
      isBusy: saving,
      isPrimaryEnabled: organizationsLoaded,
      finalActionTitle: finalActionTitle,
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
          .focused($focusedField, equals: .name)
          .accessibilityFocused($accessibilityFocusedField, equals: .name)
          .accessibilityIdentifier("billing.form.name")
        TextField("Descrição", text: $billingDescription, axis: .vertical)
          .focused($focusedField, equals: .description)
          .accessibilityFocused($accessibilityFocusedField, equals: .description)
          .accessibilityIdentifier("billing.form.description")
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
        ForEach($items) { $item in
          let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            HStack {
              Text("Item \(index + 1)")
                .font(.subheadline.weight(.semibold))
              Spacer()
              reorderButtons(
                position: index,
                count: items.count,
                label: "item \(index + 1)",
                identifierPrefix: "billing.form.item.\(item.id.rawValue)"
              ) { direction in
                BillingWizardReordering.move(id: item.id, direction: direction, in: &items)
              }
              Button("Remover", role: .destructive) {
                items.removeAll { $0.id == item.id }
              }
              .accessibilityIdentifier("billing.form.item.\(index).remove")
            }
            TextField("Descrição do item", text: $item.description)
              .focused($focusedField, equals: .itemDescription(index))
              .accessibilityFocused($accessibilityFocusedField, equals: .itemDescription(index))
              .accessibilityIdentifier("billing.form.item.\(index).description")
            Picker("Tipo", selection: $item.type) {
              ForEach(BillingItemType.allCases, id: \.self) { type in
                Text(type.label).tag(type)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("billing.form.item.\(index).type")
            .onChange(of: item.type) { _, type in
              item.centavos = type.normalizedTemplateAmount(item.centavos)
            }
            if item.type.showsTemplateAmount {
              CurrencyCentavosField(
                "Valor do item",
                centavos: $item.centavos,
                isFocused: itemAmountFocusBinding(for: index),
                isAccessibilityFocused: itemAmountAccessibilityFocusBinding(for: index)
              )
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
        .focused($focusedField, equals: .addItem)
        .accessibilityFocused($accessibilityFocusedField, equals: .addItem)
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
          .focused($focusedField, equals: .pixKey)
          .accessibilityFocused($accessibilityFocusedField, equals: .pixKey)
          .textInputAutocapitalization(.never)
          .accessibilityIdentifier("billing.form.pix.key")
        if !pixKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          TextField("Nome do recebedor", text: $pixMerchantName)
            .focused($focusedField, equals: .pixMerchantName)
            .accessibilityFocused($accessibilityFocusedField, equals: .pixMerchantName)
            .accessibilityIdentifier("billing.form.pix.merchantName")
          TextField("Cidade do recebedor", text: $pixMerchantCity)
            .focused($focusedField, equals: .pixMerchantCity)
            .accessibilityFocused($accessibilityFocusedField, equals: .pixMerchantCity)
            .textInputAutocapitalization(.characters)
            .accessibilityIdentifier("billing.form.pix.merchantCity")
        }
        validationPanel
      }

    case .communication:
      Group {
        RentivoWizardSection("Destinatários", subtitle: "Todos os destinatários recebem as comunicações desta cobrança.") {
          ForEach($recipients) { $recipient in
            let index = recipients.firstIndex(where: { $0.id == recipient.id }) ?? 0
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              HStack {
                Text("Destinatário \(index + 1)")
                  .font(.subheadline.weight(.semibold))
                Spacer()
                reorderButtons(
                  position: index,
                  count: recipients.count,
                  label: "destinatário \(index + 1)",
                  identifierPrefix: "billing.form.recipient.\(recipient.id.rawValue)"
                ) { direction in
                  BillingWizardReordering.move(id: recipient.id, direction: direction, in: &recipients)
                }
                Button("Remover", role: .destructive) {
                  recipients.removeAll { $0.id == recipient.id }
                }
                .accessibilityIdentifier("billing.form.recipient.\(index).remove")
              }
              TextField("Nome do destinatário", text: $recipient.name)
                .focused($focusedField, equals: .recipientName(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .recipientName(index))
                .accessibilityIdentifier("billing.form.recipient.\(index).name")
              TextField("E-mail do destinatário", text: $recipient.email)
                .focused($focusedField, equals: .recipientEmail(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .recipientEmail(index))
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
          ForEach($replyTo) { $contact in
            let index = replyTo.firstIndex(where: { $0.id == contact.id }) ?? 0
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              HStack {
                Text("Contato de resposta \(index + 1)")
                  .font(.subheadline.weight(.semibold))
                Spacer()
                reorderButtons(
                  position: index,
                  count: replyTo.count,
                  label: "contato de resposta \(index + 1)",
                  identifierPrefix: "billing.form.reply-to.\(contact.id.rawValue)"
                ) { direction in
                  BillingWizardReordering.move(id: contact.id, direction: direction, in: &replyTo)
                }
                Button("Remover", role: .destructive) {
                  replyTo.removeAll { $0.id == contact.id }
                }
                .accessibilityIdentifier("billing.form.reply-to.\(index).remove")
              }
              TextField("Nome para resposta", text: $contact.name)
                .focused($focusedField, equals: .replyToName(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .replyToName(index))
                .accessibilityIdentifier("billing.form.reply-to.\(index).name")
              TextField("E-mail para resposta", text: $contact.email)
                .focused($focusedField, equals: .replyToEmail(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .replyToEmail(index))
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

  @ViewBuilder
  private func reorderButtons(
    position: Int,
    count: Int,
    label: String,
    identifierPrefix: String,
    onMove: @escaping (BillingWizardReordering.Direction) -> Void
  ) -> some View {
    if count > 1 {
      Button { onMove(.up) } label: {
        Image(systemName: "arrow.up")
      }
      .disabled(position == 0)
      .accessibilityLabel("Mover \(label) para cima")
      .accessibilityIdentifier("\(identifierPrefix).move-up")

      Button { onMove(.down) } label: {
        Image(systemName: "arrow.down")
      }
      .disabled(position == count - 1)
      .accessibilityLabel("Mover \(label) para baixo")
      .accessibilityIdentifier("\(identifierPrefix).move-down")
    }
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

  private var finalActionTitle: String {
    if !organizationsLoaded { return "Carregando responsáveis…" }
    return billing == nil ? "Criar cobrança" : "Salvar cobrança"
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
    guard isValid && pixRecipientRequiredMessage == nil else {
      if isValid { focusPIXRecipientField() }
      return false
    }
    return true
  }

  private func validateCommunication() -> Bool {
    validate(fields: [.recipient, .replyTo])
  }

  private func validate(fields: Set<ValidationField>) -> Bool {
    validationIssues = currentDraft()?.validate().filter { fields.contains($0.field) } ?? [
      ValidationIssue(field: .name, message: "Não foi possível confirmar o responsável.")
    ]
    if !validationIssues.isEmpty { focusFirstInvalidControl() }
    return validationIssues.isEmpty
  }

  private func focusFirstInvalidControl() {
    switch step {
    case .essentials:
      scheduleFocus(validationIssues.contains(where: { $0.field == .name }) ? .name : .description)
    case .items:
      if BillingWizardFocusRules.itemTarget(
        issues: validationIssues,
        items: items.map { .init(type: $0.type, centavos: $0.centavos) }
      ) == .addItem {
        scheduleFocus(.addItem)
      } else if validationIssues.contains(where: { $0.field == .itemDescription }),
        let index = firstInvalidItemDescriptionIndex {
        scheduleFocus(.itemDescription(index))
      } else if validationIssues.contains(where: { $0.field == .itemAmount }),
        let index = firstInvalidItemAmountIndex {
        scheduleFocus(.itemAmount(index))
      }
    case .pix:
      focusPIXField()
    case .communication:
      if validationIssues.contains(where: { $0.field == .recipient }),
        let index = firstInvalidContactIndex(in: recipients) {
        focusContact(recipients[index], at: index, isReplyTo: false)
      } else if validationIssues.contains(where: { $0.field == .replyTo }),
        let index = firstInvalidContactIndex(in: replyTo) {
        focusContact(replyTo[index], at: index, isReplyTo: true)
      }
    case .review:
      break
    }
  }

  private func focusPIXRecipientField() {
    focusPIXField()
  }

  private func focusPIXField() {
    switch BillingWizardFocusRules.pixTarget(
      key: pixKey,
      merchantName: pixMerchantName,
      merchantCity: pixMerchantCity
    ) {
    case .key: scheduleFocus(.pixKey)
    case .merchantName: scheduleFocus(.pixMerchantName)
    case .merchantCity: scheduleFocus(.pixMerchantCity)
    }
  }

  private var firstInvalidItemDescriptionIndex: Int? {
    items.firstIndex {
      let description = $0.description.trimmingCharacters(in: .whitespacesAndNewlines)
      return description.isEmpty || description.unicodeScalars.count > 255
    }
  }

  private func itemAmountFocusBinding(for index: Int) -> Binding<Bool> {
    Binding(
      get: { focusedField == .itemAmount(index) },
      set: { focusedField = $0 ? .itemAmount(index) : nil }
    )
  }

  private func itemAmountAccessibilityFocusBinding(for index: Int) -> Binding<Bool> {
    Binding(
      get: { accessibilityFocusedField == .itemAmount(index) },
      set: { accessibilityFocusedField = $0 ? .itemAmount(index) : nil }
    )
  }

  private var firstInvalidItemAmountIndex: Int? {
    if let negativeAmount = items.firstIndex(where: { $0.centavos < 0 }) { return negativeAmount }
    if let overflow = BillingWizardFocusRules.firstFixedOverflowIndex(
      in: items.map { .init(type: $0.type, centavos: $0.centavos) }
    ) { return overflow }
    return items.firstIndex { $0.type == .variable && $0.centavos != 0 }
  }

  private func firstInvalidContactIndex(in contacts: [EditableRecipient]) -> Int? {
    let nonBlankIndices = contacts.indices.filter { !contacts[$0].isBlank }
    if let invalidContact = nonBlankIndices.first(where: { index in
      let contact = contacts[index]
      let name = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
      return name.isEmpty || name.unicodeScalars.count > 255
        || !EmailAddress.isValid(contact.email.trimmingCharacters(in: .whitespacesAndNewlines))
    }) {
      return invalidContact
    }

    var seenEmails = Set<String>()
    for index in nonBlankIndices {
      let email = contacts[index].email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if !seenEmails.insert(email).inserted { return index }
    }
    return nil
  }

  private func focusContact(_ contact: EditableRecipient, at index: Int, isReplyTo: Bool) {
    switch (isReplyTo, BillingWizardFocusRules.contactTarget(name: contact.name, email: contact.email)) {
    case (false, .name): scheduleFocus(.recipientName(index))
    case (false, .email): scheduleFocus(.recipientEmail(index))
    case (true, .name): scheduleFocus(.replyToName(index))
    case (true, .email): scheduleFocus(.replyToEmail(index))
    }
  }

  private func scheduleFocus(_ field: FocusedField) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
    }
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
