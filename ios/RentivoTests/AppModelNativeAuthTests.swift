import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// `AppModel` lives under `App/`, which the RentivoCore SPM package excludes (see `Package.swift`),
// so these only compile/run inside the Xcode-hosted `RentivoTests` target — same constraint as
// `AppModelSessionFlowTests.swift`, whose stubbed-`URLProtocol` pattern they reuse.
//
// What is under test is the app-state half of the native sign-in flow. The credential half
// (persisting the bearer token, recording the current user) belongs to `APIRentivoStore` and is
// covered by `MobileAuthRepositoryTests`; `AppModel` must not duplicate it, so these tests assert
// on `session`, `selectedTab`, and `notice` only.
#if !canImport(RentivoCore)

  @Suite(.serialized)
  @MainActor
  struct AppModelNativeAuthTests {
    private static let authenticatedBody = #"""
      {"status":"authenticated","credential_transport":"body","access_token":"mobile-token",
       "token_type":"Bearer","expires_in":3600,
       "bootstrap":{"user":{"id":21,"email":"ana@rentivo.com.br"}}}
      """#
    private static let expectedProfile = UserProfile(id: 21, email: "ana@rentivo.com.br")

    @Test func nativeSignInAuthenticatesSelectsHomeAndAnnouncesTheSession() async throws {
      let app = anonymousLiveApp(routes: ["/api/v1/auth/mobile/login": .init(200, Self.authenticatedBody)])
      app.selectedTab = .account

      let outcome = try await app.signIn(email: "ana@rentivo.com.br", password: "segredo")

      #expect(outcome == .authenticated(Self.expectedProfile))
      #expect(authenticatedProfile(of: app) == Self.expectedProfile)
      #expect(app.selectedTab == .home)
      // Deliberately the same copy the browser hand-off shows: both end in one connected session,
      // and which door the user came through is not something the notice should report.
      #expect(app.notice?.message == "Sessão conectada ao Rentivo.")
      #expect(app.notice?.owner == .home)
      guard case .success = app.notice?.kind else {
        Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
        return
      }
    }

    @Test func anMFAChallengeIsHandedBackWithoutAuthenticatingAnything() async throws {
      let app = anonymousLiveApp(
        routes: [
          "/api/v1/auth/mobile/login": .init(
            202,
            #"""
            {"status":"mfa_required","credential_transport":"body","challenge_id":"challenge-3",
             "challenge_token":"nonce-3","methods":["totp","passkey"]}
            """#)
        ])

      let outcome = try await app.signIn(email: "ana@rentivo.com.br", password: "segredo")

      #expect(
        outcome
          == .mfaRequired(
            MFAChallenge(
              challengeId: "challenge-3", challengeToken: "nonce-3", methods: [.totp, .passkey])))
      // The login is not finished, so nothing about the app's state may move yet.
      #expect(app.isAuthenticated == false)
      #expect(app.notice == nil)
    }

    @Test func verifyingASecondFactorFinishesTheSignInTheChallengeInterrupted() async throws {
      let challenge = MFAChallenge(
        challengeId: "challenge-3", challengeToken: "nonce-3", methods: [.totp, .recovery, .passkey])
      let credential = PasskeyAssertionPayload(
        credentialID: Data([0x01]), clientDataJSON: Data([0x02]),
        authenticatorData: Data([0x03]), signature: Data([0x04])
      )
      // Each factor gets its own model, so passing proves that call authenticated rather than
      // inheriting a session an earlier one left behind.
      let completions: [(String, @MainActor (AppModel) async throws -> Void)] = [
        ("/api/v1/auth/mfa/totp/verify", { try await $0.completeTOTP(challenge: challenge, code: "123456") }),
        (
          "/api/v1/auth/mfa/recovery/verify",
          { try await $0.completeRecoveryCode(challenge: challenge, code: "AAAA-BBBB") }
        ),
        (
          "/api/v1/auth/mfa/passkeys/complete",
          { try await $0.completePasskey(challenge: challenge, credential: credential) }
        ),
      ]

      for (path, complete) in completions {
        let app = anonymousLiveApp(routes: [path: .init(200, Self.authenticatedBody)])
        app.selectedTab = .billings

        try await complete(app)

        #expect(authenticatedProfile(of: app) == Self.expectedProfile, "\(path) should authenticate")
        #expect(app.selectedTab == .home, "\(path) should land on the home tab")
        #expect(app.notice?.message == "Sessão conectada ao Rentivo.", "\(path) should announce it")
      }
    }

    @Test func creatingAnAccountSignsTheNewUserStraightIn() async throws {
      let app = anonymousLiveApp(routes: ["/api/v1/auth/mobile/signup": .init(200, Self.authenticatedBody)])
      app.selectedTab = .organizations

      try await app.signUp(email: "ana@rentivo.com.br", password: "segredo")

      #expect(authenticatedProfile(of: app) == Self.expectedProfile)
      #expect(app.selectedTab == .home)
      #expect(app.notice?.message == "Sessão conectada ao Rentivo.")
    }

    @Test func aRejectedSignInStaysAnonymousAndThrowsTheServersOwnMessage() async throws {
      let app = anonymousLiveApp(
        routes: [
          "/api/v1/auth/mobile/login": .init(401, #"{"detail":"Credenciais inválidas."}"#)
        ])

      await #expect(throws: LiveAPIError.server(message: "Credenciais inválidas.", statusCode: 401)) {
        _ = try await app.signIn(email: "ana@rentivo.com.br", password: "errada")
      }

      // The screen keeps the user on the form and shows the error itself; the model must not have
      // moved the session, the tab, or posted a notice behind it.
      guard case .anonymous = app.session else {
        Issue.record("Expected a rejected sign-in to leave the session anonymous")
        return
      }
      #expect(app.notice == nil)
    }

    /// A live-API `AppModel` with no session yet, talking to `routes` through a stubbed
    /// `URLProtocol`. `session` is forced to `.anonymous` because a live model starts out
    /// `.restoring`, and restoring it for real would need a bootstrap round trip these tests do
    /// not exercise.
    private func anonymousLiveApp(routes: [String: NativeAuthStubURLProtocol.Route]) -> AppModel {
      NativeAuthStubURLProtocol.routes = routes
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [NativeAuthStubURLProtocol.self]
      let client = LiveAPIClient(
        session: URLSession(configuration: configuration), credentials: MemoryCredentialStore())
      let app = AppModel(dependencies: .live(store: APIRentivoStore(client: client)))
      app.session = .anonymous
      return app
    }

    private func authenticatedProfile(of app: AppModel) -> UserProfile? {
      guard case .authenticated(let profile) = app.session else {
        Issue.record("Expected an authenticated session")
        return nil
      }
      return profile
    }
  }

  /// Path-routed stub shared by the suite above, which is `.serialized` precisely because this
  /// route table is static.
  private final class NativeAuthStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Route {
      let statusCode: Int
      let body: String

      init(_ statusCode: Int, _ body: String) {
        self.statusCode = statusCode
        self.body = body
      }
    }

    nonisolated(unsafe) static var routes: [String: Route] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      let path = request.url?.path ?? ""
      let route =
        Self.routes[path] ?? Route(500, #"{"detail":"Endpoint inesperado: \#(path)"}"#)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: route.statusCode, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(route.body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

#endif
