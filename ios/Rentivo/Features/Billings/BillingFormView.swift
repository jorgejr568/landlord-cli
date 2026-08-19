import SwiftUI
import UIKit

private struct EditableBillingItem: Identifiable, Equatable {
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

private struct EditableRecipient: Identifiable, Equatable {
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

enum BillingFormInitialStep {
  case essentials
  case pix
}

struct BillingFormView: View {
  private enum Step: CaseIterable, Hashable {
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
  @State private var pixKeyType: PixKeyType
  @State private var pixKey: String
  @State private var preservesUnclassifiedLegacyPixKey: Bool
  @State private var pixMerchantName: String
  @State private var pixMerchantCity: String
  @State private var usesCustomPix: Bool
  @State private var recipients: [EditableRecipient]
  @State private var replyTo: [EditableRecipient]
  @State private var step: Step = .essentials
  @State private var validationIssues: [ValidationIssue] = []
  @State private var validatedSteps: Set<Step> = []
  @State private var pixRecipientRequiredMessage: String?
  /// Server-side rejection (e.g. a 422) for the last submit. It lives here instead of in the
  /// global notice banner because this form is presented in a sheet, and the banner renders
  /// behind it — the user would never see it.
  @State private var submitFailure: UserFacingFailure?
  @State private var saving = false
  @State private var organizations: [Organization] = []
  @State private var organizationsLoaded: Bool
  @FocusState private var focusedField: FocusedField?
  @AccessibilityFocusState private var accessibilityFocusedField: FocusedField?
  @State private var organizationLoadError: String?
  @State private var pendingPixKeyType: PixKeyType?
  @State private var confirmingPixKeyTypeChange = false
  @State private var isPixKeyRevealed = false

  init(
    billing: Billing? = nil,
    initialStep: BillingFormInitialStep = .essentials,
    onSaved: @escaping () async -> Void
  ) {
    self.billing = billing
    self.onSaved = onSaved
    _name = State(initialValue: billing?.name ?? "")
    _billingDescription = State(initialValue: billing?.description ?? "")
    _ownerID = State(initialValue: billing?.owner.id ?? .personal)
    _items = State(initialValue: billing?.items.map(EditableBillingItem.init) ?? [])
    let pixInput = PixKeyInput(persistedKey: billing?.pixOverride?.key ?? "")
    _pixKeyType = State(initialValue: pixInput.type)
    _pixKey = State(initialValue: pixInput.value)
    _preservesUnclassifiedLegacyPixKey = State(
      initialValue: pixInput.preservesUnclassifiedLegacyValue
    )
    _pixMerchantName = State(initialValue: billing?.pixOverride?.merchantName ?? "")
    _pixMerchantCity = State(initialValue: billing?.pixOverride?.merchantCity ?? "")
    _usesCustomPix = State(initialValue: billing?.pixOverride != nil)
    _recipients = State(initialValue: billing?.recipients.map(EditableRecipient.init) ?? [])
    _replyTo = State(initialValue: billing?.replyTo.map(EditableRecipient.init) ?? [])
    _organizationsLoaded = State(initialValue: billing != nil)
    _step = State(initialValue: initialStep == .pix ? .pix : .essentials)
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
      await loadOrganizations()
    }
    .onChange(of: step) { _, _ in isPixKeyRevealed = false }
    .onChange(of: name) { refreshValidationForCurrentStep() }
    .onChange(of: billingDescription) { refreshValidationForCurrentStep() }
    .onChange(of: ownerID) { refreshValidationForCurrentStep() }
    .onChange(of: items) { refreshValidationForCurrentStep() }
    .onChange(of: pixKeyType) { refreshValidationForCurrentStep() }
    .onChange(of: pixKey) { refreshValidationForCurrentStep() }
    .onChange(of: preservesUnclassifiedLegacyPixKey) { refreshValidationForCurrentStep() }
    .onChange(of: pixMerchantName) { refreshValidationForCurrentStep() }
    .onChange(of: pixMerchantCity) { refreshValidationForCurrentStep() }
    .onChange(of: usesCustomPix) { refreshValidationForCurrentStep() }
    .onChange(of: recipients) { refreshValidationForCurrentStep() }
    .onChange(of: replyTo) { refreshValidationForCurrentStep() }
    .confirmationDialog(
      "Alterar tipo de chave?",
      isPresented: $confirmingPixKeyTypeChange,
      titleVisibility: .visible
    ) {
      Button("Alterar e apagar", role: .destructive) {
        guard let pendingPixKeyType else { return }
        pixKeyType = pendingPixKeyType
        pixKey = ""
        preservesUnclassifiedLegacyPixKey = false
        self.pendingPixKeyType = nil
        scheduleFocus(.pixKey)
      }
      Button("Cancelar", role: .cancel) { pendingPixKeyType = nil }
    } message: {
      Text("A chave digitada será apagada para evitar que seja interpretada no formato errado.")
    }
  }

  @ViewBuilder
  private func stepContent(_ step: Step) -> some View {
    switch step {
    case .essentials:
      RentivoWizardSection("Identificação", subtitle: "Defina a cobrança e seu responsável.") {
        RentivoTextFormField(
          label: "Nome",
          text: $name,
          errorMessage: issueMessage(for: .name),
          accessibilityIdentifier: "billing.form.name"
        )
          .focused($focusedField, equals: .name)
          .accessibilityFocused($accessibilityFocusedField, equals: .name)
        RentivoTextFormField(
          label: "Descrição",
          text: $billingDescription,
          axis: .vertical,
          errorMessage: issueMessage(for: .description),
          accessibilityIdentifier: "billing.form.description"
        )
          .focused($focusedField, equals: .description)
          .accessibilityFocused($accessibilityFocusedField, equals: .description)
          .lineLimit(2...4)
        if billing == nil {
          RentivoFormField(label: "Responsável") {
            Picker("", selection: $ownerID) {
              ForEach(ownerChoices, id: \.id) { owner in
                Text(owner.name).tag(owner.id)
              }
            }
            .labelsHidden()
            .accessibilityLabel("Responsável")
            .accessibilityIdentifier("billing.form.owner")
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
            RentivoTextFormField(
              label: "Descrição do item",
              text: $item.description,
              errorMessage: firstInvalidItemDescriptionIndex == index
                ? issueMessage(for: .itemDescription) : nil,
              accessibilityIdentifier: "billing.form.item.\(index).description"
            )
              .focused($focusedField, equals: .itemDescription(index))
              .accessibilityFocused($accessibilityFocusedField, equals: .itemDescription(index))
            RentivoFormField(label: "Tipo") {
              Picker("", selection: $item.type) {
                ForEach(BillingItemType.allCases, id: \.self) { type in
                  Text(type.label).tag(type)
                }
              }
              .labelsHidden()
              .pickerStyle(.segmented)
              .accessibilityLabel("Tipo")
              .accessibilityIdentifier("billing.form.item.\(index).type")
            }
            .onChange(of: item.type) { _, type in
              item.centavos = type.normalizedTemplateAmount(item.centavos)
            }
            if item.type.showsTemplateAmount {
              RentivoCurrencyField(
                label: "Valor do item",
                amountInCents: $item.centavos,
                errorMessage: firstInvalidItemAmountIndex == index
                  ? issueMessage(for: .itemAmount) : nil,
                isFocused: itemAmountFocusBinding(for: index),
                isAccessibilityFocused: itemAmountAccessibilityFocusBinding(for: index),
                accessibilityIdentifier: "billing.form.item.\(index).amount"
              )
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
      RentivoWizardSection("PIX", subtitle: "Escolha se esta cobrança herda o PIX do responsável.") {
        Toggle("Usar PIX personalizado", isOn: $usesCustomPix)
        if usesCustomPix {
          RentivoFormField(label: "Tipo de chave") {
            Picker("", selection: pixKeyTypeBinding) {
              ForEach(PixKeyType.allCases, id: \.self) { type in Text(type.label).tag(type) }
            }
            .labelsHidden()
            .accessibilityLabel("Tipo de chave")
            .accessibilityIdentifier("billing.form.pix.key-type")
          }
          RentivoTextFormField(
            label: "Chave PIX própria",
            text: pixKeyBinding,
            hint: pixKeyType.hint,
            errorMessage: pixKeyError,
            accessibilityIdentifier: "billing.form.pix.key"
          )
            .focused($focusedField, equals: .pixKey)
            .accessibilityFocused($accessibilityFocusedField, equals: .pixKey)
            .keyboardType(pixKeyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          RentivoTextFormField(
            label: "Nome do recebedor",
            text: $pixMerchantName,
            errorMessage: pixMerchantNameError,
            accessibilityIdentifier: "billing.form.pix.merchantName"
          )
            .focused($focusedField, equals: .pixMerchantName)
            .accessibilityFocused($accessibilityFocusedField, equals: .pixMerchantName)
          RentivoTextFormField(
            label: "Cidade do recebedor",
            text: $pixMerchantCity,
            errorMessage: pixMerchantCityError,
            accessibilityIdentifier: "billing.form.pix.merchantCity"
          )
            .focused($focusedField, equals: .pixMerchantCity)
            .accessibilityFocused($accessibilityFocusedField, equals: .pixMerchantCity)
            .textInputAutocapitalization(.characters)
        } else {
          Label("Herdando o PIX do responsável", systemImage: "arrow.triangle.branch")
            .foregroundStyle(RentivoColors.secondaryInk)
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
              RentivoTextFormField(
                label: "Nome do destinatário",
                text: $recipient.name,
                errorMessage: contactError(in: recipients, index: index, part: .name),
                accessibilityIdentifier: "billing.form.recipient.\(index).name"
              )
                .focused($focusedField, equals: .recipientName(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .recipientName(index))
              RentivoTextFormField(
                label: "E-mail do destinatário",
                text: $recipient.email,
                errorMessage: contactError(in: recipients, index: index, part: .email),
                accessibilityIdentifier: "billing.form.recipient.\(index).email"
              )
                .focused($focusedField, equals: .recipientEmail(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .recipientEmail(index))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
              RentivoTextFormField(
                label: "Nome para resposta",
                text: $contact.name,
                errorMessage: contactError(in: replyTo, index: index, part: .name),
                accessibilityIdentifier: "billing.form.reply-to.\(index).name"
              )
                .focused($focusedField, equals: .replyToName(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .replyToName(index))
              RentivoTextFormField(
                label: "E-mail para resposta",
                text: $contact.email,
                errorMessage: contactError(in: replyTo, index: index, part: .email),
                accessibilityIdentifier: "billing.form.reply-to.\(index).email"
              )
                .focused($focusedField, equals: .replyToEmail(index))
                .accessibilityFocused($accessibilityFocusedField, equals: .replyToEmail(index))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
          value: usesCustomPix ? "Próprio" : "Herdado"
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
      if usesCustomPix {
        RentivoWizardSection("PIX próprio") {
          RentivoPixKeyReview(
            input: currentPixKeyInput,
            isRevealed: $isPixKeyRevealed,
            accessibilityIdentifier: "billing.form.pix.review.reveal"
          )
          RentivoWizardReviewRow(
            label: "Recebedor",
            value: pixMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          RentivoWizardReviewRow(
            label: "Cidade",
            value: pixMerchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
          )
        }
      }
    }
  }

  @ViewBuilder
  private var validationPanel: some View {
    if !aggregateValidationIssues.isEmpty
      || submitFailure != nil || organizationLoadError != nil
    {
      VStack(alignment: .leading, spacing: RentivoSpacing.small) {
        Text("Revise os campos")
          .font(.subheadline.weight(.semibold))
        ForEach(aggregateValidationIssues, id: \.self) { issue in
          validationMessage(issue.message)
        }
        if let submitFailure {
          UserFacingFailureView(failure: submitFailure) { openAuthenticatorSetup() }
            .accessibilityIdentifier("billing.form.submit-error")
        }
        if let organizationLoadError {
          validationMessage(organizationLoadError)
          Button("Tentar carregar responsáveis novamente") {
            Task { await loadOrganizations() }
          }
          .accessibilityIdentifier("billing.form.organizations.retry")
        }
      }
    }
  }

  private func validationMessage(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier("billing.form.validation")
  }

  private func openAuthenticatorSetup() {
    dismiss()
    Task { @MainActor in app.navigateToAuthenticatorSetup() }
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

  private func currentDraft() -> BillingDraft? {
    guard let selectedOwner else { return nil }
    return BillingDraft(
      name: name,
      description: billingDescription,
      owner: selectedOwner,
      items: items.enumerated().map { $0.element.domain(sortOrder: $0.offset) },
      pixOverride: currentPixOverride,
      recipients: nonBlankRecipients.map { $0.domain() },
      replyTo: nonBlankReplyTo.map { $0.domain() }
    )
  }

  private func validateCurrentStep() -> Bool {
    submitFailure = nil
    validatedSteps.insert(step)
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

  private func refreshValidationForCurrentStep() {
    guard validatedSteps.contains(step) else { return }
    let fields: Set<ValidationField>
    switch step {
    case .essentials: fields = [.name, .description]
    case .items: fields = [.items, .itemDescription, .itemAmount]
    case .pix:
      fields = [.pix]
      pixRecipientRequiredMessage = pixRecipientRequiredMessageForCurrentFields
    case .communication: fields = [.recipient, .replyTo]
    case .review: return
    }
    validationIssues = currentDraft()?.validate().filter { fields.contains($0.field) } ?? []
  }

  private var aggregateValidationIssues: [ValidationIssue] {
    validationIssues.filter { issue in
      switch issue.field {
      case .items:
        true
      case .recipient, .replyTo:
        issue.message.localizedCaseInsensitiveContains("repetid")
      default:
        false
      }
    }
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
    if currentPixKeyInput.validationMessage != nil {
      scheduleFocus(.pixKey)
      return
    }
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
    guard case .invalid(let message) = currentPixResult else { return nil }
    return message
  }

  private var currentPixResult: PixFormResult {
    usesCustomPix
      ? PixFormRules.result(
        type: pixKeyType,
        key: pixKey,
        merchantName: pixMerchantName,
        merchantCity: pixMerchantCity,
        preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyPixKey
      )
      : .inherit
  }

  private var currentPixOverride: PixConfiguration? {
    guard case .custom(let configuration) = currentPixResult else { return nil }
    return configuration
  }

  private var pixKeyBinding: Binding<String> {
    Binding(
      get: { pixKey },
      set: {
        pixKey = PixKeyInput.formatted($0, as: pixKeyType)
        preservesUnclassifiedLegacyPixKey = false
      }
    )
  }

  private var pixKeyTypeBinding: Binding<PixKeyType> {
    Binding(
      get: { pixKeyType },
      set: { newType in
        guard newType != pixKeyType else { return }
        if currentPixKeyInput.requiresConfirmation(to: newType) {
          pendingPixKeyType = newType
          confirmingPixKeyTypeChange = true
        } else {
          pixKeyType = newType
          preservesUnclassifiedLegacyPixKey = false
        }
      }
    )
  }

  private var pixKeyboardType: UIKeyboardType {
    switch pixKeyType {
    case .cpf, .cnpj: .numberPad
    case .email: .emailAddress
    case .phone: .phonePad
    case .random: .asciiCapable
    }
  }

  private var pixKeyError: String? {
    guard validationIssues.contains(where: { $0.field == .pix })
      || pixRecipientRequiredMessage != nil else { return nil }
    return currentPixKeyInput.validationMessage
  }

  private var currentPixKeyInput: PixKeyInput {
    PixKeyInput(
      type: pixKeyType,
      value: pixKey,
      preservesUnclassifiedLegacyValue: preservesUnclassifiedLegacyPixKey
    )
  }

  private var pixMerchantNameError: String? {
    guard pixKeyError == nil, validationIssues.contains(where: { $0.field == .pix })
      || pixRecipientRequiredMessage != nil else { return nil }
    let value = pixMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "Informe o nome do recebedor." }
    if value.unicodeScalars.count > 25 {
      return "O nome do recebedor deve ter até 25 caracteres."
    }
    return nil
  }

  private var pixMerchantCityError: String? {
    guard pixKeyError == nil, pixMerchantNameError == nil,
      validationIssues.contains(where: { $0.field == .pix }) || pixRecipientRequiredMessage != nil
    else { return nil }
    let value = pixMerchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return "Informe a cidade do recebedor." }
    if value.unicodeScalars.count > 15 {
      return "A cidade do recebedor deve ter até 15 caracteres."
    }
    return nil
  }

  private func issueMessage(for field: ValidationField) -> String? {
    validationIssues.first(where: { $0.field == field })?.message
  }

  private enum ContactPart: Equatable { case name, email }

  private func contactError(
    in contacts: [EditableRecipient], index: Int, part: ContactPart
  ) -> String? {
    guard contacts.indices.contains(index), firstInvalidContactIndex(in: contacts) == index else {
      return nil
    }
    let contact = contacts[index]
    let normalizedName = contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if part == .name,
      normalizedName.isEmpty || normalizedName.unicodeScalars.count > 255
    {
      return "Informe um nome válido."
    }
    if part == .email,
      !EmailAddress.isValid(contact.email.trimmingCharacters(in: .whitespacesAndNewlines))
    {
      return "Informe um e-mail válido."
    }
    return nil
  }

  private func save() async {
    guard !saving else { return }
    submitFailure = nil
    let owner: BillingOwner
    if let billing {
      owner = billing.owner
    } else if let selected = ownerChoices.first(where: { $0.id == ownerID }) {
      owner = selected
    } else {
      submitFailure = UserFacingFailure(
        message: "Não foi possível confirmar o responsável.", recovery: .none)
      return
    }
    // A wholly empty row is the user leaving the "Adicionar destinatário" placeholder untouched,
    // so it is dropped rather than reported as invalid. Partially filled rows still fail
    // validation below, because the update replaces the billing's whole recipient set.
    let draftRecipients = nonBlankRecipients.map { $0.domain() }
    let draftReplyTo = nonBlankReplyTo.map { $0.domain() }
    let pixResult = currentPixResult
    let pixOverride: PixConfiguration?
    switch pixResult {
    case .inherit:
      pixOverride = nil
      pixRecipientRequiredMessage = nil
    case .custom(let configuration):
      pixOverride = configuration
      pixRecipientRequiredMessage = nil
    case .invalid(let message):
      pixOverride = nil
      pixRecipientRequiredMessage = message
    }
    let draft = BillingDraft(
      name: name,
      description: billingDescription,
      owner: owner,
      items: items.enumerated().map { $0.element.domain(sortOrder: $0.offset) },
      pixOverride: pixOverride,
      recipients: draftRecipients,
      replyTo: draftReplyTo
    )
    validationIssues = draft.validate()
    guard validationIssues.isEmpty && pixRecipientRequiredMessage == nil else {
      routeToFirstInvalidField()
      return
    }
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
      submitFailure = UserFacingError.presentation(for: error, operation: .saveBilling)
    }
  }

  private func routeToFirstInvalidField() {
    if pixRecipientRequiredMessage != nil || validationIssues.contains(where: { $0.field == .pix }) {
      step = .pix
      validatedSteps.insert(.pix)
      focusPIXField()
      return
    }
    guard let issue = validationIssues.first else { return }
    switch issue.field {
    case .name, .description:
      step = .essentials
      validatedSteps.insert(.essentials)
      scheduleFocus(issue.field == .name ? .name : .description)
    case .items, .itemDescription, .itemAmount:
      step = .items
      validatedSteps.insert(.items)
      Task { @MainActor in focusFirstInvalidControl() }
    case .recipient, .replyTo:
      step = .communication
      validatedSteps.insert(.communication)
      Task { @MainActor in focusFirstInvalidControl() }
    case .pix:
      step = .pix
      validatedSteps.insert(.pix)
      focusPIXField()
    case .subject, .body:
      break
    }
  }

  private func loadOrganizations() async {
    organizationsLoaded = false
    organizationLoadError = nil
    do {
      organizations = try await app.dependencies.organizations.listOrganizations()
      organizationsLoaded = true
    } catch {
      organizationLoadError = UserFacingError.message(for: error, operation: .loadOrganizations)
    }
  }
}
