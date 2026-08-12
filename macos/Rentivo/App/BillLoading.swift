import RentivoCore

/// A billing together with the bills that belong to it, as resolved by `BillLoading`.
struct BillingBills: Sendable {
  let billing: Billing
  let bills: [Bill]
}

/// Fetching every billing's bills for the screens that render a whole portfolio at once.
///
/// Início and Cobranças both need one `listBills(billingID:)` per billing. Doing that in a `for`
/// loop makes a refresh cost the sum of every request, so a real account with a dozen cobranças
/// pays a dozen round trips end to end. The requests are independent, so they run as a task group
/// instead and the refresh costs roughly the slowest one.
///
/// `BillRepository` is `@MainActor`, and so is this helper — but that does not serialize the
/// network. Each child hops to the main actor for the call, and the live implementation then awaits
/// `URLSession`; every `await` releases the actor, so the children interleave: one hands the actor
/// back while its request is in flight and the next starts its own.
///
/// No concurrency cap: a portfolio is a handful of cobranças, not a queue worth pacing, and the
/// live client already funnels through `URLSession`'s own connection limits.
@MainActor
enum BillLoading {
  /// Carries the repository into the child tasks.
  ///
  /// `any BillRepository` is not `Sendable` — the protocol is `@MainActor` but the existential
  /// carries no such guarantee — so the reference cannot be captured by a child task directly.
  /// Passing it inside this box is safe because nothing is ever *done* with it off the main actor:
  /// every member of `BillRepository` is main-actor isolated, so each `listBills` call hops back
  /// before it touches any state.
  private struct RepositoryBox: @unchecked Sendable {
    let repository: any BillRepository
  }

  /// Loads each billing's bills concurrently, in the order the billings were given.
  ///
  /// The result never depends on which request finishes first: children report their input
  /// position and the pairs are reassembled from it. Any failure propagates — the task group
  /// cancels the siblings and the whole load fails, exactly as the sequential loop did.
  static func billsByBilling(
    for billings: [Billing],
    using repository: any BillRepository
  ) async throws -> [BillingBills] {
    let box = RepositoryBox(repository: repository)
    var bills = [[Bill]](repeating: [], count: billings.count)
    try await withThrowingTaskGroup(of: (offset: Int, bills: [Bill]).self) { group in
      for (offset, billing) in billings.enumerated() {
        group.addTask {
          (offset, try await box.repository.listBills(billingID: billing.id))
        }
      }
      for try await result in group {
        bills[result.offset] = result.bills
      }
    }
    return zip(billings, bills).map(BillingBills.init)
  }
}
