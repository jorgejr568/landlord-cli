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
  /// Server-side rejection (e.g. a 422) for the last submit. It lives here instead of in the
  /// global notice banner because this form is presented in a sheet, and the banner renders
  /// behind it — the user would never see it.
  @State private var submitErrorMessage: String?
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
    Form {
      Section("Identificação") {
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
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }

      Section {
        ForEach($items) { $item in
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            TextField("Descrição do item", text: $item.description)
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
        .onDelete { items.remove(atOffsets: $0) }
        .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        Button {
          items.append(EditableBillingItem())
        } label: {
          Label("Adicionar item", systemImage: "plus.circle.fill")
        }
      } header: {
        HStack {
          Text("Itens recorrentes")
          Spacer()
          EditButton()
        }
      } footer: {
        Text("Use valor zero para itens variáveis que serão preenchidos em cada fatura.")
      }

      Section("PIX") {
        Toggle("Usar PIX personalizado", isOn: $usesCustomPix)
        if usesCustomPix {
          TextField("Chave PIX própria", text: $pixKey)
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("billing.form.pix.key")
          TextField("Nome do recebedor", text: $pixMerchantName)
            .accessibilityIdentifier("billing.form.pix.merchantName")
          TextField("Cidade do recebedor", text: $pixMerchantCity)
            .textInputAutocapitalization(.characters)
            .accessibilityIdentifier("billing.form.pix.merchantCity")
        } else {
          Label("Herdando o PIX do responsável", systemImage: "arrow.triangle.branch")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }

      Section {
        ForEach($recipients) { $recipient in
          VStack(alignment: .leading, spacing: RentivoSpacing.small) {
            TextField("Nome do destinatário", text: $recipient.name)
            TextField("E-mail do destinatário", text: $recipient.email)
              .keyboardType(.emailAddress)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
          .padding(.vertical, RentivoSpacing.tiny)
        }
        .onDelete { recipients.remove(atOffsets: $0) }
        .onMove { recipients.move(fromOffsets: $0, toOffset: $1) }
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
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
          }
          .onDelete { replyTo.remove(atOffsets: $0) }
          Button {
            replyTo.append(EditableRecipient())
          } label: {
            Label("Adicionar endereço de resposta", systemImage: "plus.circle")
          }
        }
      } header: {
        HStack {
          Text("Comunicação")
          Spacer()
          EditButton()
        }
      } footer: {
        Text("Todos os destinatários listados recebem as comunicações desta cobrança.")
      }

      if !validationIssues.isEmpty || pixRecipientRequiredMessage != nil
        || submitErrorMessage != nil || organizationLoadError != nil
      {
        Section("Revise os campos") {
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
          if let submitErrorMessage {
            Label(submitErrorMessage, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("billing.form.validation")
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
    .navigationTitle(billing == nil ? "Nova cobrança" : "Editar cobrança")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") {
          if hasUnsavedChanges { confirmingDiscard = true } else { dismiss() }
        }
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
    var owners: [BillingOwner] = [
      .user(id: app.currentUser.id, name: "Pessoal")
    ]
    if let currentOwner = billing?.owner,
      !owners.contains(where: { $0.id == currentOwner.id })
    {
      owners.append(currentOwner)
    }
    let existingIDs = Set(owners.map(\.id))
    let organizationOwners =
      organizations
      .map { BillingOwner.organization(id: $0.id, name: $0.name) }
      .filter { !existingIDs.contains($0.id) }
    owners.append(contentsOf: organizationOwners)
    return owners
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

  private func save() async {
    guard !saving else { return }
    submitErrorMessage = nil
    guard let owner = ownerChoices.first(where: { $0.id == ownerID }) else {
      submitErrorMessage = "Não foi possível confirmar o responsável."
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
      await onSaved()
      app.showNotice(billing == nil ? "Cobrança criada." : "Cobrança atualizada.")
      dismiss()
    } catch {
      submitErrorMessage = DemoError(error).message
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
