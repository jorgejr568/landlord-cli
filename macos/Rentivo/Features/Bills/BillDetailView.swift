import RentivoCore
import SwiftUI

struct BillDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  let billID: BillID
  let onMutation: () async -> Void

  @State private var state: LoadState<Bill> = .idle
  @State private var billing: Billing?
  @State private var showingEdit = false
  @State private var downloadedFile: DownloadedFile?
  @State private var showingCommunication = false
  @State private var confirmingDelete = false
  /// Bumped by `regenerate` so the poll loop restarts for the render it just enqueued, even when
  /// the bill was already `pending`.
  @State private var pollGeneration = 0

  private var pollKey: String {
    "\(app.dataRevision)-\(pollGeneration)-\(state.value?.isRenderingPDF == true)"
  }

  var body: some View {
    PageStateView(state: state) { bill in
      content(bill)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Fatura")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if state.value?.status == .draft && billing?.capabilities.canManageBills == true {
          Button("Editar") { showingEdit = true }
        }
      }
    }
    .sheet(isPresented: $showingEdit) {
      if let billing, let bill = state.value {
        NavigationStack {
          BillFormView(billing: billing, bill: bill) {
            await refreshAll()
          }
        }
        .billingSheetFrame()
      }
    }
    .downloadedFileSheet($downloadedFile)
    .sheet(isPresented: $showingCommunication) {
      if let billing, let bill = state.value {
        NavigationStack {
          CommunicationComposerView(billing: billing, bill: bill)
        }
        .billingSheetFrame()
      }
    }
    .confirmationDialog("Excluir esta fatura?", isPresented: $confirmingDelete) {
      Button("Excluir fatura", role: .destructive) { Task { await deleteBill() } }
      Button("Cancelar", role: .cancel) {}
    }
    .task(id: app.dataRevision) { await load() }
    .task(id: pollKey) { await pollWhileRendering() }
  }

  private func content(_ bill: Bill) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        summaryCard(bill)

        // Wide windows read the fatura as two related halves: what it is made of and what
        // document it produced, next to where it stands and what backs it up.
        BillingAdaptiveColumns {
          lineItems(bill)
          document(bill)
        } trailing: {
          lifecycleSection(bill)
          ReceiptManagerView(
            billingID: billingID,
            bill: bill,
            canWrite: billing?.capabilities.canUploadBillReceipts == true
          ) { await refreshAll() }
        }

        if billing?.capabilities.canManageBills == true {
          Button {
            showingCommunication = true
          } label: {
            Label("Enviar comunicação", systemImage: "paperplane.fill")
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(bill.isRenderingPDF)

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
              .font(.subheadline.weight(.semibold))
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
            .font(.subheadline)
        }
        if let paidAt = bill.paidAt {
          Label("Pago em \(paidAt.displayFormatted)", systemImage: "checkmark.seal.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RentivoColors.emerald)
        }
      }
    }
  }

  private func document(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      BillingSectionTitle(title: "Documento", symbol: "doc.richtext.fill")
      renderStatus(bill)
      Button {
        Task { await downloadInvoice() }
      } label: {
        Label("Abrir fatura em PDF", systemImage: "doc.text.magnifyingglass")
      }
      .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
      .disabled(bill.isRenderingPDF || !bill.capabilities.canDownloadInvoice)
      HStack {
        // Regenerating stays available while a render is pending: a re-trigger supersedes the
        // in-flight render server-side.
        Button("Regenerar documento") { Task { await regenerate(bill) } }
          .disabled(billing?.capabilities.canManageBills != true)
        if bill.status == .paid {
          // Gated on the pending render alone: the app opens `GET .../recibo`, which renders the
          // recibo inline when no file is stored yet, so `canDownloadRecibo` (a stored-file gate)
          // would disable a button the endpoint would have served.
          Button("Abrir recibo") { Task { await downloadRecibo() } }
            .disabled(bill.isRenderingPDF)
        }
      }
      .buttonStyle(.bordered)
      if bill.isRenderingPDF {
        Text("Os documentos ficam disponíveis assim que a geração terminar.")
          .font(.footnote)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    }
  }

  @ViewBuilder
  private func lifecycleSection(_ bill: Bill) -> some View {
    if billing?.capabilities.canManageBills == true {
      lifecycle(bill)
    } else {
      Label("Ciclo disponível somente para quem pode gerenciar faturas.", systemImage: "eye")
        .font(.footnote)
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
      .font(.footnote)
      .foregroundStyle(RentivoColors.secondaryInk)
      .accessibilityIdentifier("bill.pdf.rendering")
    case .failed:
      Label("Falha no PDF", systemImage: "exclamationmark.triangle")
        .font(.footnote)
        .foregroundStyle(RentivoColors.coral)
        .accessibilityIdentifier("bill.pdf.failed")
    case .succeeded, nil:
      EmptyView()
    }
  }

  private func lineItems(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      BillingSectionTitle(title: "Composição", symbol: "list.bullet")
      RentivoCard {
        VStack(spacing: RentivoSpacing.medium) {
          ForEach(bill.lineItems) { line in
            HStack {
              VStack(alignment: .leading) {
                Text(line.description).font(.subheadline.weight(.semibold))
                Text(line.kind.sectionTitle)
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
              Spacer()
              MoneyText(money: line.amount)
            }
          }
          if !bill.notes.isEmpty {
            Divider()
            Text(bill.notes)
              .font(.footnote)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }
      }
    }
  }

  private func lifecycle(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      BillingSectionTitle(title: "Ciclo da fatura", symbol: "arrow.triangle.2.circlepath")
      // Prefer the server-authoritative transitions for this specific bill (`available_transitions`)
      // over the local `BillStatus` state machine, when the API supplies them.
      if bill.effectiveTransitions.isEmpty {
        Label("Esta fatura está em um estado final.", systemImage: "checkmark.circle")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(
          bill.effectiveTransitions.sorted { $0.rawValue < $1.rawValue },
          id: \.self
        ) { status in
          Button {
            Task { await transition(to: status) }
          } label: {
            Label("Marcar como \(status.label.lowercased())", systemImage: status.symbol)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("bill.transition.\(status.rawValue)")
        }
      }
    }
  }

  private func load() async {
    state = .loading
    do {
      let loadedBilling = try await app.dependencies.billings.billing(id: billingID)
      let loadedBill = try await app.dependencies.bills.bill(billingID: billingID, id: billID)
      billing = loadedBilling
      withAnimation(BillingsMotion.load) {
        state = .loaded(loadedBill)
      }
    } catch {
      state = .failed(DemoError(error))
    }
  }

  /// Re-fetches the bill without ever entering `.loading`, so a poll tick can never replace the
  /// screen the user is reading with `PageStateView`'s spinner.
  private func refreshQuietly() async {
    do {
      let refreshedBilling = try await app.dependencies.billings.billing(id: billingID)
      let refreshedBill = try await app.dependencies.bills.bill(billingID: billingID, id: billID)
      guard !Task.isCancelled else { return }
      billing = refreshedBilling
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

  private func refreshAll() async {
    await load()
    await onMutation()
  }

  private func transition(to status: BillStatus) async {
    do {
      try await app.dependencies.bills.transitionBill(
        billingID: billingID, billID: billID, to: status)
      await refreshAll()
      app.showNotice("Fatura marcada como \(status.label.lowercased()).")
    } catch {
      app.showNotice(DemoError(error).message, kind: .warning)
    }
  }

  private func deleteBill() async {
    do {
      try await app.dependencies.bills.deleteBill(billingID: billingID, billID: billID)
      await onMutation()
      dismiss()
    } catch {
      app.showNotice(DemoError(error).message, kind: .warning)
    }
  }

  private func regenerate(_ bill: Bill) async {
    do {
      let queued = try await app.dependencies.bills.regenerateBill(
        billingID: billingID, billID: bill.id)
      // The 202 body is the bill *summary* (no receipts), so merging only its render/status
      // metadata flips the screen to "Renderizando…" without a round trip and without blanking
      // the receipt list; bumping the generation restarts the poll loop.
      state = .loaded(bill.applyingRenderMetadata(from: queued))
      pollGeneration += 1
      await onMutation()
      app.showNotice("Documento enfileirado para regeneração.")
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func downloadInvoice() async {
    do {
      downloadedFile = try await app.dependencies.downloads.downloadInvoice(
        billingID: billingID, billID: billID)
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func downloadRecibo() async {
    do {
      downloadedFile = try await app.dependencies.downloads.downloadRecibo(
        billingID: billingID, billID: billID)
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
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
