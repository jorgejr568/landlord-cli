import Foundation
import RentivoCore
import Testing

@testable import Rentivo

/// A `BillRepository` that only answers `listBills`, recording how many of those calls are in
/// flight at once so the fan-out's window can be measured. Every other member is unreachable from
/// `BillLoading`, which is the only thing under test here.
@MainActor
private final class FanOutProbeRepository: BillRepository {
  /// The most requests that were ever open at the same time.
  private(set) var peakInFlight = 0
  private(set) var requestedBillings: [BillingID] = []
  /// The one billing whose request fails, used to check that a failure in a later wave still
  /// fails the whole load.
  var failingBillingID: BillingID?
  private var inFlight = 0

  func listBills(billingID: BillingID) async throws -> [Bill] {
    inFlight += 1
    peakInFlight = max(peakInFlight, inFlight)
    requestedBillings.append(billingID)
    // Standing in for the network wait: without a suspension every child would run to completion
    // before the next one got the main actor, and nothing would ever overlap.
    try? await Task.sleep(for: .milliseconds(20))
    inFlight -= 1
    guard billingID != failingBillingID else { throw DemoError.operationFailed }
    return [
      Bill(
        id: BillID(rawValue: "bill-\(billingID.rawValue)"),
        billingID: billingID,
        referenceMonth: ReferenceMonth(year: 2026, month: 8),
        dueDate: nil,
        paidAt: nil,
        notes: "",
        status: .draft,
        lineItems: [],
        receipts: []
      )
    ]
  }

  func bill(billingID: BillingID, id: BillID) async throws -> Bill { unreachable() }
  func createBill(_ draft: BillDraft) async throws -> Bill { unreachable() }
  func updateBill(billingID: BillingID, billID: BillID, draft: BillDraft) async throws -> Bill {
    unreachable()
  }
  func deleteBill(billingID: BillingID, billID: BillID) async throws { unreachable() }
  func transitionBill(billingID: BillingID, billID: BillID, to status: BillStatus) async throws {
    unreachable()
  }
  func regenerateBill(billingID: BillingID, billID: BillID) async throws -> Bill { unreachable() }
  func addReceipt(billingID: BillingID, billID: BillID, upload: FileUpload) async throws -> Receipt {
    unreachable()
  }
  func reorderReceipts(billingID: BillingID, billID: BillID, receiptIDs: [ReceiptID]) async throws {
    unreachable()
  }
  func deleteReceipt(billingID: BillingID, billID: BillID, receiptID: ReceiptID) async throws {
    unreachable()
  }

  private func unreachable(function: StaticString = #function) -> Never {
    fatalError("BillLoading never calls \(function)")
  }
}

private func makeProbeBillings(count: Int) -> [Billing] {
  (0..<count).map {
    Billing(
      id: BillingID(rawValue: "billing-\($0)"),
      name: "Cobrança \($0)",
      description: "",
      owner: .user(id: StableID.userAna, name: "Pessoal"),
      items: []
    )
  }
}

@Suite("macOS concurrent bill loading")
@MainActor
struct BillLoadingTests {
  @Test("every billing keeps its own bills, in the order the billings were given")
  func pairsFollowTheInputOrder() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let billings = try await store.listBillings()
    #expect(billings.count > 1)

    let pairs = try await BillLoading.billsByBilling(for: billings, using: store)

    #expect(pairs.map(\.billing.id) == billings.map(\.id))
    for pair in pairs {
      // The concurrent fetch must return exactly what a sequential one would have, billing by
      // billing — never another billing's bills shuffled in by completion order.
      let sequential = try await store.listBills(billingID: pair.billing.id)
      #expect(pair.bills == sequential)
      #expect(pair.bills.allSatisfy { $0.billingID == pair.billing.id })
    }
  }

  @Test("the order follows the input, not whichever request finishes first")
  func reversedInputProducesReversedOutput() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let billings = try await store.listBillings().reversed().map { $0 }

    let pairs = try await BillLoading.billsByBilling(for: billings, using: store)

    #expect(pairs.map(\.billing.id) == billings.map(\.id))
  }

  @Test("the requests overlap instead of adding up")
  func requestsRunConcurrently() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let billings = try await store.listBillings()
    // The demo store's delay mode suspends 350ms per operation, which stands in for the network
    // wait the live repository spends inside URLSession.
    store.setDelayEnabled(true)

    let started = ContinuousClock.now
    _ = try await BillLoading.billsByBilling(for: billings, using: store)
    let elapsed = ContinuousClock.now - started

    // Sequentially this would cost at least `billings.count * 350ms`; overlapped it costs roughly
    // one delay. The bound is deliberately loose so a busy machine cannot fail it, while still
    // being far below the sequential floor.
    #expect(billings.count >= 4)
    #expect(elapsed < .milliseconds(350 * billings.count / 2))
  }

  @Test("an empty portfolio resolves to no pairs without touching the repository")
  func noBillingsResolveToNoPairs() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    // Armed to fail: an empty input must not start a single request, so nothing consumes it.
    store.failNextOperation()

    #expect(try await BillLoading.billsByBilling(for: [], using: store).isEmpty)
    // The armed failure is still pending, which proves no bill request ran above.
    await #expect(throws: DemoError.operationFailed) {
      _ = try await store.listBills(billingID: StableID.billingAurora101)
    }
  }

  @Test("a single failed request fails the whole load, as the sequential loop did")
  func oneFailureFailsTheLoad() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let billings = try await store.listBillings()
    store.failNextOperation()

    await #expect(throws: DemoError.operationFailed) {
      _ = try await BillLoading.billsByBilling(for: billings, using: store)
    }
  }

  @Test("a large portfolio never opens more requests than the window allows")
  func fanOutStaysWithinTheWindow() async throws {
    let repository = FanOutProbeRepository()
    let billings = makeProbeBillings(count: BillLoading.maxConcurrentRequests * 3)

    let pairs = try await BillLoading.billsByBilling(for: billings, using: repository)

    #expect(repository.peakInFlight == BillLoading.maxConcurrentRequests)
    // Capping the fan-out must not drop or reorder anything: every billing is still requested
    // exactly once and still gets its own bills back, in the order it was given.
    #expect(repository.requestedBillings.count == billings.count)
    #expect(Set(repository.requestedBillings) == Set(billings.map(\.id)))
    #expect(pairs.map(\.billing.id) == billings.map(\.id))
    for pair in pairs {
      #expect(pair.bills.map(\.billingID) == [pair.billing.id])
    }
  }

  @Test("a portfolio smaller than the window still starts every request at once")
  func smallPortfolioIsNotPaced() async throws {
    let repository = FanOutProbeRepository()
    let billings = makeProbeBillings(count: BillLoading.maxConcurrentRequests - 2)

    _ = try await BillLoading.billsByBilling(for: billings, using: repository)

    #expect(repository.peakInFlight == billings.count)
  }

  @Test("a failure in a later wave fails the load like one in the first")
  func failureAfterTheFirstWaveFailsTheLoad() async throws {
    let repository = FanOutProbeRepository()
    let billings = makeProbeBillings(count: BillLoading.maxConcurrentRequests * 2)
    // Refilled positions only run once an earlier request completed, so this one is reached by the
    // window's refill path rather than by the initial fill.
    repository.failingBillingID = billings.last?.id

    await #expect(throws: DemoError.operationFailed) {
      _ = try await BillLoading.billsByBilling(for: billings, using: repository)
    }
  }

  @Test("a billing the repository does not know about fails the load")
  func unknownBillingFailsTheLoad() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let billings = try await store.listBillings()
    let unknown = Billing(
      id: BillingID(rawValue: "missing"),
      name: "Fantasma",
      description: "",
      owner: .user(id: StableID.userAna, name: "Pessoal"),
      items: []
    )

    await #expect(throws: DemoError.resourceNotFound) {
      _ = try await BillLoading.billsByBilling(for: billings + [unknown], using: store)
    }
  }
}
