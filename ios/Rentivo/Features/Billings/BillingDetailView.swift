import SwiftUI

private struct BillingDetailData: Sendable {
  let billing: Billing
  let bills: [Bill]
  let expenses: [Expense]
}

struct FinancialAmountPresentation: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case received
    case expense
    case result
  }

  let tone: RentivoSemanticTone

  init(kind: Kind, amount: Money) {
    tone = switch (kind, amount.centavos) {
    case (.received, 1...): .positive
    case (.expense, 1...): .negative
    case (.result, ..<0): .negative
    case (.result, 1...): .positive
    default: .neutral
    }
  }
}

struct BillingDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let billingID: BillingID
  let onMutation: () async -> Void

  @State private var state: LoadState<BillingDetailData> = .idle
  @State private var showingEdit = false
  @State private var editStartsAtPIX = false
  @State private var showingCreateBill = false
  @State private var showingTheme = false
  @State private var confirmingDelete = false
  @State private var downloadedFile: DownloadedFile?

  var body: some View {
    PageStateView(state: state) { data in
      detail(data)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Detalhes")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if state.value?.billing.capabilities.canEdit == true {
          Button("Editar") {
            editStartsAtPIX = false
            showingEdit = true
          }
            .accessibilityIdentifier("billing.edit")
        }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingEdit) {
      if let billing = state.value?.billing {
        BillingFormView(
          billing: billing,
          initialStep: editStartsAtPIX ? .pix : .essentials
        ) {
          await load()
          await onMutation()
        }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingCreateBill) {
      if let billing = state.value?.billing {
        BillFormView(billing: billing) {
          await load()
          await onMutation()
        }
      }
    }
    .rentivoFullScreenWizard(isPresented: $showingTheme) {
      ThemeEditorView(target: .billing(billingID))
    }
    // Keep the sheet on the pop target: iOS 26 UIKit can livelock the main thread when a modal
    // owned by a pushed screen is dismissed immediately before that screen is popped.
    .downloadedFileSheet($downloadedFile)
    .confirmationDialog(
      "Excluir esta cobrança?",
      isPresented: $confirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Excluir cobrança", role: .destructive) {
        Task { await deleteBilling() }
      }
      Button("Cancelar", role: .cancel) {}
    } message: {
      Text(
        "Faturas, despesas e arquivos desta cobrança também serão removidos. Esta ação não pode ser desfeita."
      )
    }
    .task(id: app.dataRevision) { await load() }
    .noticeArea(.billingDetail)
  }

  private func detail(_ data: BillingDetailData) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: RentivoSpacing.section) {
        RentivoCard {
          VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
            Text(data.billing.name)
              .font(RentivoTypography.title)
            Text(data.billing.description)
              .foregroundStyle(RentivoColors.secondaryInk)
            Label(data.billing.owner.name, systemImage: "person.crop.square")
              .font(.subheadline.weight(.semibold))
            HStack {
              Label(
                data.billing.pixNeedsSetup
                  ? "PIX pendente"
                  : (data.billing.pixOverride?.isComplete == true ? "PIX próprio" : "PIX herdado"),
                systemImage: "qrcode"
              )
              Spacer()
              MoneyText(money: data.billing.fixedSubtotal)
            }
          }
        }

        lineItems(data.billing.items)
        bills(data)
        financialSummary(data)
        BillingOperationsLinks(
          billingID: billingID,
          capabilities: data.billing.capabilities,
          onDownloadedFile: { downloadedFile = $0 }
        ) {
          await load()
          await onMutation()
        }
        recipients(data.billing)

        if data.billing.capabilities.canReadTheme {
          Button {
            showingTheme = true
          } label: {
            Label("Aparência dos documentos", systemImage: "paintpalette.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(RentivoSecondaryButtonStyle())
          .accessibilityIdentifier("billing.theme")
        }

        if data.billing.capabilities.canDelete {
          Button(role: .destructive) {
            confirmingDelete = true
          } label: {
            Label("Excluir cobrança", systemImage: "trash")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(RentivoDestructiveButtonStyle())
          .accessibilityIdentifier("billing.delete")
        } else {
          Label(
            "Seu perfil pode consultar, mas não alterar esta cobrança.",
            systemImage: "eye.fill"
          )
          .font(.footnote.weight(.semibold))
          .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      .padding(RentivoSpacing.page)
    }
    .rentivoTabContent()
  }

  private func lineItems(_ items: [BillingItem]) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Itens recorrentes", symbol: "list.bullet.rectangle")
      RentivoCard {
        VStack(spacing: RentivoSpacing.medium) {
          ForEach(items) { item in
            HStack {
              VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                Text(item.description)
                  .font(.subheadline.weight(.semibold))
                Text(item.type.label)
                  .font(.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
              Spacer()
              MoneyText(money: item.amount)
            }
            if item.id != items.last?.id { Divider() }
          }
        }
      }
    }
  }

  private func bills(_ data: BillingDetailData) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      if data.billing.pixNeedsSetup && data.billing.capabilities.canCreateBills {
        Label(
          "Configure a chave, o nome e a cidade do recebedor antes de gerar uma fatura.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(RentivoColors.coral)
      }
      HStack {
        SectionTitle(title: "Faturas", symbol: "doc.text.fill")
        Spacer()
        if data.billing.capabilities.canCreateBills {
          Button {
            performBillEmptyAction(for: data.billing)
          } label: {
            Image(systemName: "plus.circle.fill")
          }
          .accessibilityLabel(data.billing.pixNeedsSetup ? "Configurar PIX" : "Gerar fatura")
          .accessibilityIdentifier("bill.create")
          .help(data.billing.pixNeedsSetup ? "Configurar PIX" : "Gerar fatura")
        }
      }
      if data.bills.isEmpty {
        InlineEmptyStateView(
          configuration: billEmptyState(for: data.billing),
          action: data.billing.capabilities.canCreateBills
            ? { performBillEmptyAction(for: data.billing) }
            : nil
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, RentivoSpacing.small)
      } else {
        ForEach(data.bills) { bill in
          NavigationLink {
            BillDetailView(
              billingID: billingID,
              billID: bill.id,
              onMutation: {
                await load()
                await onMutation()
              },
              onDownloadedFile: { downloadedFile = $0 }
            )
          } label: {
            RentivoCard {
              HStack {
                VStack(alignment: .leading, spacing: RentivoSpacing.small) {
                  Text(bill.referenceMonth.standaloneDisplayFormatted)
                    .font(.headline)
                  StatusBadge(status: bill.status)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: RentivoSpacing.small) {
                  MoneyText(money: bill.effectiveTotal)
                  if let dueDate = bill.dueDate {
                    Text("Vence \(dueDate.displayFormatted)")
                      .font(.caption)
                      .foregroundStyle(RentivoColors.secondaryInk)
                  }
                }
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("bill.card.\(bill.id.rawValue)")
        }
      }
    }
  }

  private func billEmptyState(for billing: Billing) -> EmptyStateConfiguration {
    if !billing.capabilities.canCreateBills {
      return EmptyStateConfiguration(
        title: "Nenhuma fatura gerada",
        message: "Ainda não há faturas nesta cobrança.",
        systemImage: "doc.text"
      )
    }
    if billing.pixNeedsSetup {
      return EmptyStateConfiguration(
        title: "Nenhuma fatura gerada",
        message: "Configure os dados do PIX antes de gerar a primeira fatura.",
        systemImage: "doc.text",
        actionTitle: "Configurar PIX"
      )
    }
    return EmptyStateConfiguration(
      title: "Nenhuma fatura gerada",
      message: "Gere a primeira fatura desta cobrança.",
      systemImage: "doc.text",
      actionTitle: "Gerar fatura"
    )
  }

  private func performBillEmptyAction(for billing: Billing) {
    if billing.pixNeedsSetup {
      editStartsAtPIX = true
      showingEdit = true
    } else {
      showingCreateBill = true
    }
  }

  private func financialSummary(_ data: BillingDetailData) -> some View {
    let paid = data.bills.filter { $0.status == .paid }.map(\.effectiveTotal).reduce(.zero, +)
    let expenses = data.expenses.map(\.amount).reduce(.zero, +)
    return VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Resumo financeiro", symbol: "chart.bar.fill")
      RentivoCard {
        VStack(spacing: RentivoSpacing.medium) {
          valueRow("Recebido", paid, kind: .received)
          Divider()
          valueRow("Despesas", expenses, kind: .expense)
          Divider()
          valueRow("Resultado", paid - expenses, kind: .result)
        }
      }
    }
  }

  private func valueRow(
    _ label: String, _ money: Money, kind: FinancialAmountPresentation.Kind
  ) -> some View {
    let presentation = FinancialAmountPresentation(kind: kind, amount: money)
    return Group {
      if dynamicTypeSize.isAccessibilitySize {
        verticalValueRow(label, money: money, presentation: presentation)
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: RentivoSpacing.small) {
            Text(label)
              .font(.subheadline.weight(.semibold))
              .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: RentivoSpacing.small)
            MoneyText(money: money, color: presentation.tone.color)
              .fixedSize(horizontal: true, vertical: false)
          }
          verticalValueRow(label, money: money, presentation: presentation)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label): \(money.formatted())")
  }

  private func verticalValueRow(
    _ label: String,
    money: Money,
    presentation: FinancialAmountPresentation
  ) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
      Text(label).font(.subheadline.weight(.semibold))
      MoneyText(
        money: money,
        color: presentation.tone.color,
        minimumScaleFactor: 0.5,
        lineLimit: 1
      )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  private func recipients(_ billing: Billing) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Destinatários", symbol: "envelope.fill")
      RentivoCard {
        VStack(alignment: .leading, spacing: RentivoSpacing.small) {
          ForEach(billing.recipients) { recipient in
            Text(recipient.name).font(.subheadline.weight(.semibold))
            Text(recipient.email)
              .font(.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          ForEach(billing.replyTo) { contact in
            Divider()
            Label(
              "Respostas para \(contact.name) <\(contact.email)>",
              systemImage: "arrowshape.turn.up.left"
            )
              .font(.caption)
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
      let data = BillingDetailData(
        billing: try await app.dependencies.billings.billing(id: billingID),
        bills: try await app.dependencies.bills.listBills(billingID: billingID),
        expenses: try await app.dependencies.expenses.listExpenses(billingID: billingID)
      )
      state = .loaded(data)
    } catch {
      if hadVisibleState {
        app.showNotice(UserFacingError.message(for: error, operation: .loadBilling), kind: .warning)
      } else {
        state = .failed(UserFacingError.presentation(for: error, operation: .loadBilling).demoError)
      }
    }
  }

  private func deleteBilling() async {
    do {
      try await app.dependencies.billings.deleteBilling(id: billingID)
      await onMutation()
      app.showNotice("Cobrança excluída.", owner: .billings)
      dismiss()
    } catch {
      app.showNotice(UserFacingError.message(for: error, operation: .deleteBilling), kind: .warning)
    }
  }
}
