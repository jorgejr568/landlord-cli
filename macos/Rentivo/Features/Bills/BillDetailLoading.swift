import RentivoCore

/// Fetching the two independent halves of the fatura screen at once.
///
/// `BillDetailView` needs the cobrança (for its name and capabilities) and the fatura itself.
/// Neither request depends on the other's answer, so awaiting them in sequence made opening a
/// fatura cost both round trips end to end; `async let` makes it cost roughly the slower one.
///
/// Same reasoning as `BillLoading`, and the same apparent contradiction: both repositories are
/// `@MainActor`, yet this does not serialize the network. Each child hops to the main actor to
/// make its call, and the live implementation then awaits `URLSession` — every `await` releases
/// the actor, so one request is in flight while the other is being started.
@MainActor
enum BillDetailLoading {
  /// Loads the cobrança and the fatura concurrently. Either failure fails the pair, exactly as the
  /// sequential pair of `await`s did — the screen has nothing partial worth showing.
  ///
  /// Both repositories travel into their child task inside a `RepositoryBox`, the shared escape
  /// hatch for handing a `@MainActor` existential to `async let`; see that type for why it is safe.
  static func billingAndBill(
    billingID: BillingID,
    billID: BillID,
    billings: any BillingRepository,
    bills: any BillRepository
  ) async throws -> (billing: Billing, bill: Bill) {
    let billingsBox = RepositoryBox(billings)
    let billsBox = RepositoryBox(bills)
    async let billing = billingsBox.repository.billing(id: billingID)
    async let bill = billsBox.repository.bill(billingID: billingID, id: billID)
    return try await (billing, bill)
  }
}
