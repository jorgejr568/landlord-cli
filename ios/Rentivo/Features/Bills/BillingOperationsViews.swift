import SwiftUI
import UniformTypeIdentifiers

struct BillingOperationsLinks: View {
  let billingID: BillingID
  let capabilities: BillingCapabilities
  let onMutation: () async -> Void

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
            NavigationLink {
              ExportSimulationView(billingID: billingID)
            } label: {
              OperationRow(title: "Exportar dados", symbol: "square.and.arrow.up.fill")
            }
          }
        }
      }
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
    .sheet(isPresented: $showingAdd) {
      NavigationStack {
        ExpenseFormView(billingID: billingID) {
          await load()
          await onMutation()
        }
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

private struct ExpenseFormView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  let onSaved: () async -> Void
  @State private var description = ""
  @State private var centavos = 0
  @State private var category: ExpenseCategory = .maintenance
  @State private var incurredOn = Date()
  /// Server-side rejection (e.g. a 422) for the last submit. This form is presented in a sheet
  /// and the global notice banner renders behind it, so the message has to stay inline.
  @State private var submitErrorMessage: String?
  @State private var saving = false

  var body: some View {
    Form {
      TextField("Descrição", text: $description)
      CurrencyCentavosField("Valor em centavos", centavos: $centavos)
      Picker("Categoria", selection: $category) {
        ForEach(ExpenseCategory.allCases, id: \.self) { category in
          Text(category.label).tag(category)
        }
      }
      DatePicker("Data", selection: $incurredOn, displayedComponents: .date)
      if let submitErrorMessage {
        Label(submitErrorMessage, systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(RentivoColors.coral)
          .accessibilityIdentifier("expense.form.error")
      }
    }
    .navigationTitle("Nova despesa")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }.disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(saving || description.isEmpty || centavos <= 0)
      }
    }
    .interactiveDismissDisabled(saving)
  }

  private func save() async {
    guard !saving else { return }
    submitErrorMessage = nil
    saving = true
    defer { saving = false }
    do {
      _ = try await app.dependencies.expenses.createExpense(
        billingID: billingID,
        description: description,
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
  @State private var isSending = false
  /// Why the last send attempt failed, be it the local recipient check or a server rejection.
  /// The composer is presented in a sheet and the global notice banner renders behind it, so the
  /// message has to stay inline.
  @State private var sendErrorMessage: String?
  @State private var appliedTemplateType: CommunicationType

  init(billing: Billing, bill: Bill) {
    self.billing = billing
    self.bill = bill
    _selectedRecipients = State(initialValue: Set(billing.recipients.map(\.id)))
    let template = billing.template(for: .billReady)
    _subject = State(initialValue: template?.subject ?? "")
    _message = State(initialValue: template?.body ?? "")
    _appliedTemplateType = State(initialValue: .billReady)
  }

  private var availableTypes: [CommunicationType] {
    bill.status == .paid ? CommunicationType.allCases : [.billReady]
  }

  private var sendDisabled: Bool {
    // Defense in depth: the detail screen already disables the entry point while the PDF renders,
    // but a composer opened just before the render started must not attach a stale document.
    communicationSendIsDisabled(
      isSending: isSending,
      hasSelectedRecipients: !selectedRecipients.isEmpty,
      isRenderingPDF: bill.isRenderingPDF
    )
  }

  private var attachmentDescription: String {
    commType == .paymentReceipt ? "recibo" : "PDF da fatura"
  }

  var body: some View {
    Form {
      if billing.recipients.isEmpty {
        Section {
          Text("Nenhum destinatário cadastrado. Adicione destinatários na cobrança antes de enviar.")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      } else {
        if availableTypes.count > 1 {
          Section {
            Picker("Tipo", selection: $commType) {
              ForEach(availableTypes, id: \.self) { type in
                Text(type.label).tag(type)
              }
            }
            .pickerStyle(.segmented)
          }
        }

        Section {
          ForEach(billing.recipients) { recipient in
            Toggle(isOn: binding(for: recipient.id)) {
              VStack(alignment: .leading) {
                Text(recipient.name).font(.subheadline.weight(.semibold))
                Text(recipient.email)
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
            }
          }
        } header: {
          Text("Destinatários")
        } footer: {
          Text("Cada destinatário recebe um e-mail separado com o \(attachmentDescription) anexado.")
        }

        Section {
          TextField("Assunto", text: $subject)
          TextField("Corpo (Markdown — HTML não é permitido)", text: $message, axis: .vertical)
            .lineLimit(5...12)
        } header: {
          Text("Mensagem")
        } footer: {
          Text("Variáveis: {{nome_inquilino}}, {{unidade}}, {{mes}}, {{vencimento}}, {{total}}.")
        }

        Section {
          Picker("Salvar modelo", selection: $saveScope) {
            Text("Não salvar como modelo").tag(CommunicationSaveScope?.none)
            Text("Salvar para esta cobrança").tag(CommunicationSaveScope?.some(.billing))
            if billing.capabilities.canEdit {
              Text(ownerScopeLabel).tag(CommunicationSaveScope?.some(.owner))
            }
          }
        } footer: {
          Text("O modelo salvo preenche automaticamente as próximas comunicações.")
        }

        if let sendErrorMessage {
          Section {
            Label(sendErrorMessage, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("comm.error")
          }
        }

        Section {
          Button {
            Task { await send() }
          } label: {
            HStack(spacing: RentivoSpacing.small) {
              if isSending {
                ProgressView()
                  .tint(.white)
              }
              Text(isSending ? "Enviando..." : "Enviar \(commType.label.lowercased())")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(sendDisabled)
          .accessibilityIdentifier("comm.send")
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        }
      }
    }
    .navigationTitle("Enviar \(commType.label.lowercased())")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }
          .disabled(isSending)
      }
    }
    .onChange(of: commType) { _, _ in applyTemplateIfNeeded() }
    .interactiveDismissDisabled(isSending)
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
    guard !selectedRecipients.isEmpty else {
      sendErrorMessage = "Selecione ao menos um destinatário."
      return
    }
    isSending = true
    defer { isSending = false }
    do {
      let orderedIDs = billing.recipients.map(\.id).filter(selectedRecipients.contains)
      _ = try await app.dependencies.communications.sendCommunication(
        billingID: billing.id,
        billID: bill.id,
        commType: commType,
        recipientIDs: orderedIDs,
        subject: subject,
        message: message,
        acknowledgeWarning: false,
        saveScope: saveScope
      )
      dismiss()
      app.showNotice("Comunicação enfileirada para envio.")
    } catch { sendErrorMessage = DemoError(error).message }
  }
}

struct ExportSimulationView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  @State private var format = "CSV"

  var body: some View {
    Form {
      Picker("Formato", selection: $format) {
        Text("CSV").tag("CSV")
        Text("XLSX").tag("XLSX")
      }
      .pickerStyle(.segmented)
      Section("Conteúdo") {
        Label("Faturas", systemImage: "doc.text")
        Label("Despesas", systemImage: "wrench.and.screwdriver")
        Label("Resumo financeiro", systemImage: "chart.bar")
      }
      Button("Solicitar exportação") {
        Task { await requestExport() }
      }
      .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
      .listRowBackground(Color.clear)
    }
    .navigationTitle("Exportar")
  }

  private func requestExport() async {
    do {
      try await app.dependencies.exports.requestExport(billingID: billingID, format: format.lowercased())
      app.showNotice("Exportação \(format) enfileirada.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}
