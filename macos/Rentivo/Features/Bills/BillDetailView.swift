import RentivoCore
import SwiftUI

struct BillDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  let billID: BillID

  @State private var state: LoadState<Bill> = .idle
  @State private var billing: Billing?
  @State private var showingEdit = false
  @State private var downloadedFile: DownloadedFile?
  @State private var showingCommunication = false
  @State private var confirmingDelete = false
  @State private var pendingTransition: BillTransition?
  /// Bumped by `regenerate` so the poll loop restarts for the render it just enqueued, even when
  /// the bill was already `pending`.
  @State private var pollGeneration = 0
  /// Which document is being fetched, so its own button shows the wait and a second click cannot
  /// queue a duplicate download of a PDF the server has to render or sign again.
  @State private var downloadingDocument: BillDocumentDownload?
  /// The status a lifecycle transition is moving towards, or `nil` when none is in flight. Every
  /// transition button is disabled while one runs: they are mutually exclusive server-side, and a
  /// second one fired mid-flight would be judged against a status that is already gone.
  @State private var transitioningTo: BillStatus?
  @State private var isRegenerating = false

  private var pollKey: String {
    "\(app.dataRevision)-\(pollGeneration)-\(state.value?.isRenderingPDF == true)"
  }

  var body: some View {
    PageStateView(state: state) { bill in
      content(bill)
        .accessibilityIdentifier("bill.detail")
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Fatura")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if state.value?.status == .draft && state.value?.capabilities.canEdit == true {
          Button("Editar") { showingEdit = true }
        }
      }
    }
    .sheet(isPresented: $showingEdit) {
      if let billing, let bill = state.value {
        NavigationStack {
          BillFormView(billing: billing, bill: bill) {
            refreshAll()
          }
        }
        .rentivoSheetFrame()
      }
    }
    .downloadedFileSheet($downloadedFile)
    .sheet(isPresented: $showingCommunication) {
      if let billing, let bill = state.value {
        NavigationStack {
          CommunicationComposerView(billing: billing, bill: bill)
        }
        .rentivoSheetFrame()
      }
    }
    .confirmationDialog("Excluir esta fatura?", isPresented: $confirmingDelete) {
      Button("Excluir fatura", role: .destructive) { Task { await deleteBill() } }
      Button("Cancelar", role: .cancel) {}
    }
    .confirmationDialog(
      pendingTransition?.label ?? "Alterar status da fatura?",
      isPresented: Binding(presence: $pendingTransition),
      presenting: pendingTransition
    ) { action in
      Button(action.label, role: action.style == "danger" ? .destructive : nil) {
        pendingTransition = nil
        guard let currentStatus = state.value?.status else { return }
        Task { await transition(from: currentStatus, to: action.target) }
      }
      Button("Cancelar", role: .cancel) {}
    } message: { _ in
      Text("Confirme a alteração de status desta fatura.")
    }
    .task(id: app.dataRevision) { await load() }
    .task(id: pollKey) { await pollWhileRendering() }
  }

  private func content(_ bill: Bill) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        summaryCard(bill)
        lineItems(bill)
        document(bill)
        lifecycleSection(bill)
        ReceiptManagerView(
          billingID: billingID,
          bill: bill,
          capabilities: bill.capabilities
        ) { refreshAll() }
        communicationHistory(bill)

        if bill.capabilities.canCompose {
          Button {
            showingCommunication = true
          } label: {
            Label("Enviar comunicação", systemImage: "paperplane.fill")
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(!bill.capabilities.canSendInvoice && !bill.capabilities.canSendRecibo)
        }

        if bill.capabilities.canDelete {
          Button(role: .destructive) {
            confirmingDelete = true
          } label: {
            Label("Excluir fatura", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
      }
      .padding(RentivoSpacing.page)
    }
  }

  private func summaryCard(_ bill: Bill) -> some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        HStack {
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text(billing?.name ?? "Cobrança")
              .font(RentivoTypography.bodyStrong)
              .foregroundStyle(RentivoColors.secondaryInk)
            Text(bill.referenceMonth.label.capitalized)
              .font(RentivoTypography.title)
          }
          Spacer()
          StatusBadge(status: bill.status)
        }
        MoneyText(money: bill.effectiveTotal)
        if let dueDate = bill.dueDate {
          Label("Vencimento: \(dueDate.displayFormatted)", systemImage: "calendar")
            .font(RentivoTypography.body)
        }
        if let paidAt = bill.paidAt {
          Label("Pago em \(paidAt.displayFormatted)", systemImage: "checkmark.seal.fill")
            .font(RentivoTypography.bodyStrong)
            .foregroundStyle(RentivoColors.emerald)
        }
      }
    }
  }

  private func document(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Documento", symbol: "doc.richtext.fill")
      renderStatus(bill)
      Button {
        Task { await downloadInvoice() }
      } label: {
        HStack(spacing: RentivoSpacing.small) {
          if downloadingDocument == .invoice {
            ProgressView()
              .controlSize(.small)
              .tint(.white)
          }
          Label("Abrir fatura em PDF", systemImage: "doc.text.magnifyingglass")
        }
      }
      .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
      .disabled(
        bill.isRenderingPDF || !bill.capabilities.canDownloadInvoice || downloadingDocument != nil)
      HStack {
        // Regenerating stays available while a render is pending: a re-trigger supersedes the
        // in-flight render server-side.
        Button("Regenerar documento") { Task { await regenerate(bill) } }
          .disabled(!bill.capabilities.canRegenerate || isRegenerating)
        if bill.capabilities.canOpenRecibo {
          Button {
            Task { await downloadRecibo() }
          } label: {
            HStack(spacing: RentivoSpacing.small) {
              if downloadingDocument == .recibo {
                ProgressView()
                  .controlSize(.small)
              }
              Text("Abrir recibo")
            }
          }
          .disabled(bill.isRenderingPDF || downloadingDocument != nil)
        }
      }
      .buttonStyle(.bordered)
      if bill.isRenderingPDF {
        Text("Os documentos ficam disponíveis assim que a geração terminar.")
          .font(RentivoTypography.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    }
  }

  @ViewBuilder
  private func lifecycleSection(_ bill: Bill) -> some View {
    if bill.capabilities.canTransition {
      lifecycle(bill)
    } else {
      Label("Ciclo disponível somente para quem pode gerenciar faturas.", systemImage: "eye")
        .font(RentivoTypography.caption)
        .foregroundStyle(RentivoColors.secondaryInk)
    }
  }

  @ViewBuilder
  private func renderStatus(_ bill: Bill) -> some View {
    switch bill.pdfRenderStatus {
    case .pending:
      HStack(spacing: RentivoSpacing.small) {
        Label("Renderizando…", systemImage: "clock.arrow.circlepath")
        ProgressView()
          .controlSize(.small)
      }
      .font(RentivoTypography.caption)
      .foregroundStyle(RentivoColors.secondaryInk)
      .accessibilityIdentifier("bill.pdf.rendering")
    case .failed:
      Label("Falha no PDF", systemImage: "exclamationmark.triangle")
        .font(RentivoTypography.caption)
        .foregroundStyle(RentivoColors.coral)
        .accessibilityIdentifier("bill.pdf.failed")
    case .succeeded, nil:
      EmptyView()
    }
  }

  private func lineItems(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Composição", symbol: "list.bullet")
      RentivoCard {
        VStack(spacing: RentivoSpacing.medium) {
          ForEach(bill.lineItems) { line in
            HStack {
              VStack(alignment: .leading) {
                Text(line.description).font(RentivoTypography.bodyStrong)
                Text(line.kind.sectionTitle)
                  .font(RentivoTypography.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
              Spacer()
              MoneyText(money: line.amount)
            }
          }
          if !bill.notes.isEmpty {
            Divider()
            Text(bill.notes)
              .font(RentivoTypography.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }
      }
    }
  }

  private func lifecycle(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Ciclo da fatura", symbol: "arrow.triangle.2.circlepath")
      // Prefer the server-authoritative transitions for this specific bill (`available_transitions`)
      // over the local `BillStatus` state machine, when the API supplies them.
      if bill.effectiveTransitionActions.isEmpty {
        Label("Esta fatura está em um estado final.", systemImage: "checkmark.circle")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(bill.effectiveTransitionActions, id: \.target) { action in
          Button {
            if action.requiresConfirmation {
              pendingTransition = action
            } else {
              Task { await transition(from: bill.status, to: action.target) }
            }
          } label: {
            HStack(spacing: RentivoSpacing.small) {
              if transitioningTo == action.target {
                ProgressView()
                  .controlSize(.small)
                  .tint(.white)
              }
              Label(action.label, systemImage: action.target.symbol)
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(action.style == "danger" ? RentivoColors.coral : RentivoColors.emerald)
          .disabled(transitioningTo != nil)
          .accessibilityIdentifier("bill.transition.\(action.target.rawValue)")
        }
      }
      if let statusUpdatedAt = bill.statusUpdatedAt {
        Text("Status atualizado em \(statusUpdatedAt.formattedPTBR(time: .shortened)).")
          .font(RentivoTypography.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    }
  }

  private func communicationHistory(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Comunicações", symbol: "envelope.badge")
      if bill.communications.isEmpty {
        Text("Nenhuma comunicação enviada.")
          .font(RentivoTypography.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        RentivoCard {
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            ForEach(Array(bill.communications.enumerated()), id: \.element.id) { index, item in
              if index > 0 { Divider() }
              VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                HStack {
                  Text(item.createdAt?.formattedPTBR(time: .shortened) ?? "Data indisponível")
                    .font(RentivoTypography.metadata.monospacedDigit())
                  Spacer()
                  Text(item.deliveryLabel)
                    .font(RentivoTypography.metadata)
                    .foregroundStyle(item.status == "failed" ? RentivoColors.coral : RentivoColors.secondaryInk)
                }
                if item.isRedacted {
                  Text("Dados do destinatário protegidos")
                    .font(RentivoTypography.bodyStrong)
                } else {
                  Text([item.recipientName, item.recipientEmail].compactMap { $0 }.joined(separator: " · "))
                    .font(RentivoTypography.bodyStrong)
                  if let subject = item.subject { Text(subject).font(RentivoTypography.caption) }
                }
              }
            }
          }
        }
      }
    }
  }

  private func load() async {
    state.prepareForRefresh()
    do {
      let pair = try await BillDetailLoading.billingAndBill(
        billingID: billingID,
        billID: billID,
        billings: app.dependencies.billings,
        bills: app.dependencies.bills
      )
      billing = pair.billing
      state = .loaded(pair.bill)
    } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }

  /// Re-fetches the bill without ever entering `.loading`, so a poll tick can never replace the
  /// screen the user is reading with `PageStateView`'s spinner.
  ///
  /// Only the bill: the loop exists to watch `pdf_render_status`, which lives on the fatura. The
  /// cobrança's name and capabilities cannot change as a side effect of a PDF render, so refetching
  /// it every tick doubled the polling traffic for an answer that was already on screen. It stays
  /// whatever `load()` last resolved.
  private func refreshQuietly() async {
    do {
      let refreshedBill = try await app.dependencies.bills.bill(billingID: billingID, id: billID)
      guard !Task.isCancelled else { return }
      state = .loaded(refreshedBill)
    } catch {
      // A failed silent refresh leaves the current state untouched; the loop retries on the next
      // tick. Reporting it would put a warning banner on the screen for a poll the user never
      // asked for.
    }
  }

  private func pollWhileRendering() async {
    while !Task.isCancelled, BillPDFPolling.shouldPoll(state.value) {
      try? await Task.sleep(for: BillPDFPolling.interval)
      // `Task.sleep` swallows its own cancellation above, so the flag is the only signal that the
      // view went away while we waited.
      if Task.isCancelled { return }
      await refreshQuietly()
    }
  }

  private func refreshAll() {
    app.invalidateData()
  }

  private func transition(from currentStatus: BillStatus, to status: BillStatus) async {
    guard transitioningTo == nil else { return }
    transitioningTo = status
    defer { transitioningTo = nil }
    do {
      try await app.dependencies.bills.transitionBill(
        billingID: billingID, billID: billID, from: currentStatus, to: status)
      app.showNotice("Fatura marcada como \(status.label.lowercased()).")
      refreshAll()
    } catch {
      app.reportFailure(error)
    }
  }

  private func deleteBill() async {
    do {
      try await app.dependencies.bills.deleteBill(billingID: billingID, billID: billID)
      app.invalidateData()
      dismiss()
    } catch {
      app.reportFailure(error)
    }
  }

  private func regenerate(_ bill: Bill) async {
    guard !isRegenerating else { return }
    isRegenerating = true
    defer { isRegenerating = false }
    do {
      let queued = try await app.dependencies.bills.regenerateBill(
        billingID: billingID, billID: bill.id)
      // The 202 body is the bill *summary* (no receipts), so merging only its render/status
      // metadata flips the screen to "Renderizando…" without a round trip and without blanking
      // the receipt list; bumping the generation restarts the poll loop.
      state = .loaded(bill.applyingRenderMetadata(from: queued))
      pollGeneration += 1
      app.showNotice("Documento enfileirado para regeneração.")
      app.invalidateData()
    } catch { app.reportFailure(error) }
  }

  private func downloadInvoice() async {
    guard downloadingDocument == nil else { return }
    downloadingDocument = .invoice
    defer { downloadingDocument = nil }
    do {
      downloadedFile = try await app.dependencies.downloads.downloadInvoice(
        billingID: billingID, billID: billID)
    } catch { app.reportFailure(error) }
  }

  private func downloadRecibo() async {
    guard downloadingDocument == nil else { return }
    downloadingDocument = .recibo
    defer { downloadingDocument = nil }
    do {
      downloadedFile = try await app.dependencies.downloads.downloadRecibo(
        billingID: billingID, billID: billID)
    } catch { app.reportFailure(error) }
  }
}

/// Which of the fatura's two documents is being fetched. Both open the same download sheet, so the
/// screen needs to know *which* button to leave spinning while the bytes are on their way.
private enum BillDocumentDownload: Hashable {
  case invoice
  case recibo
}

extension BillStatus {
  fileprivate var symbol: String {
    switch self {
    case .draft: "pencil.circle"
    case .published: "megaphone.fill"
    case .sent: "paperplane.fill"
    case .paid: "checkmark.seal.fill"
    case .cancelled: "xmark.circle.fill"
    case .delayedPayment: "clock.badge.exclamationmark.fill"
    }
  }
}
