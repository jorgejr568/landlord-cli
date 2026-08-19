import QuickLook
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
    PageStateView(
      state: state,
      emptyState: EmptyStateConfiguration(
        title: "Nenhuma despesa registrada",
        message: canWrite
          ? "Registre a primeira despesa para acompanhar os custos desta cobrança."
          : "Não há despesas registradas nesta cobrança.",
        systemImage: "wrench.and.screwdriver.fill",
        actionTitle: canWrite ? "Adicionar despesa" : nil
      ),
      emptyAction: canWrite ? { showingAdd = true } : nil
    ) { expenses in
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
      .rentivoTabContent()
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
          Label("Adicionar despesa", systemImage: "plus")
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
    .noticeArea(.billOperations)
  }

  private func load() async {
    let hadVisibleState: Bool = switch state {
    case .loaded, .empty: true
    default: false
    }
    if !hadVisibleState { state = .loading }
    do {
      let expenses = try await app.dependencies.expenses.listExpenses(billingID: billingID)
      state = expenses.isEmpty ? .empty : .loaded(expenses)
    } catch {
      if hadVisibleState {
        app.showNotice(UserFacingError.message(for: error, operation: .loadExpenses), kind: .warning)
      } else {
        state = .failed(UserFacingError.presentation(for: error, operation: .loadExpenses).demoError)
      }
    }
  }

  private func remove(_ expense: Expense) async {
    do {
      try await app.dependencies.expenses.deleteExpense(billingID: billingID, expenseID: expense.id)
      await load()
      await onMutation()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .deleteExpense), kind: .warning)
    }
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
  @State private var submitRequiresAuthenticator = false
  @State private var saving = false
  @FocusState private var focusedField: ExpenseFormFocus?
  @AccessibilityFocusState private var accessibilityFocusedField: ExpenseFormFocus?

  var body: some View {
    RentivoFormWizard(
      title: "Nova despesa",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isBusy: saving,
      finalActionTitle: "Salvar despesa",
      onValidateAndAdvance: validateAndAdvance,
      onCommit: { Task { await save() } }
    ) { step in
      switch step {
      case .details:
        RentivoWizardSection("Detalhes") {
          RentivoTextFormField(
            label: "Descrição",
            text: $description,
            errorMessage: selectedStep == .details ? submitErrorMessage : nil,
            accessibilityIdentifier: "expense.form.description"
          )
            .textInputAutocapitalization(.sentences)
            .focused($focusedField, equals: .description)
            .accessibilityFocused($accessibilityFocusedField, equals: .description)
          RentivoFormField(label: "Categoria") {
            Picker("", selection: $category) {
              ForEach(ExpenseCategory.allCases, id: \.self) { category in
                Text(category.label).tag(category)
              }
            }
            .labelsHidden()
            .accessibilityLabel("Categoria")
            .accessibilityIdentifier("expense.form.category")
          }
        }
      case .valueAndDate:
        RentivoWizardSection("Valor e data") {
          RentivoCurrencyField(
            label: "Valor",
            amountInCents: $centavos,
            errorMessage: selectedStep == .valueAndDate ? submitErrorMessage : nil,
            isFocused: amountFocusBinding,
            isAccessibilityFocused: accessibilityAmountFocusBinding,
            accessibilityIdentifier: "expense.form.amount"
          )
          RentivoFormField(label: "Data") {
            DatePicker("", selection: $incurredOn, displayedComponents: .date)
              .labelsHidden()
              .accessibilityLabel("Data")
              .accessibilityIdentifier("expense.form.date")
          }
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
    .interactiveDismissDisabled(saving || isDirty)
    .onChange(of: description) {
      if selectedStep == .details, submitErrorMessage != nil,
        ExpenseInput.isValidDescription(description)
      {
        submitErrorMessage = nil
      }
    }
    .onChange(of: centavos) {
      if selectedStep == .valueAndDate, submitErrorMessage != nil, centavos > 0 {
        submitErrorMessage = nil
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
      VStack(alignment: .leading, spacing: RentivoSpacing.small) {
        Label(submitErrorMessage, systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(RentivoColors.coral)
        if submitRequiresAuthenticator {
          Button("Configurar autenticador") {
            dismiss()
            Task { @MainActor in app.navigateToAuthenticatorSetup() }
          }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("error.configure-authenticator")
        }
      }
      .accessibilityIdentifier("expense.form.error")
    }
  }

  private var isDirty: Bool {
    !description.isEmpty || centavos != 0 || category != .maintenance || selectedDate != DateOnly(from: Date())
  }

  private func validateAndAdvance() -> Bool {
    submitErrorMessage = nil
    submitRequiresAuthenticator = false
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
    submitRequiresAuthenticator = false
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
    } catch {
      let failure = UserFacingError.presentation(for: error, operation: .addExpense)
      submitErrorMessage = failure.message
      submitRequiresAuthenticator = failure.recovery == .configureAuthenticator
    }
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
  @State private var isUploading = false

  var body: some View {
    PageStateView(
      state: state,
      emptyState: EmptyStateConfiguration(
        title: "Nenhum arquivo adicionado",
        message: canWrite
          ? "Adicione documentos ou imagens para encontrá-los junto desta cobrança."
          : "Não há arquivos nesta cobrança.",
        systemImage: "folder.fill",
        actionTitle: canWrite ? "Adicionar arquivo" : nil
      ),
      emptyAction: canWrite ? { showingFileImporter = true } : nil
    ) { attachments in
      List {
        Section {
          ForEach(attachments) { attachment in
            let presentation = attachment.documentPresentation
            HStack {
              Label {
                VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                  Text(presentation.displayName).font(.headline)
                  Text(
                    DocumentPresentation.metadataLine(
                      byteCount: attachment.byteCount, createdAt: attachment.createdAt)
                  )
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
                }
              } icon: {
                let symbol = DocumentPresentation.symbolName(
                  mediaType: attachment.mediaType, filename: attachment.filename)
                Image(systemName: symbol)
                  .accessibilityIdentifier("attachment.type.\(symbol)")
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
              .foregroundStyle(RentivoColors.emerald)
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
      .rentivoTabContent()
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
          Label("Adicionar arquivo", systemImage: "plus")
        }
        .disabled(isUploading)
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
    .noticeArea(.billOperations)
    .task(id: app.dataRevision) { await load() }
  }

  private func load() async {
    let hadVisibleState: Bool = switch state {
    case .loaded, .empty: true
    default: false
    }
    if !hadVisibleState { state = .loading }
    do {
      let values = try await app.dependencies.attachments.listAttachments(billingID: billingID)
      state = values.isEmpty ? .empty : .loaded(values)
    } catch {
      if hadVisibleState {
        app.showNotice(UserFacingError.message(for: error, operation: .loadAttachments), kind: .warning)
      } else {
        state = .failed(UserFacingError.presentation(for: error, operation: .loadAttachments).demoError)
      }
    }
  }

  private func add(fileURL: URL) async {
    guard !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    do {
      let upload = try await FileUpload.fromSecurityScoped(
        url: fileURL, policy: .rentivoDocument
      )
      _ = try await app.dependencies.attachments.addAttachment(
        billingID: billingID,
        upload: upload
      )
      await load()
      app.showNotice("Arquivo enviado.")
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .addAttachment), kind: .warning)
    }
  }

  private func remove(_ attachment: Attachment) async {
    do {
      try await app.dependencies.attachments.deleteAttachment(
        billingID: billingID, attachmentID: attachment.id)
      await load()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .deleteAttachment), kind: .warning)
    }
  }

  private func download(_ attachment: Attachment) async {
    do {
      downloadedFile = try await app.dependencies.downloads.downloadAttachment(
        billingID: billingID,
        attachmentID: attachment.id,
        presentation: attachment.documentPresentation
      )
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .openAttachment), kind: .warning)
    }
  }
}

struct DownloadShareView: View {
  @Environment(\.dismiss) private var dismiss
  let file: DownloadedFile

  var body: some View {
    NavigationStack {
      Group {
        if canPreview {
          QuickLookPreview(file: file)
            .accessibilityIdentifier("document.preview.quicklook")
            .accessibilityElement(children: .contain)
            .accessibilityLabel(file.displayName)
        } else {
          VStack(spacing: RentivoSpacing.medium) {
            Image(
              systemName: DocumentPresentation.symbolName(
                mediaType: file.mediaType, filename: file.filename)
            )
            .font(.system(size: 52))
            .foregroundStyle(RentivoColors.emerald)
            .accessibilityHidden(true)
            Text(file.displayName)
              .font(RentivoTypography.title)
              .multilineTextAlignment(.center)
            Text("Não foi possível exibir a prévia deste arquivo.")
              .foregroundStyle(RentivoColors.secondaryInk)
              .multilineTextAlignment(.center)
          }
          .padding(RentivoSpacing.page)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(RentivoColors.paper.ignoresSafeArea())
      .navigationTitle("Prévia")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Fechar") { dismiss() }
        }
        ToolbarItem(placement: .principal) {
          VStack(spacing: 0) {
            Text("Prévia")
              .font(.headline)
            Text(file.displayName)
              .font(.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
              .lineLimit(1)
              .accessibilityLabel(file.displayName)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          ShareLink(item: file.fileURL) {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Compartilhar ou salvar arquivo")
          .disabled(!fileExists)
        }
      }
      .tint(RentivoColors.emerald)
    }
  }

  private var fileExists: Bool {
    FileManager.default.fileExists(atPath: file.fileURL.path)
  }

  private var canPreview: Bool {
    fileExists && QLPreviewController.canPreview(file.fileURL as NSURL)
  }
}


private enum ExportWizardStep: Hashable {
  case format
  case contents
  case review
}

struct ExportSimulationView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  @State private var format = BillingExportContract.formats[0]
  @State private var selectedStep: ExportWizardStep = .format
  @State private var requestingExport = false
  @State private var exportFailure: UserFacingFailure?

  var body: some View {
    RentivoFormWizard(
      title: "Exportar",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isBusy: requestingExport,
      finalActionTitle: "Solicitar exportação",
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
        if let exportFailure {
          RentivoWizardSection("Não foi possível exportar") {
            UserFacingFailureView(failure: exportFailure) { openAuthenticatorSetup() }
              .accessibilityIdentifier("export.form.error")
          }
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
    exportFailure = nil
    requestingExport = true
    defer { requestingExport = false }
    do {
      try await app.dependencies.exports.requestExport(billingID: billingID, format: format)
      dismiss()
      app.showNotice(
        "Seu arquivo \(format.uppercased()) está sendo preparado. Você o receberá no e-mail da sua conta."
      )
    } catch {
      exportFailure = UserFacingError.presentation(for: error, operation: .requestExport)
    }
  }

  private func openAuthenticatorSetup() {
    dismiss()
    Task { @MainActor in app.navigateToAuthenticatorSetup() }
  }
}
