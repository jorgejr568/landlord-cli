import RentivoCore
import SwiftUI
import UniformTypeIdentifiers

struct BillingOperationsLinks: View {
  let billingID: BillingID
  let capabilities: BillingCapabilities

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Operações", symbol: "square.grid.2x2.fill")
      RentivoCard {
        VStack(spacing: RentivoSpacing.small) {
          if capabilities.canReadExpenses {
            NavigationLink {
              ExpenseListView(
                billingID: billingID,
                canWrite: capabilities.canWriteExpenses
              )
            } label: {
              OperationRow(title: "Despesas", symbol: "wrench.and.screwdriver.fill")
            }
            .accessibilityIdentifier("billing.expenses")
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
        .font(RentivoTypography.bodyStrong)
        .foregroundStyle(RentivoColors.ink)
      Spacer()
      Image(systemName: "chevron.right")
        .foregroundStyle(RentivoColors.secondaryInk)
    }
    .contentShape(Rectangle())
    .padding(.vertical, RentivoSpacing.small)
    .padding(.horizontal, RentivoSpacing.small)
    .rentivoHoverTint()
  }
}

struct ExpenseListView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  let canWrite: Bool
  @State private var state: LoadState<[Expense]> = .idle
  @State private var showingAdd = false
  @State private var pendingDeletion: Expense?

  var body: some View {
    PageStateView(state: state) { expenses in
      List {
        Section {
          ForEach(expenses) { expense in
            HStack {
              VStack(alignment: .leading, spacing: RentivoSpacing.small) {
                HStack {
                  Text(expense.description).font(RentivoTypography.cardTitle)
                  Spacer()
                  MoneyText(money: expense.amount)
                }
                Label(expense.category.label, systemImage: "tag.fill")
                  .font(RentivoTypography.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
              // Swipe actions are an iOS gesture; on macOS the same destructive action is an
              // ordinary button on the row, backed by the same confirmation.
              if canWrite {
                Button(role: .destructive) {
                  pendingDeletion = expense
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(RentivoColors.secondaryInk)
                .accessibilityLabel("Excluir despesa \(expense.description)")
              }
            }
            .contextMenu {
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
    .accessibilityIdentifier("expense.list")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if canWrite {
          Button {
            showingAdd = true
          } label: {
            Label("Adicionar", systemImage: "plus")
          }
        }
      }
    }
    .sheet(isPresented: $showingAdd) {
      NavigationStack {
        ExpenseFormView(billingID: billingID) {
          app.invalidateData()
        }
      }
      .rentivoSheetFrame()
    }
    .confirmationDialog(
      "Excluir esta despesa?",
      isPresented: Binding(presence: $pendingDeletion),
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
    state.prepareForRefresh()
    do {
      let expenses = try await app.dependencies.expenses.listExpenses(billingID: billingID)
      withAnimation(BillingsMotion.load) {
        state = expenses.isEmpty ? .empty : .loaded(expenses)
      }
    } catch { state.settleFailure(error, reportingTo: app) }
  }

  private func remove(_ expense: Expense) async {
    do {
      try await app.dependencies.expenses.deleteExpense(billingID: billingID, expenseID: expense.id)
      app.invalidateData()
    } catch { app.reportFailure(error) }
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
  @State private var saving = false
  /// The failure is shown here rather than through `app.reportFailure`: the global banner renders
  /// behind this sheet, so a server rejection reported that way is invisible until the user gives
  /// up and dismisses the form that caused it.
  @State private var submissionError: String?

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

      if let submissionError {
        Section {
          Label(submissionError, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(RentivoColors.coral)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Nova despesa")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }
          .disabled(saving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(saving || !ExpenseInput.isValidDescription(description) || centavos <= 0)
      }
    }
    .interactiveDismissDisabled(saving)
  }

  private func save() async {
    guard !saving else { return }
    saving = true
    defer { saving = false }
    submissionError = nil
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
    } catch { submissionError = DemoError(error).message }
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
  @State private var isDropTargeted = false
  @State private var pendingDeletion: Attachment?
  /// Spans the off-main read and the request together, for the same reason as the receipts
  /// section: it is all one wait, and a second file dropped into it would race this one's reload.
  @State private var isUploading = false
  /// Which file is being fetched, so its own button shows the wait and repeated clicks cannot
  /// queue duplicate downloads.
  @State private var downloadingAttachmentID: AttachmentID?

  var body: some View {
    PageStateView(state: state) { attachments in
      List {
        Section {
          ForEach(attachments) { attachment in
            HStack {
              Label {
                VStack(alignment: .leading) {
                  Text(attachment.name).font(RentivoTypography.cardTitle)
                  Text(
                    ByteCountFormatter.string(
                      fromByteCount: Int64(attachment.byteCount), countStyle: .file)
                  )
                  .font(RentivoTypography.caption)
                }
              } icon: {
                Image(systemName: "doc.fill")
              }
              Spacer()
              // A single-action menu behind an unlabeled "..." icon added an extra click for no
              // reason; this was the only action, so it is a direct, accessibly-labeled button.
              if downloadingAttachmentID == attachment.id {
                ProgressView()
                  .controlSize(.small)
              } else {
                Button {
                  Task { await download(attachment) }
                } label: {
                  Label("Abrir", systemImage: "arrow.down.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(downloadingAttachmentID != nil)
              }
              if canWrite {
                Button(role: .destructive) {
                  pendingDeletion = attachment
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(RentivoColors.secondaryInk)
                .accessibilityLabel("Excluir arquivo \(attachment.name)")
              }
            }
            .contextMenu {
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
      ToolbarItem(placement: .primaryAction) {
        if canWrite {
          Button {
            showingFileImporter = true
          } label: {
            Label("Adicionar", systemImage: "plus")
          }
          .disabled(isUploading)
        }
      }
    }
    // The progress row sits in a bottom safe-area inset rather than inside the `List`, because the
    // list only exists in the `.loaded` state: the first upload into an empty section happens
    // while `PageStateView` is still showing its placeholder, and that is exactly when a user most
    // needs to see that something is happening.
    .safeAreaInset(edge: .bottom) {
      if isUploading {
        HStack(spacing: RentivoSpacing.small) {
          ProgressView()
            .controlSize(.small)
          Text("Enviando…")
            .font(RentivoTypography.body)
            .foregroundStyle(RentivoColors.secondaryInk)
          Spacer()
        }
        .padding(RentivoSpacing.medium)
        .background(.regularMaterial)
        .accessibilityIdentifier("attachment.uploading")
      }
    }
    .overlay {
      if canWrite {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(RentivoColors.emerald, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
          // `isDropTargeted` records only where the pointer is; whether the drop would be taken is
          // decided here, at render time. Folding `!isUploading` into the callback instead latched
          // a `false` for the whole of a drag that began during an upload, so the border stayed
          // dark even after the upload finished and the drop became available again.
          .opacity(isDropTargeted && !isUploading ? 1 : 0)
          .allowsHitTesting(false)
          .padding(RentivoSpacing.small)
      }
    }
    .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    .dropDestination(for: URL.self) { urls, _ in
      guard canWrite, !isUploading, let url = ReceiptIntake.firstFileURL(in: urls) else {
        return false
      }
      Task { await add(fileURL: url) }
      return true
    } isTargeted: { isDropTargeted = $0 }
    .downloadedFileSheet($downloadedFile)
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: ReceiptIntake.allowedContentTypes,
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await add(fileURL: url) }
    }
    .confirmationDialog(
      "Excluir este arquivo?",
      isPresented: Binding(presence: $pendingDeletion),
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
    state.prepareForRefresh()
    do {
      let values = try await app.dependencies.attachments.listAttachments(billingID: billingID)
      withAnimation(BillingsMotion.load) {
        state = values.isEmpty ? .empty : .loaded(values)
      }
    } catch { state.settleFailure(error, reportingTo: app) }
  }

  private func add(fileURL: URL) async {
    guard !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    do {
      // Unlike a receipt, an attachment is stored as uploaded rather than re-encoded. The shared
      // repository preflight still enforces the API's PDF/JPEG/PNG and 10 MB contract.
      let upload = try await ReceiptIntake.rawUpload(from: fileURL)
      _ = try await app.dependencies.attachments.addAttachment(
        billingID: billingID,
        upload: upload
      )
      app.showNotice("Arquivo enviado.")
      await load()
    } catch { app.reportFailure(error) }
  }

  private func remove(_ attachment: Attachment) async {
    do {
      try await app.dependencies.attachments.deleteAttachment(
        billingID: billingID, attachmentID: attachment.id)
      await load()
    } catch { app.reportFailure(error) }
  }

  private func download(_ attachment: Attachment) async {
    guard downloadingAttachmentID == nil else { return }
    downloadingAttachmentID = attachment.id
    defer { downloadingAttachmentID = nil }
    do {
      downloadedFile = try await app.dependencies.downloads.downloadAttachment(
        billingID: billingID, attachmentID: attachment.id
      )
    } catch { app.reportFailure(error) }
  }
}

struct ExportSimulationView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  @State private var format = BillingExportContract.formats[0]
  /// An export is a queued server job with no visible result on this screen, so without this the
  /// only feedback for a slow request is the absence of one — and an impatient second click
  /// enqueues a second export.
  @State private var isRequesting = false

  var body: some View {
    Form {
      Picker("Formato", selection: $format) {
        ForEach(BillingExportContract.formats, id: \.self) { format in
          Text(format.uppercased()).tag(format)
        }
      }
      .pickerStyle(.segmented)
      RentivoSection("Conteúdo") {
        ForEach(BillingExportContract.includedSections, id: \.self) { section in
          Label(section, systemImage: "doc.text")
        }
      }
      Button {
        Task { await requestExport() }
      } label: {
        HStack(spacing: RentivoSpacing.small) {
          if isRequesting {
            ProgressView()
              .controlSize(.small)
              .tint(.white)
          }
          Text(isRequesting ? "Solicitando…" : "Solicitar exportação")
        }
      }
      .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
      .disabled(isRequesting)
    }
    .formStyle(.grouped)
    .navigationTitle("Exportar")
  }

  private func requestExport() async {
    guard !isRequesting else { return }
    isRequesting = true
    defer { isRequesting = false }
    do {
      try await app.dependencies.exports.requestExport(billingID: billingID, format: format)
      app.showNotice("Exportação \(format.uppercased()) enfileirada.")
    } catch { app.reportFailure(error) }
  }
}
