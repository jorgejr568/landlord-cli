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

/// The other half of that policy: a refresh that keeps content on screen has nothing to say for
/// itself, so the control that started it says it instead.
///
/// A screen holds one of these in `@State` and routes its refresh control through `run(_:)`. While
/// a refresh is in flight `isRefreshing` is true — the control spins and is disabled — and a second
/// press is dropped rather than starting a load that would race the first one to assign `state`.
///
/// Only the refresh control goes through here. A `.task(id:)` re-run and the reloads a mutation
/// triggers still call `load()` directly: those carry data the screen must not miss, so dropping
/// one because a manual refresh happened to be running would leave the user looking at a stale
/// screen.
@MainActor
@Observable
final class RefreshActivity {
  private(set) var isRefreshing = false

  init() {}

  /// Runs `load` unless one is already running.
  func run(_ load: () async -> Void) async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    await load()
  }
}

/// The toolbar refresh control, shared by every screen that has one.
///
/// macOS has no pull-to-refresh, so the reload iOS gets from `.refreshable` is a toolbar command
/// here — and ⌘R, the platform-standard refresh shortcut. The label becomes a spinner while the
/// load is in flight so a refresh over already-loaded content is visibly happening.
struct RefreshToolbarButton: View {
  let activity: RefreshActivity
  var help: String?
  var accessibilityIdentifier: String?
  let load: () async -> Void

  var body: some View {
    Button {
      Task { await activity.run(load) }
    } label: {
      if activity.isRefreshing {
        ProgressView()
          .controlSize(.small)
      } else {
        Label("Atualizar", systemImage: "arrow.clockwise")
      }
    }
    .disabled(activity.isRefreshing)
    .keyboardShortcut("r", modifiers: .command)
    .help(help ?? "Atualizar")
    .accessibilityLabel("Atualizar")
    .accessibilityIdentifier(accessibilityIdentifier ?? "page.refresh")
  }
}
