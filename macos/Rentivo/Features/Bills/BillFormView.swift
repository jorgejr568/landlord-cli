import RentivoCore
import SwiftUI

struct EditableBillLine: Identifiable {
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

/// The PT-BR month names the competência picker offers, derived from the same `ReferenceMonth`
/// labels the rest of the app displays.
enum BillReferenceMonthNames {
  static func label(year: Int, month: Int) -> String {
    ReferenceMonth(year: year, month: month).label.components(separatedBy: " de ").first?
      .capitalized
      ?? "Mês"
  }
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
  @State private var saving = false

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
  }

  var body: some View {
    Form {
      Section("Competência") {
        Picker("Mês", selection: $month) {
          ForEach(1...12, id: \.self) { Text(BillReferenceMonthNames.label(year: year, month: $0)).tag($0) }
        }
        .onChange(of: month) { _, _ in syncDueDateWithReferenceMonth() }
        Stepper("Ano: \(year)", value: $year, in: 2024...2035)
          .onChange(of: year) { _, _ in syncDueDateWithReferenceMonth() }
      }

      Section("Vencimento") {
        Toggle("Definir vencimento", isOn: $hasDueDate)
          .accessibilityIdentifier("bill.form.hasDueDate")
        if hasDueDate {
          DatePicker("Data de vencimento", selection: dueDateBinding, displayedComponents: .date)
            .accessibilityIdentifier("bill.form.dueDate")
          Text("A competência é o mês de referência da fatura. O vencimento pode cair em outro mês.")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }

      ForEach(BillLineItemKind.allCases, id: \.self) { kind in
        Section(kind.sectionTitle) {
          // Fixed lines mirror the billing's own recurring items and aren't deletable here; only
          // user-added variable/extra lines can be removed.
          ForEach(lineIndices(for: kind), id: \.self) { index in
            lineRow(index, deletable: kind != .fixed)
          }
          if kind == .extra {
            // Only extras get an "add new line" affordance here: extras are the server's
            // mechanism for ad-hoc per-bill lines. Variable items are defined by the billing
            // (cobrança) itself, seeded above from `billing.items`; the live store's
            // `variable_amounts` only accepts the billing's own ULID-keyed variable items, so a
            // client-minted UUID for a brand-new variable line would silently be dropped on
            // save. Previously seeded variable lines still render and remain editable via
            // `lineRow` and removable through its trash button.
            Button {
              lines.append(EditableBillLine(kind: kind))
            } label: {
              Label("Adicionar \(kind.actionLabel)", systemImage: "plus.circle.fill")
            }
          }
        }
      }

      Section("Observações") {
        TextField("Mensagem opcional", text: $notes, axis: .vertical)
          .lineLimit(3...6)
      }

      Section("Total") {
        MoneyText(money: total)
      }

      if !issues.isEmpty {
        Section("Revise a fatura") {
          ForEach(issues, id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
          }
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(bill == nil ? "Gerar fatura" : "Editar fatura")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Salvar") { Task { await save() } }
          .disabled(saving)
          .accessibilityIdentifier("bill.form.save")
      }
    }
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
  private func lineRow(_ index: Int, deletable: Bool) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      HStack(spacing: RentivoSpacing.small) {
        TextField("Descrição", text: $lines[index].description)
        // Swipe-to-delete has no macOS equivalent, so removable lines carry their own button.
        if deletable {
          Button(role: .destructive) {
            let id = lines[index].id
            lines.removeAll { $0.id == id }
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .foregroundStyle(RentivoColors.secondaryInk)
          .accessibilityLabel("Remover item")
        }
      }
      CurrencyCentavosField("Valor em centavos", centavos: $lines[index].centavos)
    }
  }

  private func lineIndices(for kind: BillLineItemKind) -> [Int] {
    lines.indices.filter { lines[$0].kind == kind }
  }

  private func save() async {
    let draft = BillDraft(
      billingID: billing.id,
      referenceMonth: ReferenceMonth(year: year, month: month),
      dueDate: hasDueDate ? DateOnly(from: dueDate) : nil,
      notes: notes,
      lineItems: lines.map(\.domain)
    )
    issues = draft.validate()
    guard issues.isEmpty else { return }
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
      app.reportFailure(error)
    }
  }
}

extension BillLineItemKind {
  var sectionTitle: String {
    switch self {
    case .fixed: "Itens fixos"
    case .variable: "Itens variáveis"
    case .extra: "Itens extras"
    }
  }

  var actionLabel: String {
    switch self {
    case .fixed: "item fixo"
    case .variable: "valor variável"
    case .extra: "item extra"
    }
  }
}
