import Foundation
import RentivoCore
import Testing

@testable import Rentivo

@Suite("macOS fatura detail loading")
@MainActor
struct BillDetailLoadingTests {
  /// The first fatura of the first cobrança in the canonical fixtures, as the detail screen would
  /// have been navigated into.
  private func anyBill(in store: MockRentivoStore) async throws -> (BillingID, BillID) {
    let billing = try #require(await store.listBillings().first)
    let bill = try #require(await store.listBills(billingID: billing.id).first)
    return (billing.id, bill.id)
  }

  @Test("the pair is the same one two sequential fetches would have produced")
  func pairMatchesTheSequentialResult() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let (billingID, billID) = try await anyBill(in: store)

    let pair = try await BillDetailLoading.billingAndBill(
      billingID: billingID, billID: billID, billings: store, bills: store)

    let sequentialBilling = try await store.billing(id: billingID)
    #expect(pair.billing.id == billingID)
    #expect(pair.bill.id == billID)
    #expect(pair.bill.billingID == billingID)
    #expect(pair.billing == sequentialBilling)
  }

  @Test("the two requests overlap instead of adding up")
  func requestsRunConcurrently() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let (billingID, billID) = try await anyBill(in: store)
    // The demo store's delay mode suspends 350ms per operation, standing in for the network wait
    // the live repository spends inside URLSession.
    store.setDelayEnabled(true)

    let started = ContinuousClock.now
    _ = try await BillDetailLoading.billingAndBill(
      billingID: billingID, billID: billID, billings: store, bills: store)
    let elapsed = ContinuousClock.now - started

    // Sequentially the pair costs at least two delays; overlapped it costs roughly one. The bound
    // sits between the two so a busy machine cannot fail it while a regression to serial awaits
    // still would.
    #expect(elapsed < .milliseconds(600))
  }

  @Test("a failure on either half fails the pair")
  func eitherFailureFailsThePair() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let (billingID, billID) = try await anyBill(in: store)
    store.failNextOperation()

    await #expect(throws: DemoError.operationFailed) {
      _ = try await BillDetailLoading.billingAndBill(
        billingID: billingID, billID: billID, billings: store, bills: store)
    }
  }

  @Test("a fatura the repository does not know about fails the pair")
  func unknownBillFailsThePair() async throws {
    let store = MockRentivoStore(fixtures: .canonical)
    let (billingID, _) = try await anyBill(in: store)

    await #expect(throws: DemoError.resourceNotFound) {
      _ = try await BillDetailLoading.billingAndBill(
        billingID: billingID,
        billID: BillID(rawValue: "missing"),
        billings: store,
        bills: store
      )
    }
  }
}
