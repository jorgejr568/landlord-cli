import RentivoCore
import SwiftUI

/// Which owner's billings the portfolio shows. Declared at file scope rather than nested in the
/// view so the filtering rules can be exercised directly by tests.
enum BillingOwnerFilter: String, CaseIterable, Identifiable {
  case all = "Todas"
  case personal = "Pessoais"
  case organization = "Organizações"

  var id: Self { self }

  func matches(_ billing: Billing) -> Bool {
    switch self {
    case .all: true
    case .personal: !billing.owner.isOrganization
    case .organization: billing.owner.isOrganization
    }
  }
}

/// Free-text matching for the portfolio's search field: name, description, or responsible party.
enum BillingPortfolioSearch {
  static func matches(_ billing: Billing, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty
      || billing.name.localizedCaseInsensitiveContains(trimmed)
      || billing.description.localizedCaseInsensitiveContains(trimmed)
      || billing.owner.name.localizedCaseInsensitiveContains(trimmed)
  }
}

private struct BillingPortfolioItem: Identifiable, Sendable {
  let billing: Billing
  let bills: [Bill]
  var id: BillingID { billing.id }
}

struct BillingListView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<[BillingPortfolioItem]> = .idle
  @State private var searchText = ""
  @State private var ownerFilter: BillingOwnerFilter = .all
  @State private var showingCreate = false
  @State private var refresh = RefreshActivity()

  var body: some View {
    PageStateView(
      state: state,
      emptyTitle: "Nenhuma cobrança ainda",
      emptyMessage: "Crie sua primeira cobrança para começar a gerar faturas.",
      emptySystemImage: "doc.text",
      emptyActionTitle: canCreateBilling ? "Nova cobrança" : nil,
      emptyAction: canCreateBilling ? { showingCreate = true } : nil
    ) { items in
      portfolio(items)
    } retry: {
      await load()
    }
    .background(RentivoColors.paper)
    .navigationTitle("Cobranças")
    .searchable(text: $searchText, prompt: "Buscar por nome, responsável ou descrição")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        RefreshToolbarButton(
          activity: refresh,
          help: "Atualizar as cobranças",
          accessibilityIdentifier: "billing.refresh"
        ) {
          await load()
        }
      }
      ToolbarItem(placement: .primaryAction) {
        if canCreateBilling {
          Button {
            showingCreate = true
          } label: {
            Label("Nova cobrança", systemImage: "plus")
          }
          .accessibilityIdentifier("billing.create")
        }
      }
    }
    .sheet(isPresented: $showingCreate) {
      NavigationStack {
        BillingFormView { await load() }
      }
      .rentivoSheetFrame()
    }
    .navigationDestination(for: BillingID.self) { id in
      BillingDetailView(billingID: id)
    }
    .task(id: app.dataRevision) { await load() }
  }

  private var canCreateBilling: Bool { !app.demoSettings.viewerMode }

  private func portfolio(_ items: [BillingPortfolioItem]) -> some View {
    let filtered = filteredItems(items)
    return ScrollView {
      LazyVStack(spacing: RentivoSpacing.large) {
        Picker("Responsável", selection: $ownerFilter) {
          ForEach(BillingOwnerFilter.allCases) { filter in
            Text(filter.rawValue).tag(filter)
          }
        }
        .pickerStyle(.segmented)

        if filtered.isEmpty {
          ContentUnavailableView.search(text: searchText)
            .padding(.top, RentivoSpacing.section)
        } else {
          ForEach(filtered) { item in
            NavigationLink(value: item.id) {
              BillingPortfolioCard(item: item)
            }
            .buttonStyle(.plain)
            .rentivoHoverLift(elevated: true)
            .transition(BillingsMotion.row)
            .accessibilityIdentifier("billing.card.\(item.id.rawValue)")
          }
        }
      }
      .padding(RentivoSpacing.page)
    }
  }

  private func filteredItems(_ items: [BillingPortfolioItem]) -> [BillingPortfolioItem] {
    items.filter {
      ownerFilter.matches($0.billing) && BillingPortfolioSearch.matches($0.billing, query: searchText)
    }
  }

  private func load() async {
    state.prepareForRefresh()
    do {
      let billings = try await app.dependencies.billings.listBillings()
      let items = try await BillLoading.billsByBilling(
        for: billings, using: app.dependencies.bills
      ).map { BillingPortfolioItem(billing: $0.billing, bills: $0.bills) }
      withAnimation(BillingsMotion.load) {
        state = items.isEmpty ? .empty : .loaded(items)
      }
    } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }
}

private struct BillingPortfolioCard: View {
  let item: BillingPortfolioItem

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text(item.billing.name)
              .font(RentivoTypography.cardTitle)
              .foregroundStyle(RentivoColors.ink)
              .multilineTextAlignment(.leading)
            Label(item.billing.owner.name, systemImage: ownerSymbol)
              .font(RentivoTypography.metadata)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          Spacer()
          Image(systemName: "chevron.right")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        Text(item.billing.description)
          .font(RentivoTypography.body)
          .foregroundStyle(RentivoColors.secondaryInk)
          .lineLimit(2)
        HStack {
          VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
            Text("Subtotal fixo")
              .font(RentivoTypography.caption)
              .foregroundStyle(RentivoColors.secondaryInk)
            MoneyText(money: item.billing.fixedSubtotal)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: RentivoSpacing.tiny) {
            Label(
              ptBRCount(item.bills.count, singular: "fatura", plural: "faturas"),
              systemImage: "doc.text"
            )
            Label(pixLabel, systemImage: pixSymbol)
          }
          .font(RentivoTypography.metadata)
          .foregroundStyle(RentivoColors.secondaryInk)
        }
        if let status = item.bills.first?.status {
          StatusBadge(status: status)
        }
      }
    }
  }

  private var ownerSymbol: String {
    item.billing.owner.isOrganization ? "building.2" : "person"
  }

  private var pixLabel: String {
    item.billing.pixOverride?.isComplete == true ? "PIX próprio" : "PIX herdado"
  }

  private var pixSymbol: String {
    item.billing.pixOverride?.isComplete == true ? "qrcode" : "arrow.triangle.branch"
  }
}
