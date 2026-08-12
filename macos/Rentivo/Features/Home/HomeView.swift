import RentivoCore
import SwiftUI

/// Everything the Início dashboard renders, resolved by a single `load()` so the screen never
/// shows a half-populated mix of fresh and stale sections.
private struct HomeData: Sendable {
  let summary: DashboardSummary
  let overdueBills: [Bill]
  let upcomingBills: [Bill]
  let billingNames: [BillingID: String]
  let activities: [RecentActivity]
  let hasBillings: Bool
}

/// The pure derivations behind the dashboard. iOS keeps these inline in `HomeView.load()` and in
/// the view bodies; on macOS they are lifted out so the bill partitioning, the ordering rule for
/// undated bills, and the copy that switches on live-vs-demo can be asserted without a view.
enum HomeDashboard {
  /// A bill is upcoming while it is still on its way to being paid. `paid`, `cancelled`, and
  /// `delayedPayment` are all excluded: the first two are finished and the third belongs to
  /// "Atenção necessária" instead.
  static let upcomingStatuses: Set<BillStatus> = [.draft, .published, .sent]

  static func overdueBills(in bills: [Bill]) -> [Bill] {
    bills.filter { $0.status == .delayedPayment }
  }

  static func upcomingBills(in bills: [Bill]) -> [Bill] {
    bills.filter { upcomingStatuses.contains($0.status) }.sorted {
      // A bill with no due date has nothing to be "upcoming" against, so it sorts after
      // every dated bill rather than ahead of them.
      switch ($0.dueDate, $1.dueDate) {
      case let (lhs?, rhs?): return lhs < rhs
      case (_?, nil): return true
      case (nil, _?): return false
      case (nil, nil): return false
      }
    }
  }

  static func greetingSubtitle(usesLiveAPI: Bool) -> String {
    usesLiveAPI
      ? "Seu portfólio está conectado ao Rentivo."
      : "Seu portfólio está pronto para a demonstração."
  }

  static func emptyActivityMessage(usesLiveAPI: Bool) -> String {
    usesLiveAPI
      ? "Nenhuma atividade recente."
      : "As mudanças feitas na demonstração aparecerão aqui."
  }
}

struct HomeView: View {
  @Environment(AppModel.self) private var app
  @State private var state: LoadState<HomeData> = .idle

  var body: some View {
    PageStateView(state: state) { data in
      HomeContent(data: data) { await load() }
    } retry: {
      await load()
    }
    .rentivoPage()
    .navigationTitle("Início")
    .toolbar {
      // macOS has no pull-to-refresh, so the reload iOS gets from `.refreshable` is a toolbar
      // command here (and ⌘R, the platform-standard refresh shortcut).
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await load() }
        } label: {
          Label("Atualizar", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
        .help("Atualizar o painel")
        .accessibilityIdentifier("home.refresh")
      }
      ToolbarItem(placement: .primaryAction) {
        BrandMark(compact: true)
      }
    }
    .task(id: app.dataRevision) { await load() }
  }

  private func load() async {
    // Only blank the screen with a spinner when nothing has been shown yet
    // (first launch or a previously-failed load). The toolbar refresh and every
    // section revisit (`.task(id: app.dataRevision)`) otherwise refresh the
    // dashboard in place, keeping the current cards on screen.
    switch state {
    case .idle, .failed:
      state = .loading
    case .loading, .loaded, .empty:
      break
    }
    do {
      let summary = try await app.dependencies.dashboard.dashboardSummary()
      let billings = try await app.dependencies.billings.listBillings()
      var bills: [Bill] = []
      for billing in billings {
        bills.append(contentsOf: try await app.dependencies.bills.listBills(billingID: billing.id))
      }
      let names = Dictionary(uniqueKeysWithValues: billings.map { ($0.id, $0.name) })
      let data = HomeData(
        summary: summary,
        overdueBills: HomeDashboard.overdueBills(in: bills),
        upcomingBills: HomeDashboard.upcomingBills(in: bills),
        billingNames: names,
        activities: app.dependencies.activities.recentActivities,
        hasBillings: !billings.isEmpty
      )
      // The dashboard (summary cards, activity) is always meaningful, even
      // with zero billings — show it with zeroed cards plus an explainer
      // section rather than replacing the whole screen with a generic empty
      // state that has no create action on this screen.
      state = .loaded(data)
    } catch {
      if state.value != nil {
        app.reportFailure(error)
      } else {
        state = .failed(DemoError(error))
      }
    }
  }
}

/// Value-based route to a bill's detail screen. The links are value-based (and
/// not `NavigationLink { BillDetailView(...) }`) because acting on a bill from
/// its detail screen — publishing, sending, marking it paid — reloads the
/// dashboard and drops that bill out of "Próximas faturas". A view-based link
/// would be torn down along with its row and pop the user back to Início
/// mid-flow; a pushed value survives its source disappearing.
///
/// Internal rather than `private` (as on iOS) because `BillRouteTests` asserts on the route's
/// equality and hashing directly — the very properties `navigationDestination` relies on.
struct BillRoute: Hashable {
  let billingID: BillingID
  let billID: BillID
}

private struct HomeContent: View {
  @Environment(AppModel.self) private var app
  let data: HomeData
  /// Reloads the dashboard after a bill opened from here is mutated on its
  /// detail screen (status transition, edit, deletion), so the summary cards
  /// and the "Próximas faturas" list don't go stale behind the pushed view.
  let reload: () async -> Void

  /// Above this width the detail column fits two columns of cards side by side. Below it the
  /// sections stack in the iOS order instead of being squeezed.
  private static let wideLayoutThreshold: CGFloat = 980
  /// Long-form reading width. Cards stretched across a full-screen 27" display would put the
  /// money on one edge and its label on the other.
  private static let contentMaxWidth: CGFloat = 1100
  private static let activityColumnWidth: CGFloat = 360

  var body: some View {
    GeometryReader { proxy in
      let isWide = proxy.size.width >= Self.wideLayoutThreshold
      ScrollView {
        VStack(alignment: .leading, spacing: RentivoSpacing.section) {
          greeting
            .homeSection(index: 0)
          summaryGrid(isWide: isWide)
            .homeSection(index: 1)
          if isWide {
            wideSections
          } else {
            stackedSections
          }
        }
        .padding(RentivoSpacing.page)
        .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
      }
    }
    .navigationDestination(for: BillRoute.self) { route in
      BillDetailView(billingID: route.billingID, billID: route.billID, onMutation: reload)
    }
  }

  /// The bill-facing sections, in the iOS order. Shared by both layouts so the wide window is
  /// purely a rearrangement — never a different dashboard.
  @ViewBuilder
  private var primarySections: some View {
    if data.hasBillings {
      if !data.overdueBills.isEmpty {
        overdueSection
          .homeSection(index: 2)
      }
      quickActions
        .homeSection(index: 3)
      if !data.upcomingBills.isEmpty {
        billsSection(
          title: "Próximas faturas",
          bills: Array(data.upcomingBills.prefix(4))
        )
        .homeSection(index: 4)
      }
    } else {
      noBillingsSection
        .homeSection(index: 2)
    }
  }

  private var wideSections: some View {
    HStack(alignment: .top, spacing: RentivoSpacing.section) {
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        primarySections
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .leading, spacing: RentivoSpacing.section) {
        activitySection
          .homeSection(index: 5)
      }
      .frame(width: Self.activityColumnWidth, alignment: .leading)
    }
  }

  private var stackedSections: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.section) {
      primarySections
      activitySection
        .homeSection(index: 5)
    }
  }

  /// Three cards across once there is room to keep them legible, two otherwise — which is the
  /// iOS layout. A `.adaptive` grid item is deliberately avoided: it collapses to a single
  /// full-width column in a narrow detail pane.
  private func summaryGrid(isWide: Bool) -> some View {
    LazyVGrid(
      columns: Array(
        repeating: GridItem(.flexible(), spacing: RentivoSpacing.medium),
        count: isWide ? 3 : 2
      ),
      spacing: RentivoSpacing.medium
    ) {
      SummaryCard(
        title: "Recebido",
        value: data.summary.received,
        symbol: "arrow.down.circle.fill",
        color: RentivoColors.emerald
      )
      SummaryCard(
        title: "Despesas",
        value: data.summary.expenses,
        symbol: "arrow.up.circle.fill",
        color: RentivoColors.coral
      )
      SummaryCard(
        title: "Resultado",
        value: data.summary.netIncome,
        symbol: "chart.line.uptrend.xyaxis",
        color: RentivoColors.blue
      )
      CollectionCard(percent: data.summary.collectionRatePercent)
    }
  }

  private var greeting: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      Text("Olá!")
        .font(RentivoTypography.display)
        .foregroundStyle(RentivoColors.ink)
      Text(HomeDashboard.greetingSubtitle(usesLiveAPI: app.usesLiveAPI))
        .foregroundStyle(RentivoColors.secondaryInk)
      HStack {
        Label("Saldo em atraso", systemImage: "clock.badge.exclamationmark")
          .font(.caption.weight(.semibold))
        Spacer()
        MoneyText(money: data.summary.overdue, color: RentivoColors.coral)
          .contentTransition(.numericText())
          .animation(.snappy, value: data.summary.overdue)
      }
      .padding(.top, RentivoSpacing.small)
    }
  }

  private var overdueSection: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Atenção necessária", symbol: "exclamationmark.triangle.fill")
      RentivoCard {
        VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
          Text(
            "Há \(ptBRCount(data.overdueBills.count, singular: "fatura em acompanhamento", plural: "faturas em acompanhamento"))"
          )
          .font(RentivoTypography.cardTitle)
          Text("Abra Cobranças para registrar o pagamento ou cancelar a fatura.")
            .font(.subheadline)
            .foregroundStyle(RentivoColors.secondaryInk)
          Button("Ver cobranças") { app.selectedTab = .billings }
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private var quickActions: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Ações rápidas", symbol: "bolt.fill")
      Button {
        app.selectedTab = .billings
      } label: {
        // This action only switches to the Cobranças section — it does not open a
        // create flow (that would require the Cobranças section to observe a
        // cross-section "present create sheet" signal, which lives outside the
        // files this screen owns). Naming it "Ver cobranças" keeps the label
        // honest about what actually happens.
        Label("Ver cobranças", systemImage: "list.bullet.rectangle.fill")
      }
      .buttonStyle(RentivoButtonStyle())
    }
  }

  private var noBillingsSection: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Comece por aqui", symbol: "sparkles")
      RentivoCard {
        VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
          Text("Nenhuma cobrança cadastrada ainda")
            .font(RentivoTypography.cardTitle)
          Text(
            "Crie sua primeira cobrança recorrente na aba Cobranças para começar a acompanhar recebimentos, despesas e faturas por aqui."
          )
          .font(.subheadline)
          .foregroundStyle(RentivoColors.secondaryInk)
          Button("Ver cobranças") { app.selectedTab = .billings }
            .buttonStyle(RentivoButtonStyle())
        }
      }
    }
  }

  private func billsSection(title: String, bills: [Bill]) -> some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: title, symbol: "calendar")
      ForEach(bills) { bill in
        NavigationLink(value: BillRoute(billingID: bill.billingID, billID: bill.id)) {
          RentivoCard {
            VStack(alignment: .leading, spacing: RentivoSpacing.small) {
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
                  Text(data.billingNames[bill.billingID] ?? "Cobrança")
                    .font(RentivoTypography.cardTitle)
                  Text(bill.referenceMonth.label.capitalized)
                    .font(.subheadline)
                    .foregroundStyle(RentivoColors.secondaryInk)
                }
                Spacer()
                StatusBadge(status: bill.status)
              }
              HStack {
                if let dueDate = bill.dueDate {
                  Label("Vence em \(dueDate.displayFormatted)", systemImage: "calendar")
                    .font(.caption)
                }
                Spacer()
                MoneyText(money: bill.effectiveTotal)
                  .contentTransition(.numericText())
                  .animation(.snappy, value: bill.effectiveTotal)
              }
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.bill.card.\(bill.id.rawValue)")
      }
    }
  }

  private var activitySection: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      SectionTitle(title: "Atividade recente", symbol: "clock.arrow.circlepath")
      if data.activities.isEmpty {
        Text(HomeDashboard.emptyActivityMessage(usesLiveAPI: app.usesLiveAPI))
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(data.activities.prefix(5)) { activity in
          HStack(alignment: .top, spacing: RentivoSpacing.medium) {
            Image(systemName: activity.kind.symbol)
              .foregroundStyle(RentivoColors.emerald)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
              Text(activity.title)
                .font(.subheadline.weight(.semibold))
              Text(activity.detail)
                .font(.caption)
                .foregroundStyle(RentivoColors.secondaryInk)
            }
            Spacer()
          }
          .padding(.vertical, RentivoSpacing.tiny)
        }
      }
    }
  }
}

/// Sections fade and rise into place in reading order. The stagger is deliberately short — the
/// whole dashboard has settled before a pointer can cross it — and collapses to an instant
/// reveal under Reduce Motion.
private struct HomeSectionAppearance: ViewModifier {
  let index: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  private var isVisible: Bool { hasAppeared || reduceMotion }

  func body(content: Content) -> some View {
    content
      .opacity(isVisible ? 1 : 0)
      .offset(y: isVisible ? 0 : 14)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(
          .spring(response: 0.42, dampingFraction: 0.86).delay(Double(index) * 0.06)
        ) {
          hasAppeared = true
        }
      }
  }
}

extension View {
  fileprivate func homeSection(index: Int) -> some View {
    modifier(HomeSectionAppearance(index: index))
  }
}

private struct SummaryCard: View {
  let title: String
  let value: Money
  let symbol: String
  let color: Color

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.small) {
        Image(systemName: symbol)
          .font(.title2)
          .foregroundStyle(color)
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(RentivoColors.secondaryInk)
        MoneyText(
          money: value,
          color: RentivoColors.ink,
          font: .system(.subheadline, design: .monospaced, weight: .bold),
          minimumScaleFactor: 0.7,
          lineLimit: 1,
          accessibilityLabelOverride: "\(title): \(value.formatted())"
        )
        .contentTransition(.numericText())
        .animation(.snappy, value: value)
      }
    }
  }
}

private struct CollectionCard: View {
  let percent: Int

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.small) {
        Image(systemName: "percent")
          .font(.title2)
          .foregroundStyle(RentivoColors.lilac)
        Text("Taxa de recebimento")
          .font(.caption.weight(.semibold))
          .foregroundStyle(RentivoColors.secondaryInk)
        Text("\(percent)%")
          .font(.system(.title3, design: .monospaced, weight: .bold))
          .foregroundStyle(RentivoColors.ink)
          .contentTransition(.numericText())
          .animation(.snappy, value: percent)
      }
    }
  }
}

extension ActivityKind {
  fileprivate var symbol: String {
    switch self {
    case .billing: "house.fill"
    case .bill: "doc.text.fill"
    case .expense: "wrench.and.screwdriver.fill"
    case .organization: "building.2.fill"
    case .invitation: "envelope.fill"
    case .security: "lock.shield.fill"
    case .apiKey: "key.fill"
    case .theme: "paintpalette.fill"
    }
  }
}
