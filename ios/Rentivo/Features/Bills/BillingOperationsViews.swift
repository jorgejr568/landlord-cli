import SwiftUI
import UniformTypeIdentifiers
import WebKit

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
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
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
  @State private var preview: CommunicationPreview?
  @State private var acknowledgedWarnings = false
  @State private var isLoadingPreview = false
  @State private var isSending = false
  // Mirrors the web composer's `previewRequest` sequence (CommunicationComposePage.tsx): an
  // in-flight preview cannot be aborted here, so every response is checked against the generation
  // it was requested under and a superseded one is dropped instead of overwriting fresh state.
  @State private var previewGeneration = 0
  // Bumped by the refresh button; part of the preview task's id so a manual refresh runs as a
  // structured task that is cancelled on dismissal like every other preview request.
  @State private var manualPreviewRequests = 0
  // The comm type whose template currently populates the fields, so a manual refresh does not
  // re-apply a template over the user's edits.
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

  /// Identifies one preview request. Driving `.task(id:)` with this restarts — and genuinely
  /// cancels — the request whenever the comm type changes or the refresh button is tapped.
  private struct PreviewRequestKey: Equatable {
    let commType: CommunicationType
    let manualAttempt: Int
  }

  private var previewRequestKey: PreviewRequestKey {
    PreviewRequestKey(commType: commType, manualAttempt: manualPreviewRequests)
  }

  // The web attaches invalidation to the input's change event rather than to observation of the
  // value (CommunicationComposePage.tsx:236-237). These bindings do the same, which is what keeps a
  // programmatic template prefill from being mistaken for a user edit: an `onChange(of: subject)`
  // observer cannot tell the two apart and would disown the very request a type switch just made.
  private var subjectBinding: Binding<String> {
    Binding(
      get: { subject },
      set: { newValue in
        guard newValue != subject else { return }
        subject = newValue
        invalidatePreview()
      }
    )
  }

  private var messageBinding: Binding<String> {
    Binding(
      get: { message },
      set: { newValue in
        guard newValue != message else { return }
        message = newValue
        invalidatePreview()
      }
    )
  }

  private var availableTypes: [CommunicationType] {
    bill.status == .paid ? CommunicationType.allCases : [.billReady]
  }

  private var hasSevereWarnings: Bool { !(preview?.severeWarnings.isEmpty ?? true) }
  private var hasMildWarnings: Bool { !(preview?.mildWarnings.isEmpty ?? true) }

  private var sendDisabled: Bool {
    // Defense in depth: the detail screen already disables the entry point while the PDF renders,
    // but a composer opened just before the render started must not attach a stale document.
    isSending || isLoadingPreview || preview == nil || hasSevereWarnings
      || (hasMildWarnings && !acknowledgedWarnings) || selectedRecipients.isEmpty
      || bill.isRenderingPDF
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
          TextField("Assunto", text: subjectBinding)
          TextField("Corpo (Markdown — HTML não é permitido)", text: messageBinding, axis: .vertical)
            .lineLimit(5...12)
          Button {
            manualPreviewRequests += 1
          } label: {
            if isLoadingPreview {
              Text("Atualizando...")
            } else {
              Label("Atualizar pré-visualização", systemImage: "eye")
            }
          }
          .disabled(isLoadingPreview || subject.isEmpty || message.isEmpty)
        } header: {
          Text("Mensagem")
        } footer: {
          Text("Variáveis: {{nome_inquilino}}, {{unidade}}, {{mes}}, {{vencimento}}, {{total}}.")
        }

        Section("Pré-visualização") {
          if let preview {
            HTMLPreviewPanel(html: preview.html)
          } else {
            Text("A pré-visualização aparecerá aqui.")
              .font(.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }

        if hasSevereWarnings || hasMildWarnings {
          Section("Verificação de conteúdo") {
            if hasSevereWarnings, let preview {
              Text(
                "Conteúdo não permitido (ofensa grave ou ameaça): \(preview.severeWarnings.joined(separator: ", ")). Edite para enviar."
              )
              .font(.caption)
              .foregroundStyle(RentivoColors.coral)
            }
            if hasMildWarnings, let preview {
              Text("Linguagem possivelmente ofensiva: \(preview.mildWarnings.joined(separator: ", ")).")
                .font(.caption)
                .foregroundStyle(RentivoColors.coral)
            }
            if hasMildWarnings && !hasSevereWarnings {
              Toggle("Reconheço o aviso e quero enviar mesmo assim.", isOn: $acknowledgedWarnings)
                .font(.caption)
            }
          }
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
    // One structured task owns every preview request: the automatic one on open, the one after a
    // comm-type switch, and the manual refresh. Applying the template inside the task — rather than
    // from an `onChange(of: commType)` observer — also removes any dependency on the order in which
    // SwiftUI delivers the change callback and restarts the task.
    .task(id: previewRequestKey) {
      applyTemplateIfNeeded()
      await loadPreviewIfPossible()
    }
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

  /// Re-prefills subject and body from the newly selected type's template, writing the `@State`
  /// directly so the change is not mistaken for a user edit. A no-op when the type has not changed
  /// since the last application, which is what lets a manual refresh keep the user's own text.
  private func applyTemplateIfNeeded() {
    guard appliedTemplateType != commType else { return }
    appliedTemplateType = commType
    let template = billing.template(for: commType)
    subject = template?.subject ?? ""
    message = template?.body ?? ""
    invalidatePreview()
  }

  // Bumping the generation disowns any request already in flight: its response can no longer
  // restore a preview of the pre-edit content, which would otherwise re-open the send gate (and
  // hide the moderation panel) for text the server never checked. Clearing `isLoadingPreview` here
  // — as the web's `setPreviewing(false)` does — keeps the refresh button usable when the disowned
  // response lands and is dropped.
  private func invalidatePreview() {
    previewGeneration += 1
    preview = nil
    acknowledgedWarnings = false
    isLoadingPreview = false
  }

  private func loadPreviewIfPossible() async {
    guard !billing.recipients.isEmpty, !subject.isEmpty, !message.isEmpty else { return }
    await loadPreview()
  }

  private func loadPreview() async {
    previewGeneration += 1
    let generation = previewGeneration
    isLoadingPreview = true
    // Every write below is conditional on still being the current request, so an earlier or
    // superseded response can neither publish its preview nor clear the busy state of a newer one.
    defer { if generation == previewGeneration { isLoadingPreview = false } }
    do {
      let loaded = try await app.dependencies.communications.previewCommunication(
        billingID: billing.id, subject: subject, message: message
      )
      guard generation == previewGeneration else { return }
      preview = loaded
      acknowledgedWarnings = false
    } catch {
      // A cancelled request means the composer went away (or was superseded); reporting it would
      // put a warning banner on the screen the user just returned to. `Task.isCancelled` is the
      // load-bearing half of this check: `LiveAPIClient.transportError(from:)` rewrites
      // `URLError(.cancelled)` into a generic "não foi possível conectar" `LiveAPIError`, so the
      // error identity alone does not identify a cancellation on the live store.
      guard generation == previewGeneration, !Task.isCancelled, !isCancellation(error) else {
        return
      }
      app.showNotice(DemoError(error).message, kind: .warning)
    }
  }

  private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  private func send() async {
    guard !isSending else { return }
    guard !selectedRecipients.isEmpty else {
      app.showNotice("Selecione ao menos um destinatário.", kind: .warning)
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
        acknowledgeWarning: acknowledgedWarnings,
        saveScope: saveScope
      )
      dismiss()
      app.showNotice("Comunicação enfileirada para envio.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}

/// Inline preview of the rendered communication, sized to the document it loaded.
///
/// The send gate assumes the user actually read the rendered message, so the panel follows the
/// document height (as the web composer's flowing `<div>` does) instead of clipping it inside a
/// fixed viewport. Past `maxHeight` the web view keeps its own scrolling so nothing is
/// unreachable on a very long template.
private struct HTMLPreviewPanel: View {
  let html: String

  private static let minHeight: CGFloat = 80
  private static let maxHeight: CGFloat = 600

  @State private var documentHeight: CGFloat = HTMLPreviewPanel.minHeight

  var body: some View {
    HTMLPreviewView(html: html, documentHeight: $documentHeight)
      .frame(height: min(max(documentHeight, Self.minHeight), Self.maxHeight))
  }
}

private struct HTMLPreviewView: UIViewRepresentable {
  let html: String
  @Binding var documentHeight: CGFloat

  private static let heightHandler = "rentivoPreviewHeight"

  // Reports the body height at load and on every relayout (late sizing, rotation, images
  // finishing). `body.scrollHeight` is content-driven — unlike the document element's, which is
  // at least the viewport height — so growing the frame to the reported height cannot feed back
  // into an ever-taller measurement.
  private static let measureScript = """
    (function () {
      function report() {
        window.webkit.messageHandlers.\(heightHandler).postMessage(document.body.scrollHeight);
      }
      new ResizeObserver(report).observe(document.body);
      report();
    })();
    """

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.addUserScript(
      WKUserScript(source: Self.measureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    )
    configuration.userContentController.add(context.coordinator, name: Self.heightHandler)
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    // Only ever engaged for documents taller than the cap: shorter ones have a frame that already
    // matches their height, so the Form keeps the scroll gesture.
    webView.scrollView.isScrollEnabled = true
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.parent = self
    // Reloading on every update would restart the measurement, and the height it publishes
    // re-enters this method — so the document is loaded only when its content actually changes.
    guard context.coordinator.loadedHTML != html else { return }
    context.coordinator.loadedHTML = html
    webView.loadHTMLString(Self.document(for: html), baseURL: nil)
  }

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    webView.configuration.userContentController.removeScriptMessageHandler(forName: heightHandler)
  }

  /// Wraps the server's Markdown-rendered fragment in a minimal document. The viewport tag makes
  /// the layout width the view's own width, which both keeps the text legible (WebKit otherwise
  /// lays a bare fragment out at 980pt and scales it down) and makes the measured CSS pixels
  /// equal to points. A full document — should the contract ever return one — is loaded as is.
  private static func document(for html: String) -> String {
    let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !trimmed.hasPrefix("<!doctype"), !trimmed.hasPrefix("<html") else { return html }
    return """
      <!doctype html>
      <html lang="pt-BR"><head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
      :root { color-scheme: light dark; }
      body {
        margin: 0;
        background: transparent;
        font: -apple-system-body;
        font-family: -apple-system, system-ui, sans-serif;
        line-height: 1.45;
        overflow-wrap: break-word;
      }
      img, table { max-width: 100%; }
      </style>
      </head><body>\(html)</body></html>
      """
  }

  @MainActor final class Coordinator: NSObject, WKScriptMessageHandler {
    var parent: HTMLPreviewView
    var loadedHTML: String?

    init(parent: HTMLPreviewView) { self.parent = parent }

    func userContentController(
      _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      guard let height = (message.body as? NSNumber)?.doubleValue else { return }
      // Sub-point jitter would republish state on every relayout for no visible gain.
      guard abs(parent.documentHeight - height) > 0.5 else { return }
      parent.documentHeight = height
    }
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
