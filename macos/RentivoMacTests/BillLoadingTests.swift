import Foundation
import RentivoCore
import Testing

@testable import Rentivo

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
