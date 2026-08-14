import RentivoCore
import SwiftUI

struct EditableBillingItem: Identifiable {
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

struct EditableRecipient: Identifiable {
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

/// Who a cobrança can be filed under: the signed-in user, the owner it already has (which may be
/// an organization the user can no longer list), and every other organization they belong to.
enum BillingFormOwnerChoices {
  static func choices(
    currentUserID: Int,
    existingOwner: BillingOwner?,
    organizations: [Organization]
  ) -> [BillingOwner] {
    var owners: [BillingOwner] = [.user(id: currentUserID, name: "Pessoal")]
    if let existingOwner, !owners.contains(where: { $0.id == existingOwner.id }) {
      owners.append(existingOwner)
    }
    let existingIDs = Set(owners.map(\.id))
    owners.append(
      contentsOf: organizations
        .map { BillingOwner.organization(id: $0.id, name: $0.name) }
        .filter { !existingIDs.contains($0.id) }
    )
    return owners
  }
}

/// The optional per-cobrança PIX key. A key on its own cannot produce a payable QR code, so the
/// recipient's name and city become required as soon as one is typed.
enum BillingPixOverride {
  struct Resolution: Equatable {
    let configuration: PixConfiguration?
    let message: String?
  }

  static func resolve(key: String, merchantName: String, merchantCity: String) -> Resolution {
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantCity = merchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return Resolution(configuration: nil, message: nil) }
    guard !merchantName.isEmpty, !merchantCity.isEmpty else {
      return Resolution(
        configuration: nil,
        message: "Informe o nome e a cidade do recebedor para usar uma chave PIX própria."
      )
    }
    return Resolution(
      configuration: PixConfiguration(
        key: key, merchantName: merchantName, merchantCity: merchantCity
      ),
      message: nil
    )
  }
}

struct BillingFormView: View {
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
  @State private var usesCustomPix: Bool
  @State private var recipients: [EditableRecipient]
  @State private var replyTo: [EditableRecipient]
  @State private var validationIssues: [ValidationIssue] = []
  @State private var pixRecipientRequiredMessage: String?
  @State private var submitFailureMessage: String?
  @State private var saving = false
  @State private var organizations: [Organization] = []
  @State private var organizationsLoaded = false
  @State private var organizationLoadError: String?
  @State private var confirmingDiscard = false

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
    _usesCustomPix = State(initialValue: billing?.pixOverride != nil)
    _recipients = State(initialValue: billing?.recipients.map(EditableRecipient.init) ?? [])
    _replyTo = State(initialValue: billing?.replyTo.map(EditableRecipient.init) ?? [])
  }

  var body: some View {
    // Each row's own position, resolved once per body evaluation instead of by a `firstIndex` scan
    // per row (three of them, in fact: the index and both move buttons). Every keystroke in any
    // field re-evaluates this body, so the scans made editing a long list quadratic. The maps and
    // the rows come from the same body evaluation, so the positions the buttons act on are the
    // ones the user is looking at.
    let itemPositions = positions(in: items)
    let recipientPositions = positions(in: recipients)
    Form {
      RentivoSection("Identificação") {
        TextField("Nome", text: $name)
          .accessibilityIdentifier("billing.form.name")
        TextField("Descrição", text: $billingDescription, axis: .vertical)
          .lineLimit(2...4)
        Picker("Responsável", selection: $ownerID) {
          ForEach(ownerChoices, id: \.id) { owner in
            Text(owner.name).tag(owner.id)
          }
        }
        .disabled(!organizationsLoaded || billing?.owner.isOrganization == true)
        if billing?.owner.isOrganization == true {
          Text("O responsável organizacional não pode ser alterado nesta edição.")
            .font(RentivoTypography.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        if !organizationsLoaded {
          // Salvar is disabled until the organizations arrive, because until then the list of
          // responsáveis is incomplete and the cobrança could be filed under the wrong one. That
          // wait is a second or two of a dead button otherwise, so it says what it is waiting for.
          HStack(spacing: RentivoSpacing.small) {
            ProgressView()
              .controlSize(.small)
            Text("Carregando os responsáveis disponíveis…")
              .font(RentivoTypography.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          .accessibilityIdentifier("billing.form.owners.loading")
        }
      }

      Section {
        ForEach($items) { $item in
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            HStack(spacing: RentivoSpacing.small) {
              TextField("Descrição do item", text: $item.description)
              // macOS has neither swipe-to-delete nor `EditButton`, so reordering and removal are
              // ordinary buttons on the row itself.
              RowOrderControls(
                index: itemPositions[item.id] ?? 0,
                count: items.count,
                moveUp: { move(&items, from: itemPositions[item.id] ?? 0, by: -1) },
                moveDown: { move(&items, from: itemPositions[item.id] ?? 0, by: 1) },
                remove: { items.removeAll { $0.id == item.id } },
                removeLabel: "Remover item"
              )
            }
            Picker("Tipo", selection: $item.type) {
              ForEach(BillingItemType.allCases, id: \.self) { type in
                Text(type.label).tag(type)
              }
            }
            .pickerStyle(.segmented)
            .onChange(of: item.type) { _, type in
              item.centavos = type.normalizedTemplateAmount(item.centavos)
            }
            if item.type.showsTemplateAmount {
              CurrencyCentavosField("Valor do item", centavos: $item.centavos)
            }
          }
          .padding(.vertical, RentivoSpacing.tiny)
        }
        Button {
          items.append(EditableBillingItem())
        } label: {
          Label("Adicionar item", systemImage: "plus.circle.fill")
        }
      } header: {
        Text("Itens recorrentes")
      } footer: {
        Text("Use valor zero para itens variáveis que serão preenchidos em cada fatura.")
      }

      RentivoSection("PIX") {
        Toggle("Usar PIX personalizado", isOn: $usesCustomPix)
        if usesCustomPix {
          TextField("Chave PIX própria", text: $pixKey)
            .autocorrectionDisabled()
            .accessibilityIdentifier("billing.form.pix.key")
          TextField("Nome do recebedor", text: $pixMerchantName)
            .accessibilityIdentifier("billing.form.pix.merchantName")
          TextField("Cidade do recebedor", text: $pixMerchantCity)
            .accessibilityIdentifier("billing.form.pix.merchantCity")
        } else {
          Label("Herdando o PIX do responsável", systemImage: "arrow.triangle.branch")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }

      Section {
        ForEach($recipients) { $recipient in
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            HStack(spacing: RentivoSpacing.small) {
              TextField("Nome do destinatário", text: $recipient.name)
              RowOrderControls(
                index: recipientPositions[recipient.id] ?? 0,
                count: recipients.count,
                moveUp: { move(&recipients, from: recipientPositions[recipient.id] ?? 0, by: -1) },
                moveDown: { move(&recipients, from: recipientPositions[recipient.id] ?? 0, by: 1) },
                remove: { recipients.removeAll { $0.id == recipient.id } },
                removeLabel: "Remover destinatário"
              )
            }
            TextField("E-mail do destinatário", text: $recipient.email)
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
        DisclosureGroup("Responder para (opcional)") {
          ForEach($replyTo) { $contact in
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              TextField("Nome", text: $contact.name)
              TextField("E-mail", text: $contact.email)
                .autocorrectionDisabled()
            }
          }
          Button {
            replyTo.append(EditableRecipient())
          } label: {
            Label("Adicionar endereço de resposta", systemImage: "plus.circle")
          }
        }
      } header: {
        Text("Comunicação")
      } footer: {
        Text("Todos os destinatários listados recebem as comunicações desta cobrança.")
      }

      if !validationIssues.isEmpty || pixRecipientRequiredMessage != nil
        || submitFailureMessage != nil || organizationLoadError != nil
      {
        RentivoSection("Revise os campos") {
          ForEach(validationIssues, id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("billing.form.validation")
          }
          if let pixRecipientRequiredMessage {
            Label(pixRecipientRequiredMessage, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("billing.form.validation")
          }
          if let submitFailureMessage {
            // The global banner is overlaid on the window, which this sheet covers, so a failed
            // save reported there would be invisible until the sheet closes — and the sheet stays
            // open precisely because the save failed. It is reported here instead.
            Label(submitFailureMessage, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("billing.form.submitFailure")
          }
          if let organizationLoadError {
            Label(organizationLoadError, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(RentivoColors.coral)
            Button("Tentar carregar responsáveis novamente") {
              Task { await loadOrganizations() }
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(billing == nil ? "Nova cobrança" : "Editar cobrança")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        // Dismissing mid-save would leave the request running with no screen to report it, so
        // Cancelar goes down with the sheet's other exits while `saving`.
        Button("Cancelar") {
          if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
        }
          .disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(saving || !organizationsLoaded)
          .accessibilityIdentifier("billing.form.save")
      }
    }
    .interactiveDismissDisabled(saving || hasUnsavedChanges)
    .confirmationDialog(
      "Descartar as alterações?", isPresented: $confirmingDiscard, titleVisibility: .visible
    ) {
      Button("Descartar", role: .destructive) { dismiss() }
      Button("Continuar editando", role: .cancel) {}
    }
    .task { await loadOrganizations() }
  }

  private var ownerChoices: [BillingOwner] {
    BillingFormOwnerChoices.choices(
      currentUserID: app.currentUser.id,
      existingOwner: billing?.owner,
      organizations: organizations
    )
  }

  private var hasUnsavedChanges: Bool {
    let currentItems = items.enumerated().map { $0.element.domain(sortOrder: $0.offset) }
    let currentRecipients = recipients.filter { !$0.isBlank }.map { $0.domain() }
    let currentReplyTo = replyTo.filter { !$0.isBlank }.map { $0.domain() }
    guard let billing else {
      return !name.isEmpty || !billingDescription.isEmpty || !currentItems.isEmpty
        || usesCustomPix || !currentRecipients.isEmpty || !currentReplyTo.isEmpty
    }
    return name != billing.name || billingDescription != billing.description
      || ownerID != billing.owner.id || currentItems != billing.items
      || usesCustomPix != (billing.pixOverride != nil)
      || pixKey != (billing.pixOverride?.key ?? "")
      || pixMerchantName != (billing.pixOverride?.merchantName ?? "")
      || pixMerchantCity != (billing.pixOverride?.merchantCity ?? "")
      || currentRecipients != billing.recipients || currentReplyTo != billing.replyTo
  }

  /// Every element's position, keyed by its id.
  ///
  /// Duplicate ids cannot happen — items and destinatários are identified by a server id or a
  /// fresh `UUID` — but the first position wins rather than trapping, because a `ForEach` over
  /// duplicated ids is already the broken thing here and a crash would not explain it.
  private func positions<Element: Identifiable>(in collection: [Element]) -> [Element.ID: Int] {
    Dictionary(
      collection.enumerated().map { ($0.element.id, $0.offset) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  private func move<Element>(_ collection: inout [Element], from index: Int, by offset: Int) {
    let destination = index + offset
    guard collection.indices.contains(index), collection.indices.contains(destination) else {
      return
    }
    collection.swapAt(index, destination)
  }

  private func save() async {
    // Salvar is disabled while `saving`, but a second click can land before the first `Task`
    // suspends and the flag is set, which used to create the cobrança twice.
    guard !saving else { return }
    // Every issue from the previous attempt is re-derived below, so the section never mixes a
    // fresh validation run with a stale server error.
    submitFailureMessage = nil
    guard let owner = ownerChoices.first(where: { $0.id == ownerID }) else {
      submitFailureMessage = "Não foi possível confirmar o responsável."
      return
    }
    // A wholly empty row is the user leaving the "Adicionar destinatário" placeholder untouched,
    // so it is dropped rather than reported as invalid. Partially filled rows still fail
    // validation below, because the update replaces the billing's whole recipient set.
    let draftRecipients = recipients.filter { !$0.isBlank }.map { $0.domain() }
    let pixResult = usesCustomPix
      ? PixFormRules.result(
        key: pixKey, merchantName: pixMerchantName, merchantCity: pixMerchantCity)
      : .inherit
    let pix: PixConfiguration?
    switch pixResult {
    case .inherit:
      pix = nil
      pixRecipientRequiredMessage = nil
    case .custom(let configuration):
      pix = configuration
      pixRecipientRequiredMessage = nil
    case .invalid(let message):
      pix = nil
      pixRecipientRequiredMessage = message
    }
    let draft = BillingDraft(
      name: name,
      description: billingDescription,
      owner: owner,
      items: items.enumerated().map { $0.element.domain(sortOrder: $0.offset) },
      pixOverride: pix,
      recipients: draftRecipients,
      replyTo: replyTo.filter { !$0.isBlank }.map { $0.domain() }
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
      app.showNotice(billing == nil ? "Cobrança criada." : "Cobrança atualizada.")
      await onSaved()
      dismiss()
    } catch {
      submitFailureMessage = DemoError(error).message
    }
  }

  private func loadOrganizations() async {
    organizationsLoaded = false
    organizationLoadError = nil
    do {
      organizations = try await app.dependencies.organizations.listOrganizations()
      organizationsLoaded = true
    } catch {
      organizationLoadError = DemoError(error).message
    }
  }
}

/// Reorder-and-remove controls for one row of an editable list. iOS gets these from `EditButton`
/// plus swipe actions, neither of which exists on macOS.
private struct RowOrderControls: View {
  let index: Int
  let count: Int
  let moveUp: () -> Void
  let moveDown: () -> Void
  let remove: () -> Void
  let removeLabel: String

  var body: some View {
    HStack(spacing: RentivoSpacing.tiny) {
      Button(action: moveUp) {
        Image(systemName: "chevron.up")
      }
      .disabled(index == 0)
      .accessibilityLabel("Mover para cima")
      Button(action: moveDown) {
        Image(systemName: "chevron.down")
      }
      .disabled(index >= count - 1)
      .accessibilityLabel("Mover para baixo")
      Button(role: .destructive, action: remove) {
        Image(systemName: "trash")
      }
      .accessibilityLabel(removeLabel)
    }
    .buttonStyle(.borderless)
    .foregroundStyle(RentivoColors.secondaryInk)
  }
}
