import RentivoCore
import Testing

@testable import Rentivo

// The macOS `AppModel` is a port of the iOS one and carries the same session, demo, and
// session-expiry contracts, so it is covered here the way `ios/RentivoTests` covers its twin.
// `AppDependencies.mock(store:)` is the only backend these tests need: the live path would
// require a real server.

@Suite("macOS AppModel session flow")
@MainActor
struct AppModelSessionFlowTests {
  @Test("sign-in authenticates, selects Início, and shows the demo welcome notice")
  func mockSignInAuthenticatesSelectsHomeAndShowsTheDemoWelcomeNotice() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.selectedTab = .account

    app.signIn()

    guard case .authenticated(let profile) = app.session else {
      Issue.record("Expected an authenticated session after signIn()")
      return
    }
    #expect(profile.email == app.currentUser.email)
    #expect(app.isAuthenticated)
    #expect(app.selectedTab == .home)
    #expect(app.notice?.message == "Bem-vinda à demonstração do Rentivo.")
    guard case .success = app.notice?.kind else {
      Issue.record("Expected a success-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }

  @Test("browser sign-in falls back to the local demo shortcut without a live API")
  func signInWithWebAuthorizationTakesTheDemoShortcut() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    // The mock store reports `usesLiveAPI == false`, so no `ASWebAuthenticationSession` is
    // opened — which is also what keeps this test runnable headlessly.
    try await app.signInWithWebAuthorization()

    #expect(app.isAuthenticated)
    #expect(app.notice?.message == "Bem-vinda à demonstração do Rentivo.")
  }

  @Test("sign-out completes synchronously without toggling isSigningOut")
  func mockSignOutCompletesSynchronouslyWithoutTogglingIsSigningOut() async {
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

  @Test("deleting the demo account returns to the signed-out screen without claiming a deletion")
  func deleteAccountOnTheDemoStoreJustSignsOut() async {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()

    await app.deleteAccount(password: "irrelevante")

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session after deleteAccount() against the mock store")
      return
    }
    #expect(app.isDeletingAccount == false)
    #expect(app.notice == nil)
  }

  @Test("restoreSessionIfNeeded is a no-op because the demo store never starts restoring")
  func restoreSessionIfNeededIsANoOpForTheMockStoreSinceItNeverStartsRestoring() async {
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

  @Test("showNotice publishes the message with the requested kind")
  func showNoticePublishesTheRequestedKind() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    app.showNotice("Falha ao carregar as cobranças.", kind: .warning)

    #expect(app.notice?.message == "Falha ao carregar as cobranças.")
    guard case .warning = app.notice?.kind else {
      Issue.record("Expected a warning-kind notice, got \(String(describing: app.notice?.kind))")
      return
    }
  }
}

@Suite("macOS AppModel session expiry")
@MainActor
struct AppModelSessionExpiryTests {
  @Test("an expired session drops to Início and explains itself in PT-BR")
  func expiredSessionSignsOutAndShowsThePTBRNotice() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    app.selectedTab = .organizations

    app.handleSessionExpired()

    guard case .anonymous = app.session else {
      Issue.record("Expected the session to become anonymous after the token expired")
      return
    }
    #expect(app.selectedTab == .home)
    #expect(app.notice?.message == "Sua sessão expirou. Entre novamente para continuar.")
  }

  @Test("an expiry arriving mid-sign-out is ignored")
  func expiredSessionIsIgnoredWhileSigningOut() {
    // Regression guard, ported from iOS: `signOut()`'s own logout POST can itself 401 (the token
    // it's revoking is, after all, about to become invalid), racing the session-expiry
    // notification against the deliberate sign-out and briefly showing "Sua sessão expirou".
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    app.notice = nil
    app.isSigningOut = true

    app.handleSessionExpired()

    guard case .authenticated = app.session else {
      Issue.record("Expected the session to stay authenticated while isSigningOut is set")
      return
    }
    #expect(app.notice == nil)
  }

  @Test("an expiry arriving while already signed out changes nothing")
  func expiredSessionIsIgnoredWhileAnonymous() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    app.handleSessionExpired()

    guard case .anonymous = app.session else {
      Issue.record("Expected an anonymous session to stay anonymous")
      return
    }
    #expect(app.notice == nil)
  }
}
