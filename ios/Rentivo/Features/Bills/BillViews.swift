import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct EditableBillLine: Identifiable, Equatable {
  let id: BillLineItemID
  var description: String
  var centavos: Int
  var kind: BillLineItemKind

  init(line: BillLineItem) {
    id = line.id
    description = line.description
    centavos = line.amount.centavos
    kind = line.kind
  }

  init(description: String = "", centavos: Int = 0, kind: BillLineItemKind) {
    id = BillLineItemID(rawValue: UUID().uuidString)
    self.description = description
    self.centavos = centavos
    self.kind = kind
  }

  /// Seeds a line from an existing `BillingItem`, preserving its original id (a server-issued
  /// ULID). `createBill` keys `variable_amounts` by that original id, so minting a fresh client
  /// UUID here would silently drop any user-edited variable amount for a new bill.
  init(seededFrom item: BillingItem, kind: BillLineItemKind) {
    id = BillLineItemID(rawValue: item.id.rawValue)
    description = item.description
    centavos = item.amount.centavos
    self.kind = kind
  }

  var domain: BillLineItem {
    BillLineItem(
      id: id,
      description: description,
      amount: Money(centavos: centavos),
      kind: kind
    )
  }
}

private enum BillWizardStep: Hashable {
  case competence
  case dueDate
  case items
  case notes
  case review
}

enum BillFormFocus: Hashable {
  case lineDescription(BillLineItemID)
  case lineAmount(BillLineItemID)
  case addExtra
}

func billFormFocusTarget(issues: [ValidationIssue], lines: [BillLineItem]) -> BillFormFocus? {
  if issues.contains(where: { $0.field == .items }) { return .addExtra }
  if issues.contains(where: { $0.field == .itemDescription }),
    let line = lines.first(where: {
      $0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || $0.description.unicodeScalars.count > 255
    }) {
    return .lineDescription(line.id)
  }
  if issues.contains(where: { $0.field == .itemAmount }) {
    if let line = lines.first(where: {
      ($0.kind == .extra && $0.amount.centavos <= 0)
        || ($0.kind != .extra && $0.amount.centavos < 0)
    }) {
      return .lineAmount(line.id)
    }
    if !Money.fitsPersistedTotal(lines.lazy.map(\.amount.centavos)), let line = lines.first {
      return .lineAmount(line.id)
    }
  }
  return nil
}

struct BillFormView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billing: Billing
  let bill: Bill?
  let onSaved: () async -> Void

  @State private var year: Int
  @State private var month: Int
  @State private var dueDate: Date
  /// Set once the user touches the date picker. Until then the due date tracks the reference
  /// month pickers, so changing the competência moves a still-default vencimento along with it.
  @State private var dueDateEdited: Bool
  @State private var hasDueDate: Bool
  @State private var notes: String
  @State private var lines: [EditableBillLine]
  @State private var issues: [ValidationIssue] = []
  @State private var selectedStep: BillWizardStep = .competence
  /// Server-side rejection (e.g. a 422) for the last submit. This form is presented in a sheet
  /// and the global notice banner renders behind it, so the message has to stay inline.
  @State private var submitFailure: UserFacingFailure?
  @State private var hasValidatedItems = false
  @State private var saving = false
  @FocusState private var focusedField: BillFormFocus?
  @AccessibilityFocusState private var accessibilityFocusedField: BillFormFocus?
  private let initialReferenceMonth: ReferenceMonth
  private let initialDueDate: DateOnly?
  private let initialHasDueDate: Bool
  private let initialNotes: String
  private let initialLines: [BillLineItem]

  init(billing: Billing, bill: Bill? = nil, onSaved: @escaping () async -> Void) {
    self.billing = billing
    self.bill = bill
    self.onSaved = onSaved
    let currentComponents = Calendar.current.dateComponents([.year, .month], from: Date())
    let referenceMonth =
      bill?.referenceMonth
      ?? ReferenceMonth(
        year: currentComponents.year ?? 2026,
        month: currentComponents.month ?? 1
      )
    _year = State(initialValue: referenceMonth.year)
    _month = State(initialValue: referenceMonth.month)
    _dueDate = State(
      initialValue: (bill?.dueDate ?? referenceMonth.defaultDueDate).resolvedDate()
    )
    // An existing bill's *stored* due date is authoritative and must never be recomputed from
    // the reference month. A bill with no stored date has nothing to protect, so it tracks the
    // competência like a new bill until the user touches the picker.
    _dueDateEdited = State(initialValue: bill?.dueDate != nil)
    // A new bill always starts with a due date; an existing one keeps whatever the server has.
    _hasDueDate = State(initialValue: bill.map { $0.dueDate != nil } ?? true)
    _notes = State(initialValue: bill?.notes ?? "")
    let initialLines =
      bill?.lineItems.map(EditableBillLine.init)
      ?? billing.items.map { item in
        EditableBillLine(seededFrom: item, kind: item.type == .fixed ? .fixed : .variable)
      }
    _lines = State(initialValue: initialLines)
    initialReferenceMonth = referenceMonth
    initialDueDate = bill?.dueDate ?? referenceMonth.defaultDueDate
    initialHasDueDate = bill.map { $0.dueDate != nil } ?? true
    initialNotes = bill?.notes ?? ""
    self.initialLines = initialLines.map(\.domain)
  }

  var body: some View {
    RentivoFormWizard(
      title: bill == nil ? "Gerar fatura" : "Editar fatura",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isBusy: saving,
      finalActionTitle: bill == nil ? "Gerar fatura" : "Salvar fatura",
      onValidateAndAdvance: validateAndAdvance,
      onCommit: { Task { await save() } }
    ) { step in
      switch step {
      case .competence:
        RentivoWizardSection("Competência") {
          RentivoFormField(label: "Mês") {
            Picker("", selection: $month) {
              ForEach(1...12, id: \.self) { Text(monthName($0)).tag($0) }
            }
            .labelsHidden()
            .accessibilityLabel("Mês")
            .accessibilityIdentifier("bill.form.month")
          }
          .onChange(of: month) { _, _ in syncDueDateWithReferenceMonth() }
          RentivoFormField(label: "Ano") {
            Stepper(value: $year, in: 2024...2035) {
              Text(BrazilianLocaleFormatting.year(year))
            }
            .accessibilityLabel("Ano")
            .accessibilityValue(BrazilianLocaleFormatting.year(year))
            .accessibilityIdentifier("bill.form.year")
          }
            .onChange(of: year) { _, _ in syncDueDateWithReferenceMonth() }
          if bill != nil {
            Text("A competência não pode ser alterada depois que a fatura é criada.")
              .font(.footnote)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }
        .disabled(bill != nil)
      case .dueDate:
        RentivoWizardSection(
          "Vencimento",
          subtitle: "A competência é o mês de referência. O vencimento pode cair em outro mês."
        ) {
          Toggle("Definir vencimento", isOn: $hasDueDate)
            .accessibilityIdentifier("bill.form.hasDueDate")
          if hasDueDate {
            RentivoFormField(label: "Data de vencimento") {
              DatePicker("", selection: dueDateBinding, displayedComponents: .date)
                .labelsHidden()
                .accessibilityLabel("Data de vencimento")
                .accessibilityIdentifier("bill.form.dueDate")
            }
          }
        }
      case .items:
        itemsStep
      case .notes:
        RentivoWizardSection("Observações", subtitle: "Opcional") {
          RentivoTextFormField(
            label: "Observações",
            text: $notes,
            prompt: "Mensagem opcional",
            axis: .vertical,
            accessibilityIdentifier: "bill.form.notes"
          )
            .lineLimit(3...6)
        }
      case .review:
        reviewStep
      }
    }
    .interactiveDismissDisabled(saving || isDirty)
    .onChange(of: draft) {
      if hasValidatedItems { issues = draft.validate() }
    }
  }

  private var descriptors: [RentivoWizardStepDescriptor<BillWizardStep>] {
    [
      RentivoWizardStepDescriptor(id: .competence, title: "Competência"),
      RentivoWizardStepDescriptor(id: .dueDate, title: "Vencimento"),
      RentivoWizardStepDescriptor(id: .items, title: "Itens"),
      RentivoWizardStepDescriptor(id: .notes, title: "Observações"),
      RentivoWizardStepDescriptor(id: .review, title: "Revisar fatura"),
    ]
  }

  private var itemsStep: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.section) {
      ForEach(BillLineItemKind.allCases, id: \.self) { kind in
        RentivoWizardSection(kind.sectionTitle) {
          ForEach(lineIndices(for: kind), id: \.self) { index in
            // Fixed and variable template rows are mandatory. Only ad-hoc extras are removable.
            lineRow(index, canRemove: kind == .extra)
          }
          if kind == .extra {
            // Extras are the only client-created lines. Variable lines preserve the billing item
            // ULID seeded above because `variable_amounts` is keyed by that server-issued ID.
            Button {
              lines.append(EditableBillLine(kind: kind))
            } label: {
              Label("Adicionar \(kind.actionLabel)", systemImage: "plus.circle.fill")
            }
            .focused($focusedField, equals: .addExtra)
            .accessibilityFocused($accessibilityFocusedField, equals: .addExtra)
          }
        }
      }
      if !aggregateIssues.isEmpty {
        validationIssues
      }
    }
  }

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.section) {
      RentivoWizardSection("Resumo") {
        RentivoWizardReviewRow(
          label: "Competência",
          value: ReferenceMonth(year: year, month: month).displayFormatted)
        RentivoWizardReviewRow(
          label: "Vencimento",
          value: hasDueDate ? DateOnly(from: dueDate).displayFormatted : "Não definido"
        )
        RentivoWizardReviewRow(
          label: "Itens", value: BrazilianLocaleFormatting.integer(lines.count))
        RentivoWizardReviewRow(label: "Total", value: total.formatted())
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          RentivoWizardReviewRow(label: "Observações", value: notes)
        }
      }
      if !aggregateIssues.isEmpty || submitFailure != nil {
        validationIssues
      }
    }
  }

  private var validationIssues: some View {
    RentivoWizardSection("Revise a fatura") {
      ForEach(aggregateIssues, id: \.self) { issue in
        Label(issue.message, systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(RentivoColors.coral)
      }
      if let submitFailure {
        UserFacingFailureView(failure: submitFailure) { openAuthenticatorSetup() }
          .accessibilityIdentifier("bill.form.error")
      }
    }
  }

  private var isDirty: Bool {
    ReferenceMonth(year: year, month: month) != initialReferenceMonth
      || hasDueDate != initialHasDueDate
      || (hasDueDate && DateOnly(from: dueDate) != initialDueDate)
      || notes != initialNotes
      || lines.map(\.domain) != initialLines
  }

  private func openAuthenticatorSetup() {
    dismiss()
    Task { @MainActor in app.navigateToAuthenticatorSetup() }
  }

  /// Writes through to `dueDate` while recording that the choice is now the user's. A plain
  /// `.onChange(of: dueDate)` can't do this — it would also fire for the programmatic writes in
  /// `syncDueDateWithReferenceMonth()` and immediately freeze the default.
  private var dueDateBinding: Binding<Date> {
    Binding(
      get: { dueDate },
      set: { newValue in
        dueDate = newValue
        dueDateEdited = true
      }
    )
  }

  private func syncDueDateWithReferenceMonth() {
    guard !dueDateEdited else { return }
    dueDate = ReferenceMonth(year: year, month: month).defaultDueDate.resolvedDate()
  }

  private var total: Money {
    lines.map { Money(centavos: $0.centavos) }.reduce(.zero, +)
  }

  @ViewBuilder
  private func lineRow(_ index: Int, canRemove: Bool) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      if bill == nil, lines[index].kind != .extra {
        LabeledContent("Descrição", value: lines[index].description)
      } else {
        RentivoTextFormField(
          label: "Descrição",
          text: $lines[index].description,
          errorMessage: lineDescriptionError(at: index),
          accessibilityIdentifier: "bill.form.line.\(lines[index].id.rawValue).description"
        )
          .focused($focusedField, equals: .lineDescription(lines[index].id))
          .accessibilityFocused($accessibilityFocusedField, equals: .lineDescription(lines[index].id))
      }
      if bill == nil, lines[index].kind == .fixed {
        LabeledContent("Valor", value: Money(centavos: lines[index].centavos).formatted())
      } else {
        RentivoCurrencyField(
          label: "Valor",
          amountInCents: $lines[index].centavos,
          errorMessage: lineAmountError(at: index),
          isFocused: amountFocusBinding(for: lines[index].id),
          isAccessibilityFocused: accessibilityAmountFocusBinding(for: lines[index].id),
          accessibilityIdentifier: "bill.form.line.\(lines[index].id.rawValue).amount"
        )
      }
      if canRemove {
        Button("Remover item", role: .destructive) {
          lines.remove(at: index)
        }
        .font(.footnote)
      }
    }
  }

  private func lineIndices(for kind: BillLineItemKind) -> [Int] {
    lines.indices.filter { lines[$0].kind == kind }
  }

  private func validateAndAdvance() -> Bool {
    submitFailure = nil
    guard selectedStep == .items else { return true }
    hasValidatedItems = true
    issues = draft.validate()
    focusFirstInvalidLine()
    return issues.isEmpty
  }

  /// Validation aggregates a row's problems into one message. Returning focus to that row's
  /// description gives keyboard users a deterministic first correction point, including extras
  /// that were just added to the invoice.
  private func focusFirstInvalidLine() {
    guard let target = billFormFocusTarget(issues: issues, lines: lines.map(\.domain)) else { return }
    scheduleFocus(target)
  }

  private var aggregateIssues: [ValidationIssue] {
    issues.filter { $0.field == .items }
  }

  private func lineDescriptionError(at index: Int) -> String? {
    guard lines.indices.contains(index),
      let issue = issues.first(where: { $0.field == .itemDescription })
    else { return nil }
    let firstInvalidIndex = lines.firstIndex { line in
      let value = line.description.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty || value.unicodeScalars.count > 255
    }
    return firstInvalidIndex == index ? issue.message : nil
  }

  private func lineAmountError(at index: Int) -> String? {
    guard lines.indices.contains(index),
      let issue = issues.first(where: { $0.field == .itemAmount }),
      billFormFocusTarget(issues: [issue], lines: lines.map(\.domain))
        == .lineAmount(lines[index].id)
    else { return nil }
    return issue.message
  }

  private func amountFocusBinding(for id: BillLineItemID) -> Binding<Bool> {
    Binding(
      get: { focusedField == .lineAmount(id) },
      set: { isFocused in
        if isFocused {
          focusedField = .lineAmount(id)
        } else if focusedField == .lineAmount(id) {
          focusedField = nil
        }
      }
    )
  }

  private func accessibilityAmountFocusBinding(for id: BillLineItemID) -> Binding<Bool> {
    Binding(
      get: { accessibilityFocusedField == .lineAmount(id) },
      set: { isFocused in
        if isFocused {
          accessibilityFocusedField = .lineAmount(id)
        } else if accessibilityFocusedField == .lineAmount(id) {
          accessibilityFocusedField = nil
        }
      }
    )
  }

  /// The Continue button becomes first responder for the validation action. Deferring the field
  /// assignment by one main-actor turn lets that button resign before SwiftUI restores focus.
  private func scheduleFocus(_ field: BillFormFocus) {
    Task { @MainActor in
      focusedField = field
      accessibilityFocusedField = field
    }
  }

  private var draft: BillDraft {
    BillDraft(
      billingID: billing.id,
      referenceMonth: ReferenceMonth(year: year, month: month),
      dueDate: hasDueDate ? DateOnly(from: dueDate) : nil,
      notes: notes,
      lineItems: lines.map(\.domain)
    )
  }

  private func save() async {
    // A disabled action is not a synchronization primitive: claim the in-flight state before
    // any suspension so queued commits cannot submit the same draft twice.
    guard !saving else { return }
    submitFailure = nil
    issues = draft.validate()
    guard issues.isEmpty else {
      hasValidatedItems = true
      selectedStep = .items
      Task { @MainActor in focusFirstInvalidLine() }
      return
    }
    saving = true
    defer { saving = false }
    do {
      if let bill {
        _ = try await app.dependencies.bills.updateBill(
          billingID: billing.id,
          billID: bill.id,
          draft: draft
        )
      } else {
        _ = try await app.dependencies.bills.createBill(draft)
      }
      await onSaved()
      app.showNotice(bill == nil ? "Fatura criada como rascunho." : "Fatura atualizada.")
      dismiss()
    } catch {
      submitFailure = UserFacingError.presentation(for: error, operation: .saveBill)
    }
  }

  private func monthName(_ month: Int) -> String {
    ReferenceMonth(year: year, month: month).standaloneMonthName
  }
}

struct BillDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  let billID: BillID
  let onMutation: () async -> Void
  let onDownloadedFile: (DownloadedFile) -> Void

  @State private var state: LoadState<Bill> = .idle
  @State private var billing: Billing?
  @State private var showingEdit = false
  @State private var communicationPresentation: CommunicationComposerPresentation?
  @State private var confirmingDelete = false
  @State private var pendingTransition: BillLifecyclePresentedAction?
  @State private var transitioningAction: BillLifecyclePresentedAction?
  @State private var isRegenerating = false
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
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if state.value?.status == .draft && state.value?.capabilities.canEdit == true {
        Button("Editar") { showingEdit = true }
      }
    }
    .fullScreenCover(isPresented: $showingEdit) {
      if let billing, let bill = state.value {
        BillFormView(billing: billing, bill: bill) {
          await refreshAll()
        }
      }
    }
    .fullScreenCover(item: $communicationPresentation) { presentation in
      CommunicationComposerView(presentation: presentation) {
        await refreshQuietly()
        await onMutation()
      }
    }
    .confirmationDialog(
      "Excluir esta fatura?",
      isPresented: $confirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Excluir fatura", role: .destructive) { Task { await deleteBill() } }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text(
        "A fatura e seus comprovantes serão removidos permanentemente. Esta ação não pode ser desfeita."
      )
    }
    .confirmationDialog(
      pendingTransition?.confirmationTitle ?? "Alterar status da fatura?",
      isPresented: Binding(
        get: { pendingTransition != nil },
        set: { if !$0 { pendingTransition = nil } }
      ),
      titleVisibility: .visible,
      presenting: pendingTransition
    ) { action in
      Button(action.action.label, role: action.isDestructive ? .destructive : nil) {
        pendingTransition = nil
        guard let currentStatus = state.value?.status else { return }
        Task { await transition(from: currentStatus, action: action) }
      }
      .accessibilityIdentifier("bill.transition.confirm.\(action.action.target.rawValue)")
      Button("Cancelar", role: .cancel) {}
    } message: { action in
      if let message = action.confirmationMessage { Text(message) }
    }
    .task(id: app.dataRevision) { await load() }
    .task(id: pollKey) { await pollWhileRendering() }
    .noticeArea(.billOperations)
  }

  private func content(_ bill: Bill) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: RentivoSpacing.section) {
        RentivoCard {
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            HStack {
              VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                Text(billing?.name ?? "Cobrança")
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(RentivoColors.secondaryInk)
                Text(bill.referenceMonth.standaloneDisplayFormatted)
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

        lineItems(bill)
        lifecycle(bill)

        VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
          SectionTitle(title: "Documento", symbol: "doc.richtext.fill")
          renderStatus(bill)
          Button {
            Task { await downloadInvoice(bill) }
          } label: {
            Label("Abrir fatura em PDF", systemImage: "doc.text.magnifyingglass")
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(bill.isRenderingPDF || !bill.capabilities.canDownloadInvoice)
          HStack {
            // Regenerating stays available while a render is pending: a re-trigger supersedes the
            // in-flight render server-side.
            Button("Regenerar documento") { Task { await regenerate(bill) } }
              .disabled(!bill.capabilities.canRegenerate || isRegenerating)
            if bill.capabilities.canOpenRecibo {
              Button("Abrir recibo") { Task { await downloadRecibo(bill) } }
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

        ReceiptManagerView(
          billingID: billingID,
          billingName: billing?.name ?? "Cobrança",
          bill: bill,
          capabilities: bill.capabilities,
          onDownloadedFile: onDownloadedFile
        ) { await refreshAll() }

        communicationHistory(bill)

        if bill.capabilities.canCompose {
          let canOpenCommunication =
            !CommunicationComposerRules.availableTypes(for: bill).isEmpty
          Button {
            guard let billing else { return }
            let presentation = CommunicationComposerPresentation(billing: billing, bill: bill)
            guard !presentation.availableTypes.isEmpty else { return }
            communicationPresentation = presentation
          } label: {
            Label("Enviar comunicação", systemImage: "paperplane.fill")
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(!canOpenCommunication)
          .help(
            canOpenCommunication
              ? "Enviar comunicação"
              : "Esta fatura ainda não está pronta para envio."
          )
          if !canOpenCommunication {
            Text("Esta fatura ainda não está pronta para envio.")
              .font(.footnote)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
        }

        if bill.capabilities.canDelete {
          Button(role: .destructive) {
            confirmingDelete = true
          } label: {
            Label("Excluir fatura", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(RentivoDestructiveButtonStyle())
          .accessibilityIdentifier("bill.delete")
        }
      }
      .padding(RentivoSpacing.page)
    }
    .rentivoTabContent()
  }

  @ViewBuilder
  private func renderStatus(_ bill: Bill) -> some View {
    switch bill.pdfRenderStatus {
    case .pending:
      HStack(spacing: RentivoSpacing.small) {
        Label("Renderizando…", systemImage: "clock.arrow.circlepath")
        ProgressView()
      }
      .font(.footnote)
      .foregroundStyle(RentivoColors.amber)
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
      SectionTitle(title: "Composição", symbol: "list.bullet")
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
    BillLifecycleView(
      currentStatus: bill.status,
      // Preserve the server-authoritative action set exposed by the domain model.
      actions: bill.effectiveTransitionActions,
      statusUpdatedAt: bill.statusUpdatedAt,
      transitioningAction: transitioningAction,
      allowsActions: bill.capabilities.canTransition
    ) { action in
      if action.requiresConfirmation {
        pendingTransition = action
      } else {
        Task { await transition(from: bill.status, action: action) }
      }
    }
  }

  private func communicationHistory(_ bill: Bill) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Comunicações", symbol: "envelope.badge")
      if bill.communications.isEmpty {
        Text("Nenhuma comunicação enviada.")
          .font(.footnote)
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        RentivoCard {
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            ForEach(Array(bill.communications.enumerated()), id: \.element.id) { index, item in
              if index > 0 { Divider() }
              VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                HStack {
                  Text(item.createdAt?.formattedPTBR(time: .shortened) ?? "Data indisponível")
                    .font(.caption.monospacedDigit())
                  Spacer()
                  Text(item.deliveryLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status == "failed" ? RentivoColors.coral : RentivoColors.secondaryInk)
                }
                if item.isRedacted {
                  Text("Dados do destinatário protegidos")
                    .font(.subheadline.weight(.semibold))
                } else {
                  Text([item.recipientName, item.recipientEmail].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                  if let subject = item.subject { Text(subject).font(.footnote) }
                }
              }
            }
          }
        }
      }
    }
  }

  private func load() async {
    let hadVisibleState: Bool = switch state {
    case .loaded, .empty: true
    default: false
    }
    if !hadVisibleState { state = .loading }
    do {
      billing = try await app.dependencies.billings.billing(id: billingID)
      state = .loaded(try await app.dependencies.bills.bill(billingID: billingID, id: billID))
    } catch {
      if hadVisibleState {
        app.showNotice(UserFacingError.message(for: error, operation: .loadBill), kind: .warning)
      } else {
        state = .failed(UserFacingError.presentation(for: error, operation: .loadBill).demoError)
      }
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

  private func transition(
    from currentStatus: BillStatus,
    action: BillLifecyclePresentedAction
  ) async {
    guard transitioningAction == nil else { return }
    transitioningAction = action
    defer { transitioningAction = nil }
    let status = action.action.target
    do {
      try await app.dependencies.bills.transitionBill(
        billingID: billingID, billID: billID, from: currentStatus, to: status)
      await refreshAll()
      app.showNotice("Fatura marcada como \(status.label.lowercased()).")
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .changeBillStatus), kind: .warning)
    }
  }

  private func deleteBill() async {
    do {
      try await app.dependencies.bills.deleteBill(billingID: billingID, billID: billID)
      await onMutation()
      dismiss()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .deleteBill), kind: .warning)
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
      await onMutation()
      app.showNotice("Novo documento solicitado. Ele aparecerá aqui quando estiver pronto.")
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .regenerateDocument), kind: .warning)
    }
  }

  private func downloadInvoice(_ bill: Bill) async {
    let presentation = DocumentPresentation.invoice(
      billingName: billing?.name ?? "Cobrança", referenceMonth: bill.referenceMonth)
    do {
      onDownloadedFile(
        try await app.dependencies.downloads.downloadInvoice(
          billingID: billingID, billID: billID, presentation: presentation)
      )
    }
    catch {
      app.showNotice(UserFacingError.message(for: error, operation: .openDocument), kind: .warning)
    }
  }

  private func downloadRecibo(_ bill: Bill) async {
    let presentation = DocumentPresentation.generatedReceipt(
      billingName: billing?.name ?? "Cobrança", referenceMonth: bill.referenceMonth)
    do {
      onDownloadedFile(
        try await app.dependencies.downloads.downloadRecibo(
          billingID: billingID, billID: billID, presentation: presentation)
      )
    }
    catch {
      app.showNotice(UserFacingError.message(for: error, operation: .openDocument), kind: .warning)
    }
  }
}

private struct ReceiptManagerView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  let billingName: String
  let bill: Bill
  let capabilities: BillCapabilities
  let onDownloadedFile: (DownloadedFile) -> Void
  let onMutation: () async -> Void
  @State private var showingSourceChooser = false
  @State private var showingFileImporter = false
  @State private var showingCamera = false
  @State private var showingPhotosPicker = false
  @State private var photoSelection: PhotosPickerItem?
  @State private var pendingDeletion: Receipt?
  @State private var isMutating = false

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      HStack {
        SectionTitle(title: "Comprovantes", symbol: "paperclip")
        if !bill.receipts.isEmpty {
          Spacer()
          Text(ptBRCount(bill.receipts.count, singular: "comprovante", plural: "comprovantes"))
            .font(.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      if bill.receipts.isEmpty {
        Text("Nenhum comprovante anexado.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        RentivoCard {
          VStack(spacing: RentivoSpacing.medium) {
            ForEach(bill.receipts) { receipt in
              let presentation = DocumentPresentation.uploadedReceipt(
                filename: receipt.name,
                billingName: billingName,
                referenceMonth: bill.referenceMonth,
                mediaType: receipt.mediaType
              )
              HStack {
                VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                  Label(
                    presentation.displayName,
                    systemImage: DocumentPresentation.symbolName(
                      mediaType: receipt.mediaType, filename: receipt.name)
                  )
                    .font(.subheadline)
                  Text(
                    DocumentPresentation.metadataLine(
                      byteCount: receipt.byteCount, createdAt: receipt.createdAt)
                  )
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
                }
                Spacer()
                Menu {
                  Button("Abrir") { Task { await download(receipt) } }
                  if capabilities.canDeleteReceipts {
                    Button("Excluir", role: .destructive) { pendingDeletion = receipt }
                      .disabled(isMutating)
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Mais opções para \(presentation.displayName)")
              }
            }
            // Drag-to-reorder (`.onMove`) would need these rows hosted in a `List`, but this
            // section renders inside a `RentivoCard`/`VStack` (the surrounding screen is a
            // `ScrollView`, not a `List`), so `.onMove` has no effect here. Kept as an explicit
            // action instead of restructuring the whole detail screen's layout around a `List`.
            if bill.receipts.count > 1 && capabilities.canReorderReceipts {
              Button("Inverter ordem") { Task { await reverse() } }
                .buttonStyle(.bordered)
                .disabled(isMutating)
            }
          }
        }
      }
      if capabilities.canUploadReceipts {
        Button {
          showingSourceChooser = true
        } label: {
          Label("Adicionar comprovante", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(isMutating)
      }
    }
    .confirmationDialog(
      "Adicionar comprovante",
      isPresented: $showingSourceChooser,
      titleVisibility: .visible
    ) {
      ForEach(ReceiptSource.available) { source in
        Button(source.label) { present(source) }
      }
      Button("Cancelar", role: .cancel) {}
    }
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: [UTType.pdf, UTType.image],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await add(fileURL: url) }
    }
    .fullScreenCover(isPresented: $showingCamera) {
      ReceiptCameraPicker(
        onCapture: { image in
          showingCamera = false
          Task { await add(capturedPhoto: image) }
        },
        onCancel: { showingCamera = false },
        onFailure: {
          showingCamera = false
          app.showNotice(
            "Não foi possível usar a foto. Tire outra foto ou escolha um arquivo.",
            kind: .warning
          )
        }
      )
      .ignoresSafeArea()
    }
    // `.compatible` asks the picker to transcode HEIC assets to JPEG; the upload path clamps the
    // format anyway, since the picker only transcodes when it can.
    .photosPicker(
      isPresented: $showingPhotosPicker,
      selection: $photoSelection,
      matching: .images,
      preferredItemEncoding: .compatible
    )
    .onChange(of: photoSelection) { _, selection in
      guard let selection else { return }
      Task { await add(photoItem: selection) }
    }
    .confirmationDialog(
      "Excluir este comprovante?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { isPresented in if !isPresented { pendingDeletion = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Excluir comprovante", role: .destructive) {
        if let receipt = pendingDeletion { Task { await remove(receipt) } }
      }
      Button("Cancelar", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("O comprovante será removido permanentemente desta fatura.")
    }
  }

  private func present(_ source: ReceiptSource) {
    switch source {
    case .files: showingFileImporter = true
    case .camera: showingCamera = true
    case .photos: showingPhotosPicker = true
    }
  }

  private func add(fileURL: URL) async {
    do {
      guard
        let upload = try await FileUpload.fromSecurityScoped(
          url: fileURL, policy: .rentivoDocument
        )
          .clampedToAcceptedReceiptFormat()
      else {
        app.showNotice(
          "Não foi possível abrir o arquivo. Escolha outro e tente novamente.", kind: .warning)
        return
      }
      await send(upload)
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .addReceipt), kind: .warning)
    }
  }

  private func add(capturedPhoto image: UIImage) async {
    guard let upload = FileUpload.capturedPhoto(image) else {
      app.showNotice(
        "Não foi possível preparar a foto. Tire outra foto ou escolha um arquivo.",
        kind: .warning
      )
      return
    }
    await send(upload)
  }

  private func add(photoItem: PhotosPickerItem) async {
    photoSelection = nil
    do {
      guard let upload = try await photoItem.receiptUpload() else {
        app.showNotice("Não foi possível abrir a foto. Escolha outra e tente novamente.", kind: .warning)
        return
      }
      await send(upload)
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .addReceipt), kind: .warning)
    }
  }

  private func send(_ upload: FileUpload) async {
    guard !isMutating else { return }
    guard upload.byteCount > 0 else {
      app.showNotice("O arquivo está vazio. Escolha outro e tente novamente.", kind: .warning)
      return
    }
    guard !ReceiptUploadLimit.exceedsLimit(byteCount: upload.byteCount) else {
      app.showNotice(
        "O comprovante é maior que \(ReceiptUploadLimit.label). Escolha um arquivo menor e tente novamente.",
        kind: .warning)
      return
    }
    isMutating = true
    defer { isMutating = false }
    do {
      _ = try await app.dependencies.bills.addReceipt(
        billingID: billingID,
        billID: bill.id,
        upload: upload
      )
      await onMutation()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .addReceipt), kind: .warning)
    }
  }

  private func remove(_ receipt: Receipt) async {
    guard !isMutating else { return }
    isMutating = true
    defer { isMutating = false }
    do {
      try await app.dependencies.bills.deleteReceipt(
        billingID: billingID,
        billID: bill.id,
        receiptID: receipt.id
      )
      await onMutation()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .deleteReceipt), kind: .warning)
    }
  }

  private func reverse() async {
    guard !isMutating else { return }
    isMutating = true
    defer { isMutating = false }
    do {
      try await app.dependencies.bills.reorderReceipts(
        billingID: billingID, billID: bill.id, receiptIDs: Array(bill.receipts.map(\.id).reversed())
      )
      await onMutation()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .reorderReceipts), kind: .warning)
    }
  }

  private func download(_ receipt: Receipt) async {
    do {
      onDownloadedFile(
        try await app.dependencies.downloads.downloadReceipt(
          billingID: billingID,
          billID: bill.id,
          receiptID: receipt.id,
          presentation: DocumentPresentation.uploadedReceipt(
            filename: receipt.name,
            billingName: billingName,
            referenceMonth: bill.referenceMonth,
            mediaType: receipt.mediaType
          )
        )
      )
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .openDocument), kind: .warning)
    }
  }

}

extension BillLineItemKind {
  fileprivate var sectionTitle: String {
    switch self {
    case .fixed: "Itens fixos"
    case .variable: "Itens variáveis"
    case .extra: "Itens extras"
    }
  }

  fileprivate var actionLabel: String {
    switch self {
    case .fixed: "item fixo"
    case .variable: "valor variável"
    case .extra: "item extra"
    }
  }
}
