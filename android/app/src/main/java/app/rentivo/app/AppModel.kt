package app.rentivo.app

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import app.rentivo.data.AppDependencies
import app.rentivo.data.DemoSettings
import app.rentivo.domain.DemoError
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.UserProfile
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch

/**
 * The browser leg of authentication, as `AppModel` needs it.
 *
 * `MobileWebAuthenticator` — the production implementation — is bound to Custom Tabs and
 * `android.net.Uri`, so `AppModel` talks to this pure-JVM seam instead. `MainActivity` adapts the
 * real authenticator onto it (see `MobileWebAuthenticating`), and unit tests substitute a fake.
 * The iOS `AppModel` owns its `MobileWebAuthenticator` directly because `ASWebAuthenticationSession`
 * needs no such split.
 */
interface WebAuthenticating {

  /** Opens the login page and returns the one-time authorization code. */
  suspend fun authorize(): String

  /** Opens the logout page, clearing the shared browser session. */
  suspend fun logout()

  /**
   * Whether [throwable] is the user dismissing the browser rather than a real failure. Cancellation
   * is an expected outcome that callers stay silent about.
   */
  fun isUserCancellation(throwable: Throwable): Boolean
}

/**
 * App-wide session, navigation and notice state. Port of `ios/Rentivo/App/AppModel.swift`.
 *
 * The iOS type is an `@Observable @MainActor` class; the Compose equivalent is a plain state holder
 * whose properties are `mutableStateOf`-backed, created once by `MainActivity` and published to the
 * tree through [LocalAppModel]. Every mutation therefore happens on the main thread, matching the
 * `@MainActor` isolation.
 *
 * @param dependencies the 17 repositories every screen resolves through.
 * @param authenticator browser-backed sign-in/sign-out; `null` in demo builds, which never use it.
 * @param sessionExpired fires when `LiveAPIClient` sees a 401 for the stored token (the analog of
 *   the iOS `liveAPIClientSessionExpired` notification). Only collected for live dependencies.
 * @param scope the app model's own lifetime, outliving any one screen. It carries the session-expiry
 *   subscription and the session-ending flows ([signOut], [deleteAccount]), which must survive the
 *   screen that started them disappearing.
 */
@Stable
class AppModel(
  val dependencies: AppDependencies,
  private val authenticator: WebAuthenticating? = null,
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

  suspend fun signInWithWebAuthorization() {
    // Demo mode has no server to authorize against, so it takes the local sign-in shortcut instead
    // of opening a browser sheet.
    if (!dependencies.auth.usesLiveAPI) {
      signIn()
      return
    }
    val browser = requireNotNull(authenticator) {
      "Live dependencies require a WebAuthenticating to sign in through the browser."
    }
    val code = browser.authorize()
    session = Session.Authenticated(dependencies.auth.exchangeMobileAuthorization(code = code))
    selectedTab = AppTab.HOME
    notice = AppNotice(kind = AppNotice.Kind.SUCCESS, message = "Sessão conectada ao Rentivo.")
  }

  /**
   * Signs out, ending on the anonymous screen.
   *
   * Deliberately not a `suspend` function. Its very first effect — [completeSignOut] — removes the
   * account screen that started it from composition, which cancels that screen's
   * `rememberCoroutineScope()`; anything still awaited at that point (here, the trailing browser
   * logout) would be cancelled somewhere between "always runs" and "never runs" depending on frame
   * timing. Running the sequence on the app model's own scope, which lives as long as the session
   * does, makes the whole thing complete regardless of what happens to the caller. Callers keep
   * working unchanged: invoking a non-suspending function inside `scope.launch { … }` is fine.
   */
  fun signOut() {
    if (isSigningOut) return
    // Demo mode has neither a token to revoke nor a browser session to close, so it drops straight
    // to local state — synchronously, with no scope involved and no in-flight flag to toggle.
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
        // still honors the old token, nor stuck signed in locally because a later step failed.
        dependencies.auth.logout()
        completeSignOut()
        // The browser-cookie logout is best-effort and must never block sign-out (which already
        // happened above). Cancelling that sheet is an expected, silent outcome, not a failure
        // worth reporting.
        val browser = authenticator ?: return@launch
        try {
          browser.logout()
        } catch (cancellation: CancellationException) {
          throw cancellation
        } catch (throwable: Throwable) {
          if (browser.isUserCancellation(throwable)) return@launch
          notice = AppNotice(
            kind = AppNotice.Kind.WARNING,
            message = "Você saiu do Rentivo, mas não foi possível encerrar a sessão do navegador.",
          )
        }
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
