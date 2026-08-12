import RentivoCore
import SwiftUI

private struct BillingDetailData: Sendable {
  let billing: Billing
  let bills: [Bill]
  let expenses: [Expense]
}

struct BillingDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billingID: BillingID
  let onMutation: () async -> Void

  @State private var state: LoadState<BillingDetailData> = .idle
  @State private var showingEdit = false
  @State private var showingCreateBill = false
  @State private var confirmingDelete = false

  var body: some View {
    PageStateView(state: state) { data in
      detail(data)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Detalhes")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if state.value?.billing.capabilities.canEdit == true {
          Button("Editar") { showingEdit = true }
            .accessibilityIdentifier("billing.edit")
        }
      }
    }
    .sheet(isPresented: $showingEdit) {
      if let billing = state.value?.billing {
        NavigationStack {
          BillingFormView(billing: billing) {
            await load()
            await onMutation()
          }
        }
        .rentivoSheetFrame()
      }
    }
    .sheet(isPresented: $showingCreateBill) {
      if let billing = state.value?.billing {
        NavigationStack {
          BillFormView(billing: billing) {
            await load()
            await onMutation()
          }
        }
        .rentivoSheetFrame()
      }
    }
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
      Text("Faturas, despesas e arquivos desta cobrança também serão removidos.")
    }
    .navigationDestination(for: BillID.self) { billID in
      BillDetailView(billingID: billingID, billID: billID) {
        await load()
        await onMutation()
      }
    }
    .task(id: app.dataRevision) { await load() }
  }

  private func detail(_ data: BillingDetailData) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        // A wide window puts the cobrança's own record — identity, recurring items, money,
        // operations, recipients — next to the faturas it produced, rather than making the user
        // scroll past all of it to reach the list they came for.
        BillingAdaptiveColumns {
          summaryCard(data.billing)
          lineItems(data.billing.items)
          financialSummary(data)
          BillingOperationsLinks(
            billingID: billingID,
            capabilities: data.billing.capabilities
          ) {
            await load()
            await onMutation()
          }
          recipients(data.billing)
        } trailing: {
          bills(data)
        }

        footerActions(data.billing)
      }
      .padding(RentivoSpacing.page)
    }
  }

  private func summaryCard(_ billing: Billing) -> some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        Text(billing.name)
          .font(RentivoTypography.title)
        Text(billing.description)
          .foregroundStyle(RentivoColors.secondaryInk)
        Label(billing.owner.name, systemImage: "person.crop.square")
          .font(.subheadline.weight(.semibold))
        HStack {
          Label(
            billing.pixOverride?.isComplete == true ? "PIX próprio" : "PIX herdado",
            systemImage: "qrcode"
          )
          Spacer()
          MoneyText(money: billing.fixedSubtotal)
        }
      }
    }
  }

  @ViewBuilder
  private func footerActions(_ billing: Billing) -> some View {
    if billing.capabilities.canReadTheme {
      // The Conta section owns `ThemeEditorView`, so this pushes the target as a value and the
      // Conta port registers the matching `navigationDestination`.
      NavigationLink(value: ThemeTarget.billing(billingID)) {
        Label("Aparência dos documentos", systemImage: "paintpalette.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
      .accessibilityIdentifier("billing.theme")
    }

    if billing.capabilities.canDelete {
      Button(role: .destructive) {
        confirmingDelete = true
      } label: {
        Label("Excluir cobrança", systemImage: "trash")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
    } else {
      Label(
        "Seu perfil pode consultar, mas não alterar esta cobrança.",
        systemImage: "eye.fill"
      )
      .font(.footnote.weight(.semibold))
      .foregroundStyle(RentivoColors.secondaryInk)
    }
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
      HStack {
        SectionTitle(title: "Faturas", symbol: "doc.text.fill")
        Spacer()
        if data.billing.capabilities.canCreateBills {
          Button {
            showingCreateBill = true
          } label: {
            Image(systemName: "plus.circle.fill")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Gerar fatura")
          .accessibilityIdentifier("bill.create")
        }
      }
      if data.bills.isEmpty {
        Text("Nenhuma fatura foi gerada para esta cobrança.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(data.bills) { bill in
          NavigationLink(value: bill.id) {
            RentivoCard {
              HStack {
                VStack(alignment: .leading, spacing: RentivoSpacing.small) {
                  Text(bill.referenceMonth.displayFormatted.capitalized)
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
          .rentivoHoverLift(elevated: true)
          .transition(BillingsMotion.row)
          .accessibilityIdentifier("bill.card.\(bill.id.rawValue)")
        }
      }
    }
  }

  private func financialSummary(_ data: BillingDetailData) -> some View {
    let paid = data.bills.filter { $0.status == .paid }.map(\.effectiveTotal).reduce(.zero, +)
    let expenses = data.expenses.map(\.amount).reduce(.zero, +)
    return VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Resumo financeiro", symbol: "chart.bar.fill")
      RentivoCard {
        VStack(spacing: RentivoSpacing.medium) {
          valueRow("Recebido", paid, RentivoColors.emerald)
          Divider()
          valueRow("Despesas", expenses, RentivoColors.coral)
          Divider()
          valueRow("Resultado", paid - expenses, RentivoColors.blue)
        }
      }
    }
  }

  private func valueRow(_ label: String, _ money: Money, _ color: Color) -> some View {
    HStack {
      Text(label).font(.subheadline.weight(.semibold))
      Spacer()
      MoneyText(money: money, color: color)
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
          if let replyTo = billing.replyTo {
            Divider()
            Label("Respostas para \(replyTo)", systemImage: "arrowshape.turn.up.left")
              .font(.caption)
          }
        }
      }
    }
  }

  private func load() async {
    state.prepareForRefresh()
    do {
      let data = BillingDetailData(
        billing: try await app.dependencies.billings.billing(id: billingID),
        bills: try await app.dependencies.bills.listBills(billingID: billingID),
        expenses: try await app.dependencies.expenses.listExpenses(billingID: billingID)
      )
      withAnimation(BillingsMotion.load) {
        state = .loaded(data)
      }
    } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }

  private func deleteBilling() async {
    do {
      try await app.dependencies.billings.deleteBilling(id: billingID)
      await onMutation()
      app.showNotice("Cobrança excluída.")
      dismiss()
    } catch {
      app.reportFailure(error)
    }
  }
}
