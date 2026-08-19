import Foundation
import Observation
import SwiftUI

enum AppTab: Hashable {
  case home
  case billings
  case organizations
  case account
}

enum NoticeArea: Hashable, Sendable {
  case authentication
  case home
  case billings
  case billingDetail
  case billOperations
  case organizations
  case invitations
  case account
  case security
  case apiKeys
  case appearance
  case demoScenarios
}

extension AppTab {
  var noticeArea: NoticeArea {
    switch self {
    case .home: .home
    case .billings: .billings
    case .organizations: .organizations
    case .account: .account
    }
  }
}

struct AppNotice: Identifiable, Equatable {
  enum Kind {
    case success
    case information
    case warning
  }

  let id: UUID
  let kind: Kind
  let message: String
  let owner: NoticeArea

  init(
    id: UUID = UUID(),
    kind: Kind,
    message: String,
    owner: NoticeArea = .authentication
  ) {
    self.id = id
    self.kind = kind
    self.message = message
    self.owner = owner
  }
}

struct AppNoticeClock {
  let now: @MainActor () -> TimeInterval
  let sleep: @MainActor (TimeInterval) async throws -> Void

  static let continuous = AppNoticeClock(
    now: { ProcessInfo.processInfo.systemUptime },
    sleep: { duration in
      try await ContinuousClock().sleep(for: .seconds(duration))
    }
  )
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
  var selectedTab: AppTab = .home {
    didSet { activateNoticeArea(selectedTab.noticeArea) }
  }
  private(set) var notice: AppNotice?
  var isSigningOut = false
  var isDeletingAccount = false
  var demoSettings: DemoSettings
  var dataRevision = 0
  let dependencies: AppDependencies
  private(set) var activeNoticeArea: NoticeArea = .authentication
  private let noticeClock: AppNoticeClock
  private var noticeDismissalTask: Task<Void, Never>?
  private var mountedNoticeID: UUID?
  private var noticeRemainingLifetime: TimeInterval?
  private var noticeTimerStartedAt: TimeInterval?
  private var noticeReduceMotion = false

  init(
    store: MockRentivoStore = MockRentivoStore(fixtures: .canonical),
    noticeClock: AppNoticeClock = .continuous
  ) {
    dependencies = .mock(store: store)
    demoSettings = store.demoSettings
    self.noticeClock = noticeClock
  }

  init(dependencies: AppDependencies, noticeClock: AppNoticeClock = .continuous) {
    self.dependencies = dependencies
    self.noticeClock = noticeClock
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

  func updateProfilePIX(_ pix: PixConfiguration?) async throws -> UserProfile {
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
      showNotice(
        "Não foi possível restaurar sua sessão. Entre novamente.",
        kind: .warning,
        owner: .authentication
      )
    }
  }

  var usesLiveAPI: Bool { dependencies.auth.usesLiveAPI }

  func signIn() {
    session = .authenticated(currentUser)
    selectedTab = .home
    showNotice("Bem-vinda à demonstração do Rentivo.", owner: .home)
  }

  // MARK: - Native sign-in
  //
  // These are the app-state half of the native (`/api/v1/auth/mobile/*`) flow the login screen
  // drives.
  //
  // `dependencies.auth` already owns the credential half — every one of these calls persists the
  // bearer token and records the profile as the store's current user before returning (see
  // `MobileAuthRepositoryTests`) — so nothing here re-adopts it; they only move the session,
  // the selected tab, and the notice. Errors propagate to the caller, which owns the screen the
  // user is still looking at; the session is left untouched so a failed attempt keeps them on
  // the form.
  //
  // `mobileLogin` is the only one that can return without a session: its `.mfaRequired` outcome
  // is handed back verbatim so the login screen can present the second factor and finish with
  // one of the completion calls below.

  func signIn(email: String, password: String) async throws -> MobileLoginOutcome {
    let outcome = try await dependencies.auth.mobileLogin(email: email, password: password)
    if case .authenticated(let profile) = outcome { adoptSignedInProfile(profile) }
    return outcome
  }

  func signUp(email: String, password: String) async throws {
    adoptSignedInProfile(try await dependencies.auth.mobileSignup(email: email, password: password))
  }

  func completeTOTP(challenge: MFAChallenge, code: String) async throws {
    adoptSignedInProfile(try await dependencies.auth.verifyTotp(challenge: challenge, code: code))
  }

  func completeRecoveryCode(challenge: MFAChallenge, code: String) async throws {
    adoptSignedInProfile(
      try await dependencies.auth.verifyRecoveryCode(challenge: challenge, code: code))
  }

  func completePasskey(challenge: MFAChallenge, credential: PasskeyAssertionPayload) async throws {
    adoptSignedInProfile(
      try await dependencies.auth.completePasskeyAssertion(
        challenge: challenge, credential: credential))
  }

  /// The state every server-backed sign-in lands on, whichever path produced the profile.
  private func adoptSignedInProfile(_ profile: UserProfile) {
    session = .authenticated(profile)
    selectedTab = .home
    showNotice("Sessão conectada ao Rentivo.", owner: .home)
  }

  func signOut() async {
    guard !isSigningOut else { return }
    // Demo mode has no token to revoke, so it drops straight to local state.
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
      // After `completeSignOut()`, which clears the notice the deletion needs to report.
      showNotice("Sua conta foi excluída.", owner: .authentication)
    } catch {
      showNotice(error.localizedDescription, kind: .warning)
    }
  }

  private func completeSignOut() {
    session = .anonymous
    selectedTab = .home
    activeNoticeArea = .authentication
    dismissNotice()
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

  private func handleSessionExpired() {
    // A deliberate `signOut()` also revokes the token via `liveStore.logout()`, whose POST can
    // itself 401 (the token it's revoking is, after all, about to become invalid) and fire this
    // same notification concurrently. Without this guard that race would flash "Sua sessão
    // expirou" mid-sign-out even though the user chose to sign out, not because the session
    // actually expired out from under them.
    guard !isSigningOut else { return }
    guard case .authenticated = session else { return }
    session = .anonymous
    selectedTab = .home
    showNotice(
      "Sua sessão expirou. Entre novamente para continuar.",
      kind: .warning,
      owner: .authentication
    )
  }

  func showNotice(
    _ message: String,
    kind: AppNotice.Kind = .success,
    owner: NoticeArea? = nil
  ) {
    cancelNoticeTimer()
    mountedNoticeID = nil
    noticeRemainingLifetime = nil
    let animation: Animation = notice == nil
      ? .easeOut(duration: noticeReduceMotion ? 0.15 : 0.22)
      : .easeInOut(duration: 0.15)
    withAnimation(animation) {
      notice = AppNotice(kind: kind, message: message, owner: owner ?? activeNoticeArea)
    }
  }

  func noticeDidMount(id: UUID, voiceOverEnabled: Bool, reduceMotion: Bool = false) {
    guard notice?.id == id, mountedNoticeID != id else { return }
    mountedNoticeID = id
    noticeReduceMotion = reduceMotion
    startNoticeTimer(id: id, duration: voiceOverEnabled ? 8 : 4)
  }

  func dismissNotice(id: UUID? = nil) {
    guard id == nil || notice?.id == id else { return }
    cancelNoticeTimer()
    mountedNoticeID = nil
    noticeRemainingLifetime = nil
    withAnimation(.easeIn(duration: noticeReduceMotion ? 0.15 : 0.16)) {
      notice = nil
    }
  }

  func noticeInteractionBegan(id: UUID) {
    guard notice?.id == id else { return }
    if let startedAt = noticeTimerStartedAt, let remaining = noticeRemainingLifetime {
      noticeRemainingLifetime = max(0, remaining - (noticeClock.now() - startedAt))
    }
    cancelNoticeTimer()
  }

  func noticeInteractionEnded(id: UUID, committed: Bool) {
    guard notice?.id == id else { return }
    if committed {
      dismissNotice(id: id)
    } else {
      startNoticeTimer(id: id, duration: max(noticeRemainingLifetime ?? 1, 1))
    }
  }

  func activateNoticeArea(_ area: NoticeArea) {
    activeNoticeArea = area
    if let notice, notice.owner != area {
      dismissNotice(id: notice.id)
    }
  }

  func sceneDidBecomeInactive() {
    dismissNotice()
  }

  func updateNoticeReduceMotion(_ enabled: Bool) {
    noticeReduceMotion = enabled
  }

  private func startNoticeTimer(id: UUID, duration: TimeInterval) {
    cancelNoticeTimer()
    noticeRemainingLifetime = duration
    noticeTimerStartedAt = noticeClock.now()
    let clock = noticeClock
    noticeDismissalTask = Task { [weak self] in
      do {
        try await clock.sleep(duration)
        try Task.checkCancellation()
        self?.dismissNotice(id: id)
      } catch {
        // Cancellation is the expected result for replacement, manual dismissal, navigation,
        // scene changes, and sign-out. The identity check above protects against custom test
        // clocks that resume an already-cancelled sleep.
      }
    }
  }

  private func cancelNoticeTimer() {
    noticeDismissalTask?.cancel()
    noticeDismissalTask = nil
    noticeTimerStartedAt = nil
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
