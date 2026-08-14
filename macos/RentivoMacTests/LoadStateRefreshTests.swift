import RentivoCore
import Testing

@testable import Rentivo

/// `LoadState` is not `Equatable` — its payload only has to be `Sendable` — so the assertions here
/// name the case they expect and read any payload out separately.
private func caseName<Value>(_ state: LoadState<Value>) -> String {
  switch state {
  case .idle: "idle"
  case .loading: "loading"
  case .loaded: "loaded"
  case .empty: "empty"
  case .failed: "failed"
  }
}

private func failureMessage<Value>(_ state: LoadState<Value>) -> String? {
  guard case .failed(let error) = state else { return nil }
  return error.message
}

@Suite("macOS LoadState.prepareForRefresh")
struct LoadStatePrepareForRefreshTests {
  @Test("a screen with nothing to preserve shows the spinner")
  func idleAndFailedBecomeLoading() {
    var idle: LoadState<String> = .idle
    idle.prepareForRefresh()
    #expect(caseName(idle) == "loading")

    var failed: LoadState<String> = .failed(.operationFailed)
    failed.prepareForRefresh()
    #expect(caseName(failed) == "loading")
  }

  @Test("a refresh never blanks what is already on screen")
  func loadingLoadedAndEmptyAreLeftAlone() {
    var loading: LoadState<String> = .loading
    loading.prepareForRefresh()
    #expect(caseName(loading) == "loading")

    var loaded: LoadState<String> = .loaded("conteúdo")
    loaded.prepareForRefresh()
    #expect(loaded.value == "conteúdo")

    // `.empty` is a rendered state with its own copy and call to action, so a refresh keeps it
    // instead of swapping it for a spinner.
    var empty: LoadState<String> = .empty
    empty.prepareForRefresh()
    #expect(caseName(empty) == "empty")
  }
}

@Suite("macOS LoadState.settleFailure")
@MainActor
struct LoadStateSettleFailureTests {
  @Test("a failed refresh keeps visible content and reports the error as a banner")
  func loadedAndEmptyKeepContentAndReportTheFailure() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    var loaded: LoadState<String> = .loaded("conteúdo")
    loaded.settleFailure(DemoError.operationFailed, reportingTo: app)
    #expect(loaded.value == "conteúdo")
    #expect(app.notice?.message == DemoError.operationFailed.message)
    #expect(app.notice?.kind == .warning)

    app.notice = nil
    var empty: LoadState<String> = .empty
    empty.settleFailure(DemoError.resourceNotFound, reportingTo: app)
    #expect(caseName(empty) == "empty")
    #expect(app.notice?.message == DemoError.resourceNotFound.message)
  }

  @Test("a screen with nothing to fall back to fails the whole page instead of banner-ing")
  func idleLoadingAndFailedTakeTheFullPageError() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    for var state: LoadState<String> in [.idle, .loading, .failed(.resourceNotFound)] {
      state.settleFailure(DemoError.operationFailed, reportingTo: app)
      #expect(failureMessage(state) == DemoError.operationFailed.message)
    }
    // A full-page error is already the whole screen; adding a banner on top would say it twice.
    #expect(app.notice == nil)
  }

  @Test("a plain error is translated through DemoError like every other screen failure")
  func nonDemoErrorsGetTheSharedCopy() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    struct OpaqueError: Error {}

    var state: LoadState<String> = .idle
    state.settleFailure(OpaqueError(), reportingTo: app)

    #expect(failureMessage(state) == DemoError(OpaqueError()).message)
  }
}

/// A refresh whose completion the test decides, so `isRefreshing` can be observed while one is
/// genuinely in flight rather than inferred from a finished call.
@MainActor
private final class GatedRefresh {
  private(set) var startedRuns = 0
  private(set) var finishedRuns = 0
  private var resume: CheckedContinuation<Void, Never>?
  private var pendingFinish = false

  func run() async {
    startedRuns += 1
    if pendingFinish {
      pendingFinish = false
    } else {
      await withCheckedContinuation { resume = $0 }
    }
    finishedRuns += 1
  }

  /// Releases the refresh that is waiting, or the next one to start. Remembering the signal is
  /// what keeps a test from hanging forever if it gets here a beat before the load suspends.
  func finish() {
    if let resume {
      self.resume = nil
      resume.resume()
    } else {
      pendingFinish = true
    }
  }
}

@Suite("macOS RefreshActivity")
@MainActor
struct RefreshActivityTests {
  @Test("a screen that has not refreshed anything reports nothing in flight")
  func startsIdle() {
    #expect(RefreshActivity().isRefreshing == false)
  }

  @Test("a refresh reports itself while it runs and clears when it finishes")
  func isRefreshingFollowsTheLoad() async {
    let activity = RefreshActivity()
    let gated = GatedRefresh()

    let refresh = Task { await activity.run { await gated.run() } }
    while !activity.isRefreshing { await Task.yield() }

    gated.finish()
    await refresh.value

    #expect(activity.isRefreshing == false)
    #expect(gated.finishedRuns == 1)
  }

  @Test("a second press while a refresh is in flight is dropped instead of racing it")
  func reentrantRefreshIsDropped() async {
    let activity = RefreshActivity()
    let gated = GatedRefresh()

    let refresh = Task { await activity.run { await gated.run() } }
    while !activity.isRefreshing { await Task.yield() }

    await activity.run { await gated.run() }
    // The dropped press must not start a second load: two loads in flight would both assign the
    // screen's state on completion, and the older one could land last.
    #expect(gated.startedRuns == 1)

    gated.finish()
    await refresh.value
    #expect(gated.finishedRuns == 1)
  }

  @Test("the control works again once the previous refresh finished")
  func sequentialRefreshesBothRun() async {
    let activity = RefreshActivity()
    let gated = GatedRefresh()

    for _ in 0..<2 {
      let refresh = Task { await activity.run { await gated.run() } }
      while !activity.isRefreshing { await Task.yield() }
      gated.finish()
      await refresh.value
    }

    #expect(gated.finishedRuns == 2)
    #expect(activity.isRefreshing == false)
  }
}

/// The `load()` skeleton every screen now shares, standing in for a SwiftUI view (whose `load()` is
/// private and unreachable from a unit test) so the idiom is exercised end to end against a real
/// store.
@MainActor
private final class BillingListLoader {
  let app: AppModel
  var state: LoadState<[Billing]> = .idle

  init(app: AppModel) {
    self.app = app
  }

  func load() async {
    state.prepareForRefresh()
    do {
      let billings = try await app.dependencies.billings.listBillings()
      state = billings.isEmpty ? .empty : .loaded(billings)
    } catch {
      state.settleFailure(error, reportingTo: app)
    }
  }
}

@Suite("macOS refresh policy against the demo store")
@MainActor
struct LoadStateRefreshThroughStoreTests {
  @Test("a refresh that fails after content loaded keeps the content and warns")
  func secondLoadFailureKeepsTheFirstLoadsContent() async {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let loader = BillingListLoader(app: app)

    await loader.load()
    let loadedCount = loader.state.value?.count
    #expect(loadedCount ?? 0 > 0)
    app.notice = nil

    app.failNextOperation()
    await loader.load()

    #expect(loader.state.value?.count == loadedCount)
    #expect(app.notice?.message == DemoError.operationFailed.message)
    #expect(app.notice?.kind == .warning)
  }

  @Test("a first load that fails still takes the full-page error state")
  func firstLoadFailureFailsThePage() async {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let loader = BillingListLoader(app: app)

    app.failNextOperation()
    await loader.load()

    #expect(failureMessage(loader.state) == DemoError.operationFailed.message)
    #expect(app.notice == nil)
  }
}
