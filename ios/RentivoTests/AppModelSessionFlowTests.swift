import AuthenticationServices
import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// `AppModel` lives under `App/`, which the RentivoCore SPM package excludes (see
// `Package.swift`), so these tests only compile/run as part of the Xcode-hosted `RentivoTests`
// target (the full "Rentivo" app module), like the `AppModel`-only section of
// `SessionExpiryTests.swift`.
#if !canImport(RentivoCore)

  @MainActor
  @Test func mockSignInAuthenticatesSelectsHomeAndShowsTheDemoWelcomeNotice() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.selectedTab = .account

    app.signIn()

    guard case .authenticated(let profile) = app.session else {
      Issue.record("Expected an authenticated session after signIn()")
      return
    }
    #expect(profile.email == app.currentUser.email)
    #expect(app.selectedTab == .home)
    #expect(app.notice?.message == "Bem-vinda à demonstração do Rentivo.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @MainActor
  @Test func mockSignOutCompletesSynchronouslyWithoutTogglingIsSigningOut() async {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    app.selectedTab = .billings

    await app.signOut()

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after signOut() against the mock store")
      return
    }
    // The mock store reports `usesLiveAPI == false` and has no token to revoke, so `signOut()`
    // takes the `completeSignOut()` shortcut directly and never flips `isSigningOut` to true in
    // between.
    #expect(app.isSigningOut == false)
    #expect(app.selectedTab == .home)
    #expect(app.notice == nil)
  }

  @MainActor
  @Test func delayToggleSkipsDataRevisionButEmptyAndViewerToggleBumpIt() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let initialRevision = app.dataRevision

    // Only the delay toggle is a "how content loads" setting, not a "what content loads" setting;
    // bumping `dataRevision` for it would force every visible screen to redundantly reload.
    app.setDelayEnabled(true)
    #expect(app.demoSettings.delayEnabled == true)
    #expect(app.dataRevision == initialRevision)

    app.setEmptyMode(true)
    #expect(app.demoSettings.emptyMode == true)
    #expect(app.dataRevision == initialRevision + 1)

    app.setViewerMode(true)
    #expect(app.demoSettings.viewerMode == true)
    #expect(app.dataRevision == initialRevision + 2)
  }

  @MainActor
  @Test func resetDemoRestoresDefaultSettingsAndBumpsDataRevision() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.setDelayEnabled(true)
    app.setEmptyMode(true)
    app.setViewerMode(true)
    let revisionBeforeReset = app.dataRevision

    app.resetDemo()

    #expect(app.demoSettings == .standard)
    #expect(app.dataRevision == revisionBeforeReset + 1)
  }

  // MARK: - Account deletion closes the shared browser session
  //
  // Deleting the account leaves the same web cookies behind that `signOut()` clears, so the
  // deletion runs the identical best-effort browser logout. These use the stubbed-URLProtocol
  // pattern from `APIRentivoStoreAccountDeletionTests` for the API half, and the injected
  // `browserLogout` for the browser half — a real `ASWebAuthenticationSession` cannot be
  // presented from a test run.

  @MainActor
  @Test func deletingTheAccountAlsoClosesTheBrowserSessionAndKeepsItsNotice() async throws {
    let browser = BrowserLogoutSpy()
    let app = try await authenticatedLiveApp(
      protocolClass: AccountDeletionURLProtocol.self, browserLogout: browser.logout)

    await app.deleteAccount(password: "s3cret")

    #expect(browser.calls == 1)
    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after the account was deleted")
      return
    }
    #expect(app.isDeletingAccount == false)
    // Set after `completeSignOut()` clears the notice, and left untouched by a browser logout
    // that succeeded.
    #expect(app.notice?.message == "Sua conta foi excluída.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @MainActor
  @Test func aFailingBrowserLogoutWarnsWithoutHidingTheAccountDeletion() async throws {
    let browser = BrowserLogoutSpy(failure: LiveAPIError.invalidResponse)
    let app = try await authenticatedLiveApp(
      protocolClass: AccountDeletionURLProtocol.self, browserLogout: browser.logout)

    await app.deleteAccount(password: "s3cret")

    #expect(browser.calls == 1)
    guard case .anonymous = app.session else {
      Issue.record("Expected the deletion to stand even though the browser logout failed")
      return
    }
    // The deletion still happened, so the copy reports it alongside the browser-session warning
    // instead of replacing it with `signOut()`'s "Você saiu do Rentivo" wording.
    let warning = "Sua conta foi excluída, mas não foi possível encerrar a sessão do navegador."
    #expect(app.notice?.message == warning)
    guard case .warning = app.notice?.kind else {
      Issue.record("Expected a warning-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @MainActor
  @Test func dismissingTheBrowserLogoutSheetLeavesTheDeletionNoticeAlone() async throws {
    let browser = BrowserLogoutSpy(failure: userCancelledWebAuthentication())
    let app = try await authenticatedLiveApp(
      protocolClass: AccountDeletionURLProtocol.self, browserLogout: browser.logout)

    await app.deleteAccount(password: "s3cret")

    #expect(browser.calls == 1)
    // Closing that sheet is an expected outcome, not a failure worth reporting over the
    // deletion the user just confirmed.
    #expect(app.notice?.message == "Sua conta foi excluída.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @MainActor
  @Test func aRejectedDeletionNeverOpensTheBrowserLogout() async throws {
    let browser = BrowserLogoutSpy()
    let app = try await authenticatedLiveApp(
      protocolClass: RejectedAccountDeletionURLProtocol.self, browserLogout: browser.logout)

    await app.deleteAccount(password: "wrong")

    // Nothing was deleted, so the browser session must stay exactly as it is.
    #expect(browser.calls == 0)
    #expect(app.isDeletingAccount == false)
    // `session` and `notice` are deliberately not asserted here: a live `AppModel` observes the
    // process-wide `liveAPIClientSessionExpired` notification, which the 401 stubs elsewhere in
    // this bundle post while these tests run in parallel — and unlike the successful deletions
    // above, this model is still authenticated, so such a notification would sign it out and
    // replace the notice. The deletions above are immune because they end anonymous, which
    // `handleSessionExpired()` ignores.
  }

  /// A live-API `AppModel` whose session is already restored from the stubbed bootstrap
  /// response, with the shared-browser logout redirected at `browserLogout`.
  @MainActor
  private func authenticatedLiveApp(
    protocolClass: AnyClass,
    browserLogout: @escaping @MainActor () async throws -> Void
  ) async throws -> AppModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]
    let client = LiveAPIClient(
      session: URLSession(configuration: configuration),
      credentials: MemoryCredentialStore(token: "stored-token")
    )
    let app = AppModel(
      dependencies: .live(store: APIRentivoStore(client: client)), browserLogout: browserLogout)
    await app.restoreSessionIfNeeded()
    guard case .authenticated = app.session else {
      Issue.record("Expected restoreSessionIfNeeded to authenticate from the stubbed bootstrap")
      throw LiveAPIError.invalidResponse
    }
    return app
  }

  private func userCancelledWebAuthentication() -> Error {
    ASWebAuthenticationSessionError(
      _nsError: NSError(
        domain: ASWebAuthenticationSessionErrorDomain,
        code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue))
  }

  /// Counts the browser logouts `AppModel` performs and, when `failure` is set, fails them.
  @MainActor
  private final class BrowserLogoutSpy {
    private(set) var calls = 0
    private let failure: Error?

    init(failure: Error? = nil) {
      self.failure = failure
    }

    func logout() async throws {
      calls += 1
      if let failure { throw failure }
    }
  }

  /// Authenticates the session bootstrap and accepts the account deletion; the subclass below
  /// rejects the deletion instead. Two classes rather than one switchable stub so the tests
  /// share no mutable state and stay safe to run in parallel.
  private class AccountDeletionURLProtocol: URLProtocol, @unchecked Sendable {
    class var deletion: (statusCode: Int, body: Data) { (204, Data()) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      let statusCode: Int
      let body: Data
      switch request.url?.path {
      case "/api/v1/auth/session":
        statusCode = 200
        body = Data(
          #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#.utf8
        )
      case "/api/v1/security/delete-account":
        (statusCode, body) = Self.deletion
      default:
        statusCode = 500
        body = Data(#"{"detail":"Endpoint inesperado."}"#.utf8)
      }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: statusCode, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

  private final class RejectedAccountDeletionURLProtocol: AccountDeletionURLProtocol, @unchecked Sendable {
    override class var deletion: (statusCode: Int, body: Data) {
      (400, Data(#"{"detail":"Senha incorreta."}"#.utf8))
    }
  }

  @MainActor
  @Test func restoreSessionIfNeededIsANoOpForTheMockStoreSinceItNeverStartsRestoring() async {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    guard case .anonymous = app.session else {
      Issue.record("Expected the mock-backed AppModel to start anonymous, not restoring")
      return
    }

    await app.restoreSessionIfNeeded()

    guard case .anonymous = app.session else {
      Issue.record("Expected restoreSessionIfNeeded() to leave an already-anonymous session alone")
      return
    }
  }

#endif
