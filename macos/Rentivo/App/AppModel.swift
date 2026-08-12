import Foundation
import Observation
import RentivoCore
import SwiftUI

/// The four top-level sections of the app. `CaseIterable` (unlike the iOS enum, whose tabs are
/// spelled out one by one in its `TabView`) so the macOS sidebar and the "Ir para" menu can both
/// be driven from a single ordered list.
enum AppTab: Hashable, CaseIterable {
  case home
  case billings
  case organizations
  case account
}

struct AppNotice: Identifiable, Equatable {
  enum Kind {
    case success
    case information
    case warning
  }

  let id = UUID()
  let kind: Kind
  let message: String
}

@MainActor
@Observable
final class AppModel {
  enum Session {
    case restoring
    case anonymous
    case authenticated(UserProfile)
  }

  var session: Session = .anonymous
  var selectedTab: AppTab = .home
  var notice: AppNotice?
  var isSigningOut = false
  var isDeletingAccount = false
  var demoSettings: DemoSettings
  var dataRevision = 0
  let dependencies: AppDependencies
  private let mobileWebAuthenticator = MobileWebAuthenticator()

  init(store: MockRentivoStore = MockRentivoStore(fixtures: .canonical)) {
    dependencies = .mock(store: store)
    demoSettings = store.demoSettings
  }

  init(dependencies: AppDependencies) {
    self.dependencies = dependencies
    demoSettings = dependencies.demo.demoSettings
    if dependencies.auth.usesLiveAPI {
      session = .restoring
      observeSessionExpiry()
    }
  }

  var currentUser: UserProfile {
    if case .authenticated(let user) = session { return user }
    return dependencies.auth.currentUser
  }

  var isAuthenticated: Bool {
    if case .authenticated = session { return true }
    return false
  }

  func loadProfile() async throws -> UserProfile {
    let profile = try await dependencies.profile.profile()
    if case .authenticated = session {
      session = .authenticated(profile)
    }
    return profile
  }

  func updateProfilePIX(_ pix: PixConfiguration) async throws -> UserProfile {
    let profile = try await dependencies.profile.updatePix(pix)
    if case .authenticated = session {
      session = .authenticated(profile)
    }
    return profile
  }

  func restoreSessionIfNeeded() async {
    // Only a live-API session ever starts out `.restoring` (see `init(dependencies:)`), so the
    // demo store returns here before its `restoreSession()` — which has nothing to restore — runs.
    guard case .restoring = session else { return }
    do {
      session = try await dependencies.auth.restoreSession().map(Session.authenticated) ?? .anonymous
    } catch {
      session = .anonymous
      notice = AppNotice(kind: .warning, message: "Não foi possível restaurar sua sessão. Entre novamente.")
    }
  }

  var usesLiveAPI: Bool { dependencies.auth.usesLiveAPI }

  func signIn() {
    session = .authenticated(currentUser)
    selectedTab = .home
    notice = AppNotice(kind: .success, message: "Bem-vinda à demonstração do Rentivo.")
  }

  func signInWithWebAuthorization() async throws {
    // Demo mode has no server to authorize against, so it takes the local sign-in shortcut
    // instead of opening a browser sheet.
    guard dependencies.auth.usesLiveAPI else { signIn(); return }
    let code = try await mobileWebAuthenticator.authorize()
    session = .authenticated(try await dependencies.auth.exchangeMobileAuthorization(code: code))
    selectedTab = .home
    notice = AppNotice(kind: .success, message: "Sessão conectada ao Rentivo.")
  }

  func signOut() async {
    guard !isSigningOut else { return }
    // Demo mode has neither a token to revoke nor a browser session to close, so it drops
    // straight to local state.
    guard dependencies.auth.usesLiveAPI else {
      completeSignOut()
      return
    }
    isSigningOut = true
    defer { isSigningOut = false }
    // Revoke the API token first (best-effort inside `logout()`),
    // then unconditionally drop local credentials/state: the user must never
    // end up "signed out" locally while the server still honors the old
    // token, nor stuck signed in locally because a later step failed.
    await dependencies.auth.logout()
    completeSignOut()
    // The browser-cookie logout is best-effort and must never block sign-out
    // (which already happened above). Cancelling that sheet is an expected,
    // silent outcome, not a failure worth reporting.
    do {
      try await mobileWebAuthenticator.logout()
    } catch {
      guard !MobileWebAuthenticator.isUserCancellation(error) else { return }
      notice = AppNotice(
        kind: .warning,
        message: "Você saiu do Rentivo, mas não foi possível encerrar a sessão do navegador."
      )
    }
  }

  func deleteAccount(password: String) async {
    guard !isDeletingAccount else { return }
    // There is no demo account to delete, so demo mode just returns to the signed-out screen
    // without claiming a deletion happened.
    guard dependencies.auth.usesLiveAPI else {
      completeSignOut()
      return
    }
    isDeletingAccount = true
    defer { isDeletingAccount = false }
    do {
      try await dependencies.auth.deleteAccount(password: password)
      completeSignOut()
      notice = AppNotice(kind: .success, message: "Sua conta foi excluída.")
    } catch {
      notice = AppNotice(kind: .warning, message: error.localizedDescription)
    }
  }

  private func completeSignOut() {
    session = .anonymous
    selectedTab = .home
    notice = nil
  }

  /// Reacts to `LiveAPIClient` reporting that the stored token is no longer
  /// valid (a 401 during a background/foreground request), which otherwise
  /// leaves the app "authenticated" while every screen keeps failing until
  /// relaunch. This subscription lives for the lifetime of the app model.
  private func observeSessionExpiry() {
    Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(named: .liveAPIClientSessionExpired) {
        self?.handleSessionExpired()
      }
    }
  }

  /// Exposed so tests can drive the expiry path without a live API client posting the
  /// notification; `observeSessionExpiry()` is the only production caller.
  func handleSessionExpired() {
    // A deliberate `signOut()` also revokes the token via `liveStore.logout()`, whose POST can
    // itself 401 (the token it's revoking is, after all, about to become invalid) and fire this
    // same notification concurrently. Without this guard that race would flash "Sua sessão
    // expirou" mid-sign-out even though the user chose to sign out, not because the session
    // actually expired out from under them.
    guard !isSigningOut else { return }
    guard case .authenticated = session else { return }
    session = .anonymous
    selectedTab = .home
    notice = AppNotice(kind: .warning, message: "Sua sessão expirou. Entre novamente para continuar.")
  }

  func showNotice(_ message: String, kind: AppNotice.Kind = .success) {
    notice = AppNotice(kind: kind, message: message)
  }

  /// Reports a failed action as a warning banner, translated through `DemoError` so every screen
  /// surfaces the same PT-BR copy for the same failure. This is what a `catch` around a
  /// user-initiated action reaches for; a screen that has nothing to show yet still owns the
  /// choice to fail its whole page instead — `LoadState.settleFailure(_:reportingTo:)` is that
  /// choice, made once for every screen that loads content.
  func reportFailure(_ error: some Error) {
    showNotice(DemoError(error).message, kind: .warning)
  }

  func setDelayEnabled(_ enabled: Bool) {
    dependencies.demo.setDelayEnabled(enabled)
    refreshDemoState(reloadContent: false)
  }

  func setEmptyMode(_ enabled: Bool) {
    dependencies.demo.setEmptyMode(enabled)
    refreshDemoState(reloadContent: true)
  }

  func setViewerMode(_ enabled: Bool) {
    dependencies.demo.setViewerMode(enabled)
    refreshDemoState(reloadContent: true)
  }

  func failNextOperation() {
    dependencies.demo.failNextOperation()
  }

  func resetDemo() {
    dependencies.demo.reset()
    refreshDemoState(reloadContent: true)
  }

  private func refreshDemoState(reloadContent: Bool) {
    demoSettings = dependencies.demo.demoSettings
    if reloadContent { dataRevision += 1 }
  }
}
