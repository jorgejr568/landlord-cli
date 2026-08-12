import RentivoCore
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
    .padding(.horizontal, RentivoSpacing.small)
    .rentivoHoverTint()
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
            HStack {
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
          await load()
          await onMutation()
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
      await load()
      await onMutation()
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
    }
    .formStyle(.grouped)
    .navigationTitle("Nova despesa")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(description.isEmpty || centavos <= 0)
      }
    }
  }

  private func save() async {
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
    } catch { app.reportFailure(error) }
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
              // A single-action menu behind an unlabeled "..." icon added an extra click for no
              // reason; this was the only action, so it is a direct, accessibly-labeled button.
              Button {
                Task { await download(attachment) }
              } label: {
                Label("Abrir", systemImage: "arrow.down.circle")
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
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
        }
      }
    }
    .overlay {
      if canWrite {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(RentivoColors.emerald, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
          .opacity(isDropTargeted ? 1 : 0)
          .allowsHitTesting(false)
          .padding(RentivoSpacing.small)
      }
    }
    .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    .dropDestination(for: URL.self) { urls, _ in
      guard canWrite, let url = ReceiptIntake.firstFileURL(in: urls) else { return false }
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
    do {
      // Unlike a receipt, an attachment is stored as uploaded — no format clamping — so this
      // only needs the security-scoped read the sandbox requires for a chosen or dropped file.
      let accessGranted = fileURL.startAccessingSecurityScopedResource()
      defer { if accessGranted { fileURL.stopAccessingSecurityScopedResource() } }
      let upload = try FileUpload.from(url: fileURL)
      _ = try await app.dependencies.attachments.addAttachment(
        billingID: billingID,
        upload: upload
      )
      await load()
      app.showNotice("Arquivo enviado.")
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
    }
    .formStyle(.grouped)
    .navigationTitle("Exportar")
  }

  private func requestExport() async {
    do {
      try await app.dependencies.exports.requestExport(billingID: billingID, format: format.lowercased())
      app.showNotice("Exportação \(format) enfileirada.")
    } catch { app.reportFailure(error) }
  }
}
