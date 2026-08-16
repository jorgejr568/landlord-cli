import Foundation
import RentivoCore
import Testing

@testable import Rentivo

// The app-state half of the native (`/api/v1/auth/mobile/*`) sign-in flow, ported from the iOS
// `AppModelNativeAuthTests`. The credential half (persisting the bearer token, recording the
// current user) belongs to `APIRentivoStore` and is covered by the `RentivoCore` package suite;
// `AppModel` must not duplicate it, so these tests assert on `session`, `selectedTab`, and
// `notice` only.
//
// Unlike iOS — where the same Data sources compile into the app target and a stubbed `URLProtocol`
// can drive a real `LiveAPIClient` through `@testable import` — the macOS app links `RentivoCore`
// as a binary package, so `LiveAPIClient`'s internal initializer is out of reach. A programmable
// `StubAuthRepository` standing in for the `auth` slot of `AppDependencies` is what lets these
// exercise every native outcome (authenticated, MFA-required, rejected) headlessly.

@Suite("macOS AppModel native sign-in")
@MainActor
struct AppModelNativeAuthTests {
  private static let profile = UserProfile(id: 21, email: "ana@rentivo.com.br")
  private static let challenge = MFAChallenge(
    challengeId: "challenge-3", challengeToken: "nonce-3", methods: [.totp, .recovery, .passkey])

  @Test("native sign-in authenticates, selects Início, and announces the session")
  func nativeSignInAuthenticatesSelectsHomeAndAnnouncesTheSession() async throws {
    let auth = StubAuthRepository(loginOutcome: .authenticated(Self.profile))
    let app = anonymousLiveApp(auth: auth)
    app.selectedTab = .account

    let outcome = try await app.signIn(email: "ana@rentivo.com.br", password: "segredo")

    #expect(outcome == .authenticated(Self.profile))
    #expect(authenticatedProfile(of: app) == Self.profile)
    #expect(app.selectedTab == .home)
    // Deliberately the same copy the demo shortcut shows: both end in one connected session, and
    // which door the user came through is not something the notice should report.
    #expect(app.notice?.message == "Sessão conectada ao Rentivo.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @Test("an MFA challenge is handed back without authenticating anything")
  func anMFAChallengeIsHandedBackWithoutAuthenticatingAnything() async throws {
    let challenge = MFAChallenge(
      challengeId: "challenge-3", challengeToken: "nonce-3", methods: [.totp, .passkey])
    let auth = StubAuthRepository(loginOutcome: .mfaRequired(challenge))
    let app = anonymousLiveApp(auth: auth)

    let outcome = try await app.signIn(email: "ana@rentivo.com.br", password: "segredo")

    #expect(outcome == .mfaRequired(challenge))
    // The login is not finished, so nothing about the app's state may move yet.
    #expect(app.isAuthenticated == false)
    #expect(app.notice == nil)
  }

  @Test("verifying any second factor finishes the sign-in the challenge interrupted")
  func verifyingASecondFactorFinishesTheSignInTheChallengeInterrupted() async throws {
    let credential = PasskeyAssertionPayload(
      credentialID: Data([0x01]), clientDataJSON: Data([0x02]),
      authenticatorData: Data([0x03]), signature: Data([0x04]))
    // Each factor gets its own model, so passing proves that call authenticated rather than
    // inheriting a session an earlier one left behind.
    let completions: [(String, @MainActor (AppModel) async throws -> Void)] = [
      ("totp", { try await $0.completeTOTP(challenge: Self.challenge, code: "123456") }),
      ("recovery", { try await $0.completeRecoveryCode(challenge: Self.challenge, code: "AAAA-BBBB") }),
      ("passkey", { try await $0.completePasskey(challenge: Self.challenge, credential: credential) }),
    ]

    for (factor, complete) in completions {
      let auth = StubAuthRepository(mfaProfile: Self.profile)
      let app = anonymousLiveApp(auth: auth)
      app.selectedTab = .billings

      try await complete(app)

      #expect(authenticatedProfile(of: app) == Self.profile, "\(factor) should authenticate")
      #expect(app.selectedTab == .home, "\(factor) should land on the home tab")
      #expect(app.notice?.message == "Sessão conectada ao Rentivo.", "\(factor) should announce it")
    }
  }

  @Test("creating an account signs the new user straight in")
  func creatingAnAccountSignsTheNewUserStraightIn() async throws {
    let auth = StubAuthRepository(signupProfile: Self.profile)
    let app = anonymousLiveApp(auth: auth)
    app.selectedTab = .organizations

    try await app.signUp(email: "ana@rentivo.com.br", password: "segredo")

    #expect(authenticatedProfile(of: app) == Self.profile)
    #expect(app.selectedTab == .home)
    #expect(app.notice?.message == "Sessão conectada ao Rentivo.")
  }

  @Test("a rejected sign-in stays anonymous and throws the server's own message")
  func aRejectedSignInStaysAnonymousAndThrowsTheServersOwnMessage() async throws {
    let auth = StubAuthRepository(
      loginError: LiveAPIError.server(message: "Credenciais inválidas.", statusCode: 401))
    let app = anonymousLiveApp(auth: auth)

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

  @Test("deleting the account signs out with no browser round-trip")
  func deletingTheAccountSignsOutWithNoBrowserRoundTrip() async throws {
    let auth = StubAuthRepository(loginOutcome: .authenticated(Self.profile))
    let app = anonymousLiveApp(auth: auth)
    _ = try await app.signIn(email: "ana@rentivo.com.br", password: "segredo")

    await app.deleteAccount(password: "segredo")

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after a successful deletion")
      return
    }
    #expect(auth.deleteAccountCalls == 1)
    // Sign-in is fully native now, so deletion has no shared browser cookie jar to close: the only
    // notice is the deletion's own success, never a "não foi possível encerrar a sessão do
    // navegador" warning.
    #expect(app.notice?.message == "Sua conta foi excluída.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @Test("sign-out revokes the token and drops state with no browser round-trip")
  func signOutRevokesTheTokenAndDropsStateWithNoBrowserRoundTrip() async throws {
    let auth = StubAuthRepository(loginOutcome: .authenticated(Self.profile))
    let app = anonymousLiveApp(auth: auth)
    _ = try await app.signIn(email: "ana@rentivo.com.br", password: "segredo")

    await app.signOut()

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after signOut()")
      return
    }
    #expect(auth.logoutCalls == 1)
    #expect(app.isSigningOut == false)
    #expect(app.selectedTab == .home)
    // `completeSignOut()` clears the notice and nothing re-posts one — there is no browser logout
    // left to warn about.
    #expect(app.notice == nil)
  }

  /// A live-API `AppModel` whose `auth` slot is `auth` and whose every other repository is the
  /// canonical mock. `session` is forced to `.anonymous` because a live model starts out
  /// `.restoring`, and restoring it for real would need a bootstrap round trip these tests do not
  /// exercise.
  private func anonymousLiveApp(auth: StubAuthRepository) -> AppModel {
    let store = MockRentivoStore(fixtures: .canonical)
    let dependencies = AppDependencies(
      auth: auth, profile: store, billings: store, bills: store, expenses: store,
      attachments: store, communications: store, downloads: store, exports: store,
      dashboard: store, activities: store, organizations: store, invitations: store,
      security: store, apiKeys: store, themes: store, demo: store)
    let app = AppModel(dependencies: dependencies)
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

/// A programmable `AuthRepository` for the native-sign-in tests. `usesLiveAPI` is `true` so
/// `AppModel` takes the server-backed sign-out and deletion paths rather than the demo shortcuts.
@MainActor
private final class StubAuthRepository: AuthRepository {
  func accountDeletionReadiness() async throws -> AccountDeletionReadiness {
    AccountDeletionReadiness(canDelete: true)
  }
  private let loginOutcome: MobileLoginOutcome
  private let loginError: Error?
  private let signupProfile: UserProfile
  private let mfaProfile: UserProfile

  private(set) var logoutCalls = 0
  private(set) var deleteAccountCalls = 0

  init(
    loginOutcome: MobileLoginOutcome = .authenticated(UserProfile(id: 0, email: "")),
    loginError: Error? = nil,
    signupProfile: UserProfile = UserProfile(id: 0, email: ""),
    mfaProfile: UserProfile = UserProfile(id: 0, email: "")
  ) {
    self.loginOutcome = loginOutcome
    self.loginError = loginError
    self.signupProfile = signupProfile
    self.mfaProfile = mfaProfile
  }

  var currentUser: UserProfile { UserProfile(id: 0, email: "") }
  var usesLiveAPI: Bool { true }

  func restoreSession() async throws -> UserProfile? { nil }
  func exchangeMobileAuthorization(code: String) async throws -> UserProfile { mfaProfile }

  func mobileLogin(email: String, password: String) async throws -> MobileLoginOutcome {
    if let loginError { throw loginError }
    return loginOutcome
  }

  func mobileSignup(email: String, password: String) async throws -> UserProfile { signupProfile }

  func verifyTotp(challenge: MFAChallenge, code: String) async throws -> UserProfile { mfaProfile }

  func verifyRecoveryCode(challenge: MFAChallenge, code: String) async throws -> UserProfile {
    mfaProfile
  }

  func beginPasskeyAssertion(challenge: MFAChallenge) async throws -> PasskeyRequestOptions {
    PasskeyRequestOptions(
      challenge: Data(), relyingPartyIdentifier: "rentivo.com.br", allowedCredentialIDs: [],
      userVerification: "preferred", timeoutMilliseconds: 60_000)
  }

  func completePasskeyAssertion(
    challenge: MFAChallenge, credential: PasskeyAssertionPayload
  ) async throws -> UserProfile {
    mfaProfile
  }

  func logout() async { logoutCalls += 1 }
  func deleteAccount(password: String) async throws { deleteAccountCalls += 1 }
}
