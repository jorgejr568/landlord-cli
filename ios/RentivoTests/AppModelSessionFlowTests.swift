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

  // MARK: - Live sign-out and account deletion
  //
  // With native login there is no shared browser session to tear down, so `signOut()` and
  // `deleteAccount()` finish on local state alone — no browser round-trip. These use the
  // stubbed-URLProtocol pattern from `APIRentivoStoreAccountDeletionTests` for the API half.

  @MainActor
  @Test func signingOutRevokesTheTokenAndGoesAnonymousWithNoBrowserRoundTrip() async throws {
    let credentials = MemoryCredentialStore(token: "stored-token")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SignOutURLProtocol.self]
    let client = LiveAPIClient(
      session: URLSession(configuration: configuration), credentials: credentials)
    let app = AppModel(dependencies: .live(store: APIRentivoStore(client: client)))
    await app.restoreSessionIfNeeded()
    guard case .authenticated = app.session else {
      Issue.record("Expected restoreSessionIfNeeded to authenticate from the stubbed bootstrap")
      return
    }

    await app.signOut()

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after signOut() against the live store")
      return
    }
    #expect(app.isSigningOut == false)
    #expect(app.selectedTab == .home)
    #expect(app.notice == nil)
    // `logout()` cleared the persisted credential: the token is revoked locally, and no browser
    // session was ever opened to close.
    #expect(await credentials.readAccessToken() == nil)
  }

  @MainActor
  @Test func deletingTheAccountGoesAnonymousAndReportsSuccessWithNoBrowserRoundTrip() async throws {
    let app = try await authenticatedLiveApp(protocolClass: AccountDeletionURLProtocol.self)

    await app.deleteAccount(password: "s3cret")

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after the account was deleted")
      return
    }
    #expect(app.isDeletingAccount == false)
    // Set after `completeSignOut()` clears the notice; nothing else runs to disturb it.
    #expect(app.notice?.message == "Sua conta foi excluída.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @MainActor
  @Test func aRejectedDeletionLeavesTheAccountAndClearsTheInFlightFlag() async throws {
    let app = try await authenticatedLiveApp(protocolClass: RejectedAccountDeletionURLProtocol.self)

    await app.deleteAccount(password: "wrong")

    #expect(app.isDeletingAccount == false)
    // `session` and `notice` are deliberately not asserted here: a live `AppModel` observes the
    // process-wide `liveAPIClientSessionExpired` notification, which the 401 stubs elsewhere in
    // this bundle post while these tests run in parallel — and unlike the successful deletions
    // above, this model is still authenticated, so such a notification would sign it out and
    // replace the notice. The deletions above are immune because they end anonymous, which
    // `handleSessionExpired()` ignores.
  }

  /// A live-API `AppModel` whose session is already restored from the stubbed bootstrap response.
  @MainActor
  private func authenticatedLiveApp(protocolClass: AnyClass) async throws -> AppModel {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [protocolClass]
    let client = LiveAPIClient(
      session: URLSession(configuration: configuration),
      credentials: MemoryCredentialStore(token: "stored-token")
    )
    let app = AppModel(dependencies: .live(store: APIRentivoStore(client: client)))
    await app.restoreSessionIfNeeded()
    guard case .authenticated = app.session else {
      Issue.record("Expected restoreSessionIfNeeded to authenticate from the stubbed bootstrap")
      throw LiveAPIError.invalidResponse
    }
    return app
  }

  /// Authenticates the session bootstrap and then acknowledges the token-revocation logout, so a
  /// live `signOut()` can run end to end.
  private final class SignOutURLProtocol: URLProtocol, @unchecked Sendable {
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
      case "/api/v1/auth/logout":
        (statusCode, body) = (204, Data())
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
