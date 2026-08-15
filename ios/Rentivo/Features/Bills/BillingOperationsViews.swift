import SwiftUI
import UniformTypeIdentifiers

struct BillingOperationsLinks: View {
  let billingID: BillingID
  let capabilities: BillingCapabilities
  let onMutation: () async -> Void
  @State private var showingExport = false

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Operações", symbol: "square.grid.2x2.fill")
      RentivoCard {
        VStack(spacing: RentivoSpacing.small) {
          if capabilities.canReadExpenses {
            NavigationLink {
              ExpenseListView(
                billingID: billingID,
                canWrite: capabilities.canWriteExpenses,
                onMutation: onMutation
              )
            } label: {
              OperationRow(title: "Despesas", symbol: "wrench.and.screwdriver.fill")
            }
          }
          if capabilities.canReadAttachments {
            Divider()
            NavigationLink {
              AttachmentListView(
                billingID: billingID,
                canWrite: capabilities.canWriteAttachments
              )
            } label: {
              OperationRow(title: "Arquivos", symbol: "folder.fill")
            }
          }
          if capabilities.canCreateExports {
            Divider()
            Button {
              showingExport = true
            } label: {
              OperationRow(title: "Exportar dados", symbol: "square.and.arrow.up.fill")
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .fullScreenCover(isPresented: $showingExport) {
      ExportSimulationView(billingID: billingID)
    }
  }
}

private struct OperationRow: View {
  let title: String
  let symbol: String

  var body: some View {
    HStack {
      Label(title, systemImage: symbol)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(RentivoColors.ink)
      Spacer()
      Image(systemName: "chevron.right")
        .foregroundStyle(RentivoColors.secondaryInk)
    }
    .contentShape(Rectangle())
    .padding(.vertical, RentivoSpacing.small)
  }
}

struct ExpenseListView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  let canWrite: Bool
  let onMutation: () async -> Void
  @State private var state: LoadState<[Expense]> = .idle
  @State private var showingAdd = false
  @State private var pendingDeletion: Expense?

  var body: some View {
    PageStateView(state: state) { expenses in
      List {
        Section {
          ForEach(expenses) { expense in
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              HStack {
                Text(expense.description).font(.headline)
                Spacer()
                MoneyText(money: expense.amount)
              }
              Label(expense.category.label, systemImage: "tag.fill")
                .font(.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            }
            .swipeActions {
              if canWrite {
                Button("Excluir", role: .destructive) { pendingDeletion = expense }
              }
            }
          }
        } header: {
          Text(ptBRCount(expenses.count, singular: "despesa", plural: "despesas"))
        }
      }
      .scrollContentBackground(.hidden)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Despesas")
    .toolbar {
      if canWrite {
        Button {
          showingAdd = true
        } label: {
          Label("Adicionar", systemImage: "plus")
        }
      }
    }
    .fullScreenCover(isPresented: $showingAdd) {
      ExpenseFormView(billingID: billingID) {
        await load()
        await onMutation()
      }
    }
    .confirmationDialog(
      "Excluir esta despesa?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { isPresented in if !isPresented { pendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Excluir despesa", role: .destructive) {
        if let expense = pendingDeletion { Task { await remove(expense) } }
      }
      Button("Cancelar", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("A despesa será removida permanentemente do registro desta cobrança.")
    }
    .task(id: app.dataRevision) { await load() }
  }

  private func load() async {
    state = .loading
    do {
      let expenses = try await app.dependencies.expenses.listExpenses(billingID: billingID)
      state = expenses.isEmpty ? .empty : .loaded(expenses)
    } catch { state = .failed(DemoError(error)) }
  }

  private func remove(_ expense: Expense) async {
    do {
      try await app.dependencies.expenses.deleteExpense(billingID: billingID, expenseID: expense.id)
      await load()
      await onMutation()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}

enum ExpenseWizardStep: Hashable {
  case details
  case valueAndDate
  case review
}

enum ExpenseFormFocus: Hashable {
  case description
  case amount
}

func expenseFormFocusTarget(
  step: ExpenseWizardStep, descriptionIsValid: Bool, centavos: Int
) -> ExpenseFormFocus? {
  switch step {
  case .details: return descriptionIsValid ? nil : .description
  case .valueAndDate: return centavos > 0 ? nil : .amount
  case .review: return nil
  }
}

private struct ExpenseFormView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  let onSaved: () async -> Void
  @State private var description = ""
  @State private var centavos = 0
  @State private var category: ExpenseCategory = .maintenance
  @State private var incurredOn = Date()
  @State private var selectedStep: ExpenseWizardStep = .details
  /// Server-side rejection (e.g. a 422) for the last submit. This form is presented in a sheet
  /// and the global notice banner renders behind it, so the message has to stay inline.
  @State private var submitErrorMessage: String?
  @State private var saving = false
  @FocusState private var focusedField: ExpenseFormFocus?
  @AccessibilityFocusState private var accessibilityFocusedField: ExpenseFormFocus?

  var body: some View {
    RentivoFormWizard(
      title: "Nova despesa",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isDirty: isDirty,
      isBusy: saving,
      primaryTitle: "Salvar",
      onValidateAndAdvance: validateAndAdvance,
      onCommit: { Task { await save() } }
    ) { step in
      switch step {
      case .details:
        RentivoWizardSection("Detalhes") {
          TextField("Descrição", text: $description)
            .focused($focusedField, equals: .description)
            .accessibilityFocused($accessibilityFocusedField, equals: .description)
          Picker("Categoria", selection: $category) {
            ForEach(ExpenseCategory.allCases, id: \.self) { category in
              Text(category.label).tag(category)
            }
          }
          .pickerStyle(.menu)
          validationError
        }
      case .valueAndDate:
        RentivoWizardSection("Valor e data") {
          CurrencyCentavosField(
            "Valor em centavos",
            centavos: $centavos,
            isFocused: amountFocusBinding,
            isAccessibilityFocused: accessibilityAmountFocusBinding
          )
          DatePicker("Data", selection: $incurredOn, displayedComponents: .date)
          validationError
        }
      case .review:
        RentivoWizardSection("Resumo") {
          RentivoWizardReviewRow(label: "Descrição", value: ExpenseInput.normalizedDescription(description))
          RentivoWizardReviewRow(label: "Categoria", value: category.label)
          RentivoWizardReviewRow(label: "Valor", value: Money(centavos: centavos).formatted())
          RentivoWizardReviewRow(label: "Data", value: selectedDate.displayFormatted)
          validationError
        }
      }
    }
  }

  private var descriptors: [RentivoWizardStepDescriptor<ExpenseWizardStep>] {
    [
      RentivoWizardStepDescriptor(id: .details, title: "Detalhes"),
      RentivoWizardStepDescriptor(id: .valueAndDate, title: "Valor e data"),
      RentivoWizardStepDescriptor(id: .review, title: "Revisar despesa"),
    ]
  }

  @ViewBuilder
  private var validationError: some View {
    if let submitErrorMessage {
      Label(submitErrorMessage, systemImage: "exclamationmark.circle.fill")
        .foregroundStyle(RentivoColors.coral)
        .accessibilityIdentifier("expense.form.error")
    }
  }

  private var isDirty: Bool {
    !description.isEmpty || centavos != 0 || category != .maintenance || selectedDate != DateOnly(from: Date())
  }

  private func validateAndAdvance() -> Bool {
    submitErrorMessage = nil
    switch selectedStep {
    case .details:
      if expenseFormFocusTarget(
        step: .details,
        descriptionIsValid: ExpenseInput.isValidDescription(description),
        centavos: centavos
      ) == .description {
        submitErrorMessage = "Informe uma descrição válida para a despesa."
        scheduleFocus(.description)
        return false
      }
    case .valueAndDate:
      if expenseFormFocusTarget(
        step: .valueAndDate,
        descriptionIsValid: true,
        centavos: centavos
      ) == .amount {
        submitErrorMessage = "Informe um valor maior que zero."
        scheduleFocus(.amount)
        return false
      }
    case .review:
      break
    }
    return true
  }

  private func scheduleFocus(_ field: ExpenseFormFocus) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
    }
  }

  private var amountFocusBinding: Binding<Bool> {
    Binding(
      get: { focusedField == .amount },
      set: { isFocused in
        if isFocused {
          focusedField = .amount
        } else if focusedField == .amount {
          focusedField = nil
        }
      }
    )
  }

  private var accessibilityAmountFocusBinding: Binding<Bool> {
    Binding(
      get: { accessibilityFocusedField == .amount },
      set: { isFocused in
        if isFocused {
          accessibilityFocusedField = .amount
        } else if accessibilityFocusedField == .amount {
          accessibilityFocusedField = nil
        }
      }
    )
  }

  private func save() async {
    guard !saving else { return }
    submitErrorMessage = nil
    guard ExpenseInput.isValidDescription(description) else {
      submitErrorMessage = "Informe uma descrição válida para a despesa."
      selectedStep = .details
      return
    }
    guard centavos > 0 else {
      submitErrorMessage = "Informe um valor maior que zero."
      selectedStep = .valueAndDate
      return
    }
    saving = true
    defer { saving = false }
    do {
      _ = try await app.dependencies.expenses.createExpense(
        billingID: billingID,
        description: ExpenseInput.normalizedDescription(description),
        category: category,
        incurredOn: selectedDate,
        amount: Money(centavos: centavos)
      )
      await onSaved()
      dismiss()
    } catch { submitErrorMessage = DemoError(error).message }
  }

  private var selectedDate: DateOnly { DateOnly(from: incurredOn) }
}

struct AttachmentListView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  let canWrite: Bool
  @State private var state: LoadState<[Attachment]> = .idle
  @State private var downloadedFile: DownloadedFile?
  @State private var showingFileImporter = false
  @State private var pendingDeletion: Attachment?

  var body: some View {
    PageStateView(state: state) { attachments in
      List {
        Section {
          ForEach(attachments) { attachment in
            HStack {
              Label {
                VStack(alignment: .leading) {
                  Text(attachment.name).font(.headline)
                  Text(
                    ByteCountFormatter.string(
                      fromByteCount: Int64(attachment.byteCount), countStyle: .file)
                  )
                  .font(.caption)
                }
              } icon: {
                Image(systemName: "doc.fill")
              }
              Spacer()
              // A single-action menu behind an unlabeled "..." icon added an extra tap for no
              // reason; this was the only action, so it is now a direct, accessibly-labeled button.
              Button {
                Task { await download(attachment) }
              } label: {
                Label("Abrir", systemImage: "arrow.down.circle")
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
            }
            .swipeActions {
              if canWrite {
                Button("Excluir", role: .destructive) { pendingDeletion = attachment }
              }
            }
          }
        } header: {
          Text(ptBRCount(attachments.count, singular: "arquivo", plural: "arquivos"))
        }
      }
      .scrollContentBackground(.hidden)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Arquivos")
    .toolbar {
      if canWrite {
        Button {
          showingFileImporter = true
        } label: {
          Label("Adicionar", systemImage: "plus")
        }
      }
    }
    .downloadedFileSheet($downloadedFile)
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: [UTType.pdf, UTType.image],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await add(fileURL: url) }
    }
    .confirmationDialog(
      "Excluir este arquivo?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { isPresented in if !isPresented { pendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Excluir arquivo", role: .destructive) {
        if let attachment = pendingDeletion { Task { await remove(attachment) } }
      }
      Button("Cancelar", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("O arquivo será removido permanentemente e não poderá ser recuperado.")
    }
    .task(id: app.dataRevision) { await load() }
  }

  private func load() async {
    state = .loading
    do {
      let values = try await app.dependencies.attachments.listAttachments(billingID: billingID)
      state = values.isEmpty ? .empty : .loaded(values)
    } catch { state = .failed(DemoError(error)) }
  }

  private func add(fileURL: URL) async {
    do {
      let accessGranted = fileURL.startAccessingSecurityScopedResource()
      defer { if accessGranted { fileURL.stopAccessingSecurityScopedResource() } }
      let upload = try FileUpload.from(url: fileURL)
      _ = try await app.dependencies.attachments.addAttachment(
        billingID: billingID,
        upload: upload
      )
      await load()
      app.showNotice("Arquivo enviado.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func remove(_ attachment: Attachment) async {
    do {
      try await app.dependencies.attachments.deleteAttachment(
        billingID: billingID, attachmentID: attachment.id)
      await load()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func download(_ attachment: Attachment) async {
    do {
      downloadedFile = try await app.dependencies.downloads.downloadAttachment(
        billingID: billingID, attachmentID: attachment.id
      )
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}

struct DownloadShareView: View {
  @Environment(\.dismiss) private var dismiss
  let file: DownloadedFile

  var body: some View {
    NavigationStack {
      VStack(spacing: RentivoSpacing.large) {
        Image(systemName: "doc.text.fill")
          .font(.system(size: 64))
          .foregroundStyle(RentivoColors.blue)
        Text(file.filename).font(RentivoTypography.title)
        Text("Arquivo baixado do Rentivo.").foregroundStyle(RentivoColors.secondaryInk)
        ShareLink(item: file.fileURL) {
          Label("Compartilhar ou salvar arquivo", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
          .font(.footnote)
        Spacer()
      }
      .padding(RentivoSpacing.page)
      .navigationTitle("Prévia")
      .toolbar { Button("Concluir") { dismiss() } }
    }
  }
}

private enum CommunicationWizardStep: Hashable {
  case channel
  case recipients
  case message
  case template
  case review
}

private enum CommunicationComposerFocus: Hashable {
  case recipient(RecipientID)
  case subject
  case message
}

struct CommunicationComposerView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billing: Billing
  let bill: Bill

  @State private var commType: CommunicationType = .billReady
  @State private var selectedRecipients: Set<RecipientID>
  @State private var subject: String
  @State private var message: String
  @State private var saveScope: CommunicationSaveScope?
  @State private var selectedStep: CommunicationWizardStep = .channel
  @State private var isSending = false
  /// Why the last send attempt failed, be it the local recipient check or a server rejection.
  /// The composer is presented in a sheet and the global notice banner renders behind it, so the
  /// message has to stay inline.
  @State private var sendErrorMessage: String?
  @State private var appliedTemplateType: CommunicationType
  @FocusState private var focusedField: CommunicationComposerFocus?
  @AccessibilityFocusState private var accessibilityFocusedField: CommunicationComposerFocus?
  private let initialCommType: CommunicationType

  init(billing: Billing, bill: Bill) {
    self.billing = billing
    self.bill = bill
    let initialType: CommunicationType = bill.capabilities.canSendInvoice ? .billReady : .paymentReceipt
    _commType = State(initialValue: initialType)
    _selectedRecipients = State(initialValue: Set(billing.recipients.map(\.id)))
    let template = billing.template(for: initialType)
    _subject = State(initialValue: template?.subject ?? "")
    _message = State(initialValue: template?.body ?? "")
    _appliedTemplateType = State(initialValue: initialType)
    initialCommType = initialType
  }

  private var availableTypes: [CommunicationType] {
    CommunicationType.allCases.filter { type in
      switch type {
      case .billReady: bill.capabilities.canSendInvoice
      case .paymentReceipt: bill.status == .paid && bill.capabilities.canSendRecibo
      }
    }
  }

  private var attachmentDescription: String {
    commType == .paymentReceipt ? "recibo" : "PDF da fatura"
  }

  var body: some View {
    RentivoFormWizard(
      title: "Enviar \(commType.label.lowercased())",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isDirty: isDirty,
      isBusy: isSending,
      isPrimaryEnabled: selectedStep != .review || !bill.isRenderingPDF,
      primaryTitle: isSending ? "Enviando..." : "Enviar \(commType.label.lowercased())",
      onValidateAndAdvance: validateAndAdvance,
      onCommit: { Task { await send() } }
    ) { step in
      switch step {
      case .channel:
        channelStep
      case .recipients:
        recipientsStep
      case .message:
        messageStep
      case .template:
        templateStep
      case .review:
        reviewStep
      }
    }
    .onChange(of: commType) { _, _ in applyTemplateIfNeeded() }
  }

  private var descriptors: [RentivoWizardStepDescriptor<CommunicationWizardStep>] {
    [
      RentivoWizardStepDescriptor(id: .channel, title: "Canal"),
      RentivoWizardStepDescriptor(id: .recipients, title: "Destinatários"),
      RentivoWizardStepDescriptor(id: .message, title: "Mensagem"),
      RentivoWizardStepDescriptor(id: .template, title: "Modelo"),
      RentivoWizardStepDescriptor(id: .review, title: "Revisar envio"),
    ]
  }

  private var channelStep: some View {
    RentivoWizardSection("Canal") {
      if availableTypes.count > 1 {
        Picker("Tipo", selection: $commType) {
          ForEach(availableTypes, id: \.self) { type in
            Text(type.label).tag(type)
          }
        }
        .pickerStyle(.segmented)
      } else if let type = availableTypes.first {
        RentivoWizardReviewRow(label: "Tipo", value: type.label)
      } else {
        Label("Esta fatura ainda não está pronta para envio.", systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(RentivoColors.coral)
      }
      inlineError
    }
  }

  private var recipientsStep: some View {
    RentivoWizardSection(
      "Destinatários",
      subtitle: "Cada destinatário recebe um e-mail separado com o \(attachmentDescription) anexado."
    ) {
      if billing.recipients.isEmpty {
        Text("Nenhum destinatário cadastrado. Adicione destinatários na cobrança antes de enviar.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(billing.recipients) { recipient in
          Toggle(isOn: binding(for: recipient.id)) {
            VStack(alignment: .leading) {
              Text(recipient.name).font(.subheadline.weight(.semibold))
              Text(recipient.email)
                .font(.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            }
          }
          .focused($focusedField, equals: .recipient(recipient.id))
          .accessibilityFocused($accessibilityFocusedField, equals: .recipient(recipient.id))
        }
      }
      inlineError
    }
  }

  private var messageStep: some View {
    RentivoWizardSection(
      "Mensagem",
      subtitle: "Variáveis: {{nome_inquilino}}, {{unidade}}, {{mes}}, {{vencimento}}, {{total}}."
    ) {
      TextField("Assunto", text: $subject)
        .focused($focusedField, equals: .subject)
        .accessibilityFocused($accessibilityFocusedField, equals: .subject)
      TextField("Corpo (Markdown — HTML não é permitido)", text: $message, axis: .vertical)
        .lineLimit(5...12)
        .focused($focusedField, equals: .message)
        .accessibilityFocused($accessibilityFocusedField, equals: .message)
      inlineError
    }
  }

  private var templateStep: some View {
    RentivoWizardSection(
      "Modelo",
      subtitle: "O modelo salvo preenche automaticamente as próximas comunicações."
    ) {
      Picker("Salvar modelo", selection: $saveScope) {
        Text("Não salvar como modelo").tag(CommunicationSaveScope?.none)
        Text("Salvar para esta cobrança").tag(CommunicationSaveScope?.some(.billing))
        if billing.capabilities.canEdit {
          Text(ownerScopeLabel).tag(CommunicationSaveScope?.some(.owner))
        }
      }
      .pickerStyle(.menu)
      inlineError
    }
  }

  private var reviewStep: some View {
    RentivoWizardSection("Prévia") {
      RentivoWizardReviewRow(label: "Canal", value: commType.label)
      RentivoWizardReviewRow(label: "Destinatários", value: "\(selectedRecipients.count)")
      RentivoWizardReviewRow(label: "Assunto", value: CommunicationContent.normalizedSubject(subject))
      RentivoWizardReviewRow(label: "Anexo", value: attachmentDescription)
      if bill.isRenderingPDF {
        Label("Aguarde a geração do PDF antes de enviar.", systemImage: "clock.fill")
          .foregroundStyle(RentivoColors.secondaryInk)
      }
      inlineError
    }
  }

  @ViewBuilder
  private var inlineError: some View {
    if let sendErrorMessage {
      Label(sendErrorMessage, systemImage: "exclamationmark.circle.fill")
        .foregroundStyle(RentivoColors.coral)
        .accessibilityIdentifier("comm.error")
    }
  }

  private var isDirty: Bool {
    commType != initialCommType
      || selectedRecipients != Set(billing.recipients.map(\.id))
      || subject != (billing.template(for: commType)?.subject ?? "")
      || message != (billing.template(for: commType)?.body ?? "")
      || saveScope != nil
  }

  private func validateAndAdvance() -> Bool {
    sendErrorMessage = nil
    switch selectedStep {
    case .channel:
      guard availableTypes.contains(commType) else {
        sendErrorMessage = "Esta comunicação não está disponível para a fatura atual."
        return false
      }
    case .recipients:
      guard !selectedRecipients.isEmpty else {
        sendErrorMessage = "Selecione ao menos um destinatário."
        if let recipient = billing.recipients.first {
          scheduleFocus(.recipient(recipient.id))
        }
        return false
      }
    case .message:
      if let message = CommunicationContent.validationMessage(subject: subject, message: message) {
        sendErrorMessage = message
        scheduleFocus(CommunicationContent.normalizedSubject(subject).isEmpty
          || CommunicationContent.normalizedSubject(subject).unicodeScalars.count
            > CommunicationContent.maximumSubjectLength
          ? .subject : .message)
        return false
      }
    case .template, .review:
      break
    }
    return true
  }

  private func scheduleFocus(_ field: CommunicationComposerFocus) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
    }
  }

  private var ownerScopeLabel: String {
    switch billing.owner {
    case .organization: "Salvar para a organização"
    case .user: "Salvar para minha conta"
    }
  }

  private func binding(for id: RecipientID) -> Binding<Bool> {
    Binding(
      get: { selectedRecipients.contains(id) },
      set: { isOn in
        if isOn { selectedRecipients.insert(id) } else { selectedRecipients.remove(id) }
      }
    )
  }

  private func applyTemplateIfNeeded() {
    guard appliedTemplateType != commType else { return }
    appliedTemplateType = commType
    let template = billing.template(for: commType)
    subject = template?.subject ?? ""
    message = template?.body ?? ""
  }

  private func send() async {
    guard !isSending else { return }
    sendErrorMessage = nil
    guard availableTypes.contains(commType), !bill.isRenderingPDF else {
      sendErrorMessage = "Aguarde a fatura ficar pronta antes de enviar."
      return
    }
    guard !selectedRecipients.isEmpty else {
      sendErrorMessage = "Selecione ao menos um destinatário."
      return
    }
    if let message = CommunicationContent.validationMessage(subject: subject, message: message) {
      sendErrorMessage = message
      return
    }
    let normalizedSubject = CommunicationContent.normalizedSubject(subject)
    let normalizedMessage = CommunicationContent.normalizedMessage(message)
    isSending = true
    defer { isSending = false }
    do {
      let orderedIDs = billing.recipients.map(\.id).filter(selectedRecipients.contains)
      _ = try await app.dependencies.communications.sendCommunication(
        billingID: billing.id,
        billID: bill.id,
        commType: commType,
        recipientIDs: orderedIDs,
        subject: normalizedSubject,
        message: normalizedMessage,
        acknowledgeWarning: false,
        saveScope: saveScope
      )
      dismiss()
      app.showNotice("Comunicação enfileirada para envio.")
    } catch { sendErrorMessage = DemoError(error).message }
  }
}

private enum ExportWizardStep: Hashable {
  case format
  case contents
  case review
}

struct ExportSimulationView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  @State private var format = BillingExportContract.formats[0]
  @State private var selectedStep: ExportWizardStep = .format
  @State private var requestingExport = false

  var body: some View {
    RentivoFormWizard(
      title: "Exportar",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isDirty: format != BillingExportContract.formats[0],
      isBusy: requestingExport,
      primaryTitle: "Solicitar exportação",
      onValidateAndAdvance: { true },
      onCommit: { Task { await requestExport() } }
    ) { step in
      switch step {
      case .format:
        RentivoWizardSection("Formato") {
          Picker("Formato", selection: $format) {
            ForEach(BillingExportContract.formats, id: \.self) { format in
              Text(format.uppercased()).tag(format)
            }
          }
          .pickerStyle(.segmented)
        }
      case .contents:
        RentivoWizardSection("Conteúdo") {
          ForEach(BillingExportContract.includedSections, id: \.self) { section in
            Label(section, systemImage: "doc.text")
          }
        }
      case .review:
        RentivoWizardSection("Resumo") {
          RentivoWizardReviewRow(label: "Formato", value: format.uppercased())
          RentivoWizardReviewRow(
            label: "Conteúdo", value: BillingExportContract.includedSections.joined(separator: ", ")
          )
        }
      }
    }
  }

  private var descriptors: [RentivoWizardStepDescriptor<ExportWizardStep>] {
    [
      RentivoWizardStepDescriptor(id: .format, title: "Formato"),
      RentivoWizardStepDescriptor(id: .contents, title: "Conteúdo"),
      RentivoWizardStepDescriptor(id: .review, title: "Revisar exportação"),
    ]
  }

  private func requestExport() async {
    guard !requestingExport else { return }
    requestingExport = true
    defer { requestingExport = false }
    do {
      try await app.dependencies.exports.requestExport(billingID: billingID, format: format)
      app.showNotice("Exportação \(format.uppercased()) enfileirada.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}
