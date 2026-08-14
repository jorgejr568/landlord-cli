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
/// instead and the refresh costs roughly the slowest one — or, past the cap below, the slowest of
/// each windowful.
///
/// `BillRepository` is `@MainActor`, and so is this helper — but that does not serialize the
/// network. Each child hops to the main actor for the call, and the live implementation then awaits
/// `URLSession`; every `await` releases the actor, so the children interleave: one hands the actor
/// back while its request is in flight and the next starts its own.
///
/// The fan-out is capped rather than unbounded. A typical portfolio is a handful of cobranças and
/// still starts every request at once; an account with dozens would otherwise hand all of them to
/// `URLSession` in one go, where they queue behind its per-host connection limit anyway — ahead of
/// whatever else the app needs while the queue drains. Holding the surplus here instead keeps that
/// queue short, and keeps the group's own cost (a live child task and a pending response per
/// billing) proportional to the window rather than to the account.
@MainActor
enum BillLoading {
  /// How many `listBills` requests may be in flight at once.
  ///
  /// Six clears every realistic portfolio in a single wave, so the common case is exactly as
  /// concurrent as it was before the cap; only an unusually large account pays for the window.
  /// Internal rather than private so the tests can assert the fan-out against the same number the
  /// loader uses.
  static let maxConcurrentRequests = 6

  /// Loads each billing's bills concurrently, in the order the billings were given.
  ///
  /// The result never depends on which request finishes first: children report their input
  /// position and the pairs are reassembled from it. Any failure propagates — the task group
  /// cancels the siblings and the whole load fails, exactly as the sequential loop did.
  ///
  /// At most `maxConcurrentRequests` children run at a time: the window is filled up front and
  /// then refilled one request per completion, so the group never holds more than that many
  /// requests open while still keeping the window full until the input runs out.
  static func billsByBilling(
    for billings: [Billing],
    using repository: any BillRepository
  ) async throws -> [BillingBills] {
    let box = RepositoryBox(repository)
    var bills = [[Bill]](repeating: [], count: billings.count)
    try await withThrowingTaskGroup(of: (offset: Int, bills: [Bill]).self) { group in
      var next = 0
      func addRequest() {
        let offset = next
        let billingID = billings[offset].id
        group.addTask {
          (offset, try await box.repository.listBills(billingID: billingID))
        }
        next += 1
      }

      while next < min(maxConcurrentRequests, billings.count) {
        addRequest()
      }
      while let result = try await group.next() {
        bills[result.offset] = result.bills
        if next < billings.count { addRequest() }
      }
    }
    return zip(billings, bills).map(BillingBills.init)
  }
}
