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
  @State private var recipients: [EditableRecipient]
  @State private var replyTo: String
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
    _replyTo = State(initialValue: billing?.replyTo ?? "")
    _organizationsLoaded = State(initialValue: billing != nil)
  }

  var body: some View {
    Form {
      Section("Identificação") {
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

      Section("PIX opcional") {
        TextField("Chave PIX própria", text: $pixKey)
          .textInputAutocapitalization(.never)
          .accessibilityIdentifier("billing.form.pix.key")
        TextField("Nome do recebedor", text: $pixMerchantName)
          .accessibilityIdentifier("billing.form.pix.merchantName")
        TextField("Cidade do recebedor", text: $pixMerchantCity)
          .textInputAutocapitalization(.characters)
          .accessibilityIdentifier("billing.form.pix.merchantCity")
        Text("Deixe em branco para herdar o PIX do responsável.")
          .font(.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
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
        TextField("Responder para", text: $replyTo)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
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
        || submitErrorMessage != nil
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
        }
      }
    }
    .navigationTitle(billing == nil ? "Nova cobrança" : "Editar cobrança")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(saving || !organizationsLoaded)
          .accessibilityIdentifier("billing.form.save")
      }
    }
    .interactiveDismissDisabled(saving)
    .task {
      guard billing == nil else { return }
      organizations = (try? await app.dependencies.organizations.listOrganizations()) ?? []
      organizationsLoaded = true
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
    let draftRecipients = recipients.filter { !$0.isBlank }.map { $0.domain() }
    let pix = pixKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantName = pixMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
    let merchantCity = pixMerchantCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if pix.isEmpty {
      pixRecipientRequiredMessage = nil
    } else if merchantName.isEmpty || merchantCity.isEmpty {
      pixRecipientRequiredMessage =
        "Informe o nome e a cidade do recebedor para usar uma chave PIX própria."
    } else {
      pixRecipientRequiredMessage = nil
    }
    let draft = BillingDraft(
      name: name,
      description: billingDescription,
      owner: owner,
      items: items.enumerated().map { $0.element.domain(sortOrder: $0.offset) },
      pixOverride: pix.isEmpty
        ? nil
        : PixConfiguration(key: pix, merchantName: merchantName, merchantCity: merchantCity),
      recipients: draftRecipients,
      replyTo: replyTo.isEmpty ? nil : replyTo
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
