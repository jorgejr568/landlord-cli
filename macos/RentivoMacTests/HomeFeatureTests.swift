import Foundation
import RentivoCore
import Testing

@testable import Rentivo

/// Builds a bill with only the fields the dashboard partitioning looks at; everything else is a
/// harmless default so each test reads as the one thing it varies.
private func makeBill(
  id: String,
  status: BillStatus,
  dueDate: DateOnly? = nil,
  billingID: String = "billing-1"
) -> Bill {
  Bill(
    id: BillID(rawValue: id),
    billingID: BillingID(rawValue: billingID),
    referenceMonth: ReferenceMonth(year: 2026, month: 8),
    dueDate: dueDate,
    paidAt: nil,
    notes: "",
    status: status,
    lineItems: [],
    receipts: []
  )
}

@Suite("macOS home dashboard derivations")
struct HomeDashboardTests {
  @Test("only bills in delayed payment reach Atenção necessária")
  func overdueBillsKeepOnlyDelayedPayments() {
    let bills = BillStatus.allCases.map { makeBill(id: $0.rawValue, status: $0) }

    let overdue = HomeDashboard.overdueBills(in: bills)

    #expect(overdue.map(\.status) == [.delayedPayment])
  }

  @Test("Próximas faturas holds exactly the statuses still on their way to being paid")
  func upcomingBillsKeepOnlyUnsettledStatuses() {
    let bills = BillStatus.allCases.map { makeBill(id: $0.rawValue, status: $0) }

    let upcoming = HomeDashboard.upcomingBills(in: bills)

    #expect(Set(upcoming.map(\.status)) == HomeDashboard.upcomingStatuses)
    #expect(HomeDashboard.upcomingStatuses == [.draft, .published, .sent])
    // A delayed bill is already surfaced by "Atenção necessária"; listing it again as "próxima"
    // would double-count it on the dashboard.
    #expect(upcoming.contains { $0.status == .delayedPayment } == false)
  }

  @Test("upcoming bills are ordered by due date, with undated bills last")
  func upcomingBillsSortDatedFirstThenUndated() {
    let bills = [
      makeBill(id: "no-date-a", status: .draft),
      makeBill(id: "late", status: .sent, dueDate: DateOnly(year: 2026, month: 9, day: 1)),
      makeBill(id: "no-date-b", status: .published),
      makeBill(id: "early", status: .draft, dueDate: DateOnly(year: 2026, month: 8, day: 10)),
    ]

    let upcoming = HomeDashboard.upcomingBills(in: bills)

    // A bill with no due date has nothing to be "upcoming" against, so both undated bills follow
    // every dated one instead of leading the list.
    #expect(upcoming.map(\.id.rawValue) == ["early", "late", "no-date-a", "no-date-b"])
  }

  @Test("an empty portfolio derives empty sections rather than failing")
  func derivationsTolerateNoBills() {
    #expect(HomeDashboard.overdueBills(in: []).isEmpty)
    #expect(HomeDashboard.upcomingBills(in: []).isEmpty)
  }

  @Test("the greeting and the empty-activity copy switch on the live API")
  func copySwitchesBetweenLiveAndDemo() {
    #expect(
      HomeDashboard.greetingSubtitle(usesLiveAPI: true) == "Seu portfólio está conectado ao Rentivo."
    )
    #expect(
      HomeDashboard.greetingSubtitle(usesLiveAPI: false)
        == "Seu portfólio está pronto para a demonstração."
    )
    #expect(HomeDashboard.emptyActivityMessage(usesLiveAPI: true) == "Nenhuma atividade recente.")
    #expect(
      HomeDashboard.emptyActivityMessage(usesLiveAPI: false)
        == "As mudanças feitas na demonstração aparecerão aqui."
    )
  }

  @Test("the canonical fixtures split into disjoint overdue and upcoming lists")
  @MainActor
  func canonicalFixturesPartitionWithoutOverlap() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    var bills: [Bill] = []
    for billing in try await store.listBillings() {
      bills.append(contentsOf: try await store.listBills(billingID: billing.id))
    }

    let overdue = HomeDashboard.overdueBills(in: bills)
    let upcoming = HomeDashboard.upcomingBills(in: bills)

    #expect(overdue.isEmpty == false)
    #expect(upcoming.isEmpty == false)
    #expect(Set(overdue.map(\.id)).isDisjoint(with: Set(upcoming.map(\.id))))
  }
}

@Suite("macOS home bill route")
struct BillRouteTests {
  @Test("a route is identified by its billing and its bill together")
  func routeIdentityCoversBothIdentifiers() {
    let route = BillRoute(
      billingID: BillingID(rawValue: "billing-1"), billID: BillID(rawValue: "bill-1")
    )

    #expect(
      route
        == BillRoute(billingID: BillingID(rawValue: "billing-1"), billID: BillID(rawValue: "bill-1"))
    )
    // Two bills can share an identifier suffix across billings, so the billing must take part in
    // both equality and hashing or the navigation stack would conflate them.
    #expect(
      route
        != BillRoute(billingID: BillingID(rawValue: "billing-2"), billID: BillID(rawValue: "bill-1"))
    )
    #expect(
      route
        != BillRoute(billingID: BillingID(rawValue: "billing-1"), billID: BillID(rawValue: "bill-2"))
    )
  }

  @Test("equal routes hash equally, so a pushed route survives a list reload")
  func equalRoutesShareAHashValue() {
    let first = BillRoute(
      billingID: BillingID(rawValue: "billing-1"), billID: BillID(rawValue: "bill-1")
    )
    let second = BillRoute(
      billingID: BillingID(rawValue: "billing-1"), billID: BillID(rawValue: "bill-1")
    )

    #expect(first.hashValue == second.hashValue)
    #expect(Set([first, second]).count == 1)
  }
}
