import RentivoCore
import SwiftUI

/// The app-wide "don't blank loaded content on refresh" policy, in one place.
///
/// Every screen here loads through the same skeleton: a `load()` driven both by the first
/// appearance and by re-runs (`.task(id: app.dataRevision)`, the toolbar refresh button, and every
/// mutation that calls back into `load()`). Resetting to `.loading` on each of those re-runs would
/// flash `PageStateView`'s spinner over content the user is already reading, and failing the whole
/// page on a refresh error would throw that content away for a failure the screen can report as a
/// banner instead.
///
/// `LoadState` itself lives in `RentivoCore` and is shared with iOS; this policy is macOS UI
/// behavior, so it stays in the app target as an extension rather than in the shared package.
extension LoadState {
  /// Moves the state into `.loading` only when there is nothing on screen to preserve.
  ///
  /// `.idle` (first load) and `.failed` (retry after a full-page error) have no content to keep, so
  /// they get the spinner. `.loading`, `.loaded`, and `.empty` refresh in place.
  mutating func prepareForRefresh() {
    switch self {
    case .idle, .failed:
      self = .loading
    case .loading, .loaded, .empty:
      break
    }
  }

  /// Resolves a failed load: keep whatever is on screen and report the error as a banner, or fail
  /// the whole page when the screen has nothing to fall back to.
  ///
  /// `.empty` counts as content — it is a rendered state with its own copy and call to action, and
  /// replacing it with a generic error page on a failed refresh loses that.
  @MainActor
  mutating func settleFailure(_ error: some Error, reportingTo app: AppModel) {
    switch self {
    case .loaded, .empty:
      app.reportFailure(error)
    case .idle, .loading, .failed:
      self = .failed(DemoError(error))
    }
  }
}
