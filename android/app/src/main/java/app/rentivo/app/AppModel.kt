package app.rentivo.app

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import app.rentivo.data.AppDependencies
import app.rentivo.data.DemoSettings
import app.rentivo.domain.DemoError
import app.rentivo.domain.MFAChallenge
import app.rentivo.domain.MobileLoginOutcome
import app.rentivo.domain.PasskeyAssertionPayload
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.UserProfile
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * App-wide session, navigation and notice state. Port of `ios/Rentivo/App/AppModel.swift`.
 *
 * The iOS type is an `@Observable @MainActor` class; the Compose equivalent is a plain state holder
 * whose properties are `mutableStateOf`-backed, created once by `MainActivity` and published to the
 * tree through [LocalAppModel]. Every mutation therefore happens on the main thread, matching the
 * `@MainActor` isolation.
 *
 * @param dependencies the 17 repositories every screen resolves through.
 * @param sessionExpired fires when `LiveAPIClient` sees a 401 for the stored token (the analog of
 *   the iOS `liveAPIClientSessionExpired` notification). Only collected for live dependencies.
 * @param scope the app model's own lifetime, outliving any one screen. It carries the session-expiry
 *   subscription and the session-ending flows ([signOut], [deleteAccount]), which must survive the
 *   screen that started them disappearing.
 */
@Stable
class AppModel(
  val dependencies: AppDependencies,
  sessionExpired: Flow<Unit>? = null,
  private val scope: CoroutineScope,
) {

  sealed interface Session {
    data object Restoring : Session

    data object Anonymous : Session

    data class Authenticated(val profile: UserProfile) : Session
  }

  var session: Session by mutableStateOf(Session.Anonymous)

  var selectedTab: AppTab by mutableStateOf(AppTab.HOME)

  var notice: AppNotice? by mutableStateOf(null)

  var isSigningOut: Boolean by mutableStateOf(false)

  var isDeletingAccount: Boolean by mutableStateOf(false)

  var demoSettings: DemoSettings by mutableStateOf(dependencies.demo.demoSettings)

  var dataRevision: Int by mutableStateOf(0)

  init {
    if (dependencies.auth.usesLiveAPI) {
      session = Session.Restoring
      observeSessionExpiry(sessionExpired)
    }
  }

  val currentUser: UserProfile
    get() = (session as? Session.Authenticated)?.profile ?: dependencies.auth.currentUser

  val isAuthenticated: Boolean
    get() = session is Session.Authenticated

  val usesLiveAPI: Boolean
    get() = dependencies.auth.usesLiveAPI

  suspend fun loadProfile(): UserProfile {
    val profile = dependencies.profile.profile()
    if (session is Session.Authenticated) {
      session = Session.Authenticated(profile)
    }
    return profile
  }

  suspend fun updateProfilePIX(pix: PixConfiguration): UserProfile {
    val profile = dependencies.profile.updatePix(pix)
    if (session is Session.Authenticated) {
      session = Session.Authenticated(profile)
    }
    return profile
  }

  suspend fun restoreSessionIfNeeded() {
    // Only a live-API session ever starts out `Restoring` (see `init`), so the demo store returns
    // here before its `restoreSession()` — which has nothing to restore — runs.
    if (session !is Session.Restoring) return
    session = try {
      dependencies.auth.restoreSession()?.let(Session::Authenticated) ?: Session.Anonymous
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (throwable: Throwable) {
      notice = AppNotice(
        kind = AppNotice.Kind.WARNING,
        message = "Não foi possível restaurar sua sessão. Entre novamente.",
      )
      Session.Anonymous
    }
  }

  fun signIn() {
    session = Session.Authenticated(currentUser)
    selectedTab = AppTab.HOME
    notice = AppNotice(
      kind = AppNotice.Kind.SUCCESS,
      message = "Bem-vinda à demonstração do Rentivo.",
    )
  }

  // MARK: - Native sign-in
  //
  // These are the app-state half of the native (`/api/v1/auth/mobile/*`) flow the login screen
  // drives. `dependencies.auth` already owns the credential half — every one of these calls
  // persists the bearer token and records the profile as the store's current user before returning
  // — so nothing here re-adopts it; they only move the session, the selected tab, and the notice.
  // Errors propagate to the caller, which owns the screen the user is still looking at; the session
  // is left untouched so a failed attempt keeps them on the form.
  //
  // `signIn` is the only one that can return without a session: its `MfaRequired` outcome is handed
  // back verbatim so the login screen can present the second factor and finish with one of the
  // completion calls below.

  suspend fun signIn(email: String, password: String): MobileLoginOutcome {
    val outcome = dependencies.auth.mobileLogin(email = email, password = password)
    if (outcome is MobileLoginOutcome.Authenticated) adoptSignedInProfile(outcome.profile)
    return outcome
  }

  suspend fun signUp(email: String, password: String) {
    adoptSignedInProfile(dependencies.auth.mobileSignup(email = email, password = password))
  }

  suspend fun completeTOTP(challenge: MFAChallenge, code: String) {
    adoptSignedInProfile(dependencies.auth.verifyTotp(challenge = challenge, code = code))
  }

  suspend fun completeRecoveryCode(challenge: MFAChallenge, code: String) {
    adoptSignedInProfile(dependencies.auth.verifyRecoveryCode(challenge = challenge, code = code))
  }

  suspend fun completePasskey(challenge: MFAChallenge, credential: PasskeyAssertionPayload) {
    adoptSignedInProfile(
      dependencies.auth.completePasskeyAssertion(challenge = challenge, credential = credential)
    )
  }

  /** The state every server-backed sign-in lands on, whichever path produced the profile. */
  private fun adoptSignedInProfile(profile: UserProfile) {
    session = Session.Authenticated(profile)
    selectedTab = AppTab.HOME
    notice = AppNotice(kind = AppNotice.Kind.SUCCESS, message = "Sessão conectada ao Rentivo.")
  }

  /**
   * Signs out, ending on the anonymous screen.
   *
   * Deliberately not a `suspend` function. Its very first effect — [completeSignOut] — removes the
   * account screen that started it from composition, which cancels that screen's
   * `rememberCoroutineScope()`; the token revocation still in flight at that point would be
   * cancelled somewhere between "always runs" and "never runs" depending on frame timing. Running
   * the sequence on the app model's own scope, which lives as long as the session does, makes it
   * complete regardless of what happens to the caller. Callers keep working unchanged: invoking a
   * non-suspending function inside `scope.launch { … }` is fine.
   */
  fun signOut() {
    if (isSigningOut) return
    // Demo mode has no token to revoke, so it drops straight to local state — synchronously, with
    // no scope involved and no in-flight flag to toggle.
    if (!dependencies.auth.usesLiveAPI) {
      completeSignOut()
      return
    }
    // Claimed here rather than inside the coroutine so that a second tap arriving in the same frame
    // is rejected by the guard above instead of starting a competing sign-out.
    isSigningOut = true
    scope.launch {
      try {
        // Revoke the API token first (best-effort inside `logout()`), then unconditionally drop
        // local credentials/state: the user must never end up "signed out" locally while the server
        // still honors the old token, nor stuck signed in locally because a later step failed. With
        // native sign-in there is no browser session to close afterwards.
        dependencies.auth.logout()
        completeSignOut()
      } finally {
        isSigningOut = false
      }
    }
  }

  /** Deletes the account and signs out. Runs on the app model's scope, for the reasons in [signOut]. */
  fun deleteAccount(password: String) {
    if (isDeletingAccount) return
    // There is no demo account to delete, so demo mode just returns to the signed-out screen
    // without claiming a deletion happened.
    if (!dependencies.auth.usesLiveAPI) {
      completeSignOut()
      return
    }
    isDeletingAccount = true
    scope.launch {
      try {
        dependencies.auth.deleteAccount(password = password)
        completeSignOut()
        notice = AppNotice(kind = AppNotice.Kind.SUCCESS, message = "Sua conta foi excluída.")
      } catch (cancellation: CancellationException) {
        throw cancellation
      } catch (throwable: Throwable) {
        notice = AppNotice(
          kind = AppNotice.Kind.WARNING,
          message = DemoError.from(throwable).message,
        )
      } finally {
        isDeletingAccount = false
      }
    }
  }

  private fun completeSignOut() {
    session = Session.Anonymous
    selectedTab = AppTab.HOME
    notice = null
  }

  /**
   * Reacts to `LiveAPIClient` reporting that the stored token is no longer valid (a 401 during a
   * background/foreground request), which otherwise leaves the app "authenticated" while every
   * screen keeps failing until relaunch. This subscription lives for the lifetime of the app model.
   */
  private fun observeSessionExpiry(sessionExpired: Flow<Unit>?) {
    val expiries = sessionExpired ?: return
    scope.launch { expiries.collect { handleSessionExpired() } }
  }

  private fun handleSessionExpired() {
    // A deliberate `signOut()` also revokes the token via the live store's `logout()`, whose POST
    // can itself 401 (the token it's revoking is, after all, about to become invalid) and emit this
    // same event concurrently. Without this guard that race would flash "Sua sessão expirou"
    // mid-sign-out even though the user chose to sign out, not because the session actually expired
    // out from under them.
    if (isSigningOut) return
    if (session !is Session.Authenticated) return
    session = Session.Anonymous
    selectedTab = AppTab.HOME
    notice = AppNotice(
      kind = AppNotice.Kind.WARNING,
      message = "Sua sessão expirou. Entre novamente para continuar.",
    )
  }

  fun showNotice(message: String, kind: AppNotice.Kind = AppNotice.Kind.SUCCESS) {
    notice = AppNotice(kind = kind, message = message)
  }

  fun setDelayEnabled(enabled: Boolean) {
    dependencies.demo.setDelayEnabled(enabled)
    refreshDemoState(reloadContent = false)
  }

  fun setEmptyMode(enabled: Boolean) {
    dependencies.demo.setEmptyMode(enabled)
    refreshDemoState(reloadContent = true)
  }

  fun setViewerMode(enabled: Boolean) {
    dependencies.demo.setViewerMode(enabled)
    refreshDemoState(reloadContent = true)
  }

  fun failNextOperation() {
    dependencies.demo.failNextOperation()
  }

  fun resetDemo() {
    dependencies.demo.reset()
    refreshDemoState(reloadContent = true)
  }

  private fun refreshDemoState(reloadContent: Boolean) {
    demoSettings = dependencies.demo.demoSettings
    if (reloadContent) dataRevision += 1
  }
}

/**
 * The one [AppModel] for the whole tree, provided by `MainActivity`.
 *
 * Screens read it with `val app = LocalAppModel.current` — the Compose analog of the iOS
 * `@Environment(AppModel.self)` — and reload themselves on demo-data changes with
 * `LaunchedEffect(app.dataRevision) { load() }`.
 */
val LocalAppModel = staticCompositionLocalOf<AppModel> {
  error("LocalAppModel was read outside of the app shell; provide it from MainActivity.")
}
