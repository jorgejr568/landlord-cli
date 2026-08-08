package app.rentivo.data.api

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred

/**
 * Drives the browser leg of authentication through Chrome Custom Tabs.
 *
 * Port of the iOS `MobileWebAuthenticator`, which uses `ASWebAuthenticationSession`. Android has no
 * equivalent all-in-one session type, so the round trip is split in two halves:
 *
 * 1. [authorize] / [logout] mint a fresh state, hand the URL to the injected launcher, and suspend.
 * 2. The website redirects to `rentivo://auth/…`, Android delivers it to the activity declaring the
 *    deep-link filter, and that activity forwards it to [handleCallback], which resumes the caller.
 *
 * Session sharing parity: iOS sets `prefersEphemeralWebBrowserSession = false` so login and logout
 * run against the same cookie jar as the website. Custom Tabs share the user's browser profile by
 * default, so the same behaviour holds here with no extra configuration.
 *
 * All protocol logic lives in [MobileWebAuthenticationFlow]; this class stays deliberately thin
 * because it cannot be covered by JVM unit tests.
 *
 * @param launchUrl opens the URL in a Custom Tab. [customTabsLauncher] builds the production one;
 *   the app shell injects it so this class never captures an activity itself.
 * @param baseUrl origin serving the authorization pages.
 */
class MobileWebAuthenticator(
  private val launchUrl: (Uri) -> Unit,
  private val baseUrl: String = MobileWebAuthenticationFlow.PRODUCTION_BASE_URL,
) {

  private enum class Kind {
    AUTHORIZE,
    LOGOUT,
  }

  private class PendingFlow(
    val kind: Kind,
    val state: String,
    val result: CompletableDeferred<String>,
  )

  private val lock = Any()
  private var pending: PendingFlow? = null

  /**
   * Opens the login page and suspends until the browser redirects back, returning the one-time
   * authorization code.
   *
   * @throws UserCancelledException when [cancelPending] runs first, i.e. the user dismissed the
   *   Custom Tab without completing the flow.
   * @throws MobileWebAuthenticationException when the callback does not carry a usable code for
   *   this attempt's state.
   */
  suspend fun authorize(): String = perform(Kind.AUTHORIZE)

  /**
   * Opens the logout page and suspends until the browser confirms, clearing the shared browser
   * session. Throws under the same conditions as [authorize].
   */
  suspend fun logout() {
    perform(Kind.LOGOUT)
  }

  /**
   * Consumes a `rentivo://auth/…` deep link, resuming whoever is waiting in [authorize] or
   * [logout]. The app shell calls this from `onCreate`/`onNewIntent` for every incoming data URI.
   *
   * Returns `true` when the URI belonged to this flow and was consumed — including when it was
   * rejected for a state, path or code mismatch, which fails the pending call with
   * [MobileWebAuthenticationException] exactly as the iOS session does. Returns `false` for URIs
   * outside `rentivo://auth` and for callbacks arriving with nothing in flight, so the caller may
   * route them elsewhere.
   */
  fun handleCallback(uri: Uri): Boolean {
    val raw = uri.toString()
    if (!MobileWebAuthenticationFlow.isCallbackUri(raw)) return false
    val flow = synchronized(lock) { pending } ?: return false
    val value = when (flow.kind) {
      Kind.AUTHORIZE -> MobileWebAuthenticationFlow.authorizationCode(raw, flow.state)
      Kind.LOGOUT ->
        if (MobileWebAuthenticationFlow.isLogoutCallback(raw, flow.state)) "" else null
    }
    if (value == null) {
      flow.result.completeExceptionally(MobileWebAuthenticationException())
    } else {
      flow.result.complete(value)
    }
    clear(flow)
    return true
  }

  /**
   * Abandons the in-flight flow, failing [authorize]/[logout] with [UserCancelledException].
   *
   * The app shell calls this when the activity resumes without a callback having arrived — the user
   * came back from the Custom Tab by pressing back or closing it. Returns `true` when something was
   * actually pending, so the shell can tell a real cancellation from a redundant call (in
   * particular, the resume that immediately follows a successful callback).
   */
  fun cancelPending(): Boolean {
    val flow = synchronized(lock) { pending } ?: return false
    flow.result.completeExceptionally(UserCancelledException())
    clear(flow)
    return true
  }

  private suspend fun perform(kind: Kind): String {
    val state = UUID.randomUUID().toString()
    val flow = PendingFlow(kind, state, CompletableDeferred())
    val url = when (kind) {
      Kind.AUTHORIZE -> MobileWebAuthenticationFlow.authorizationUrl(baseUrl, state)
      Kind.LOGOUT -> MobileWebAuthenticationFlow.logoutUrl(baseUrl, state)
    }
    synchronized(lock) {
      // A second attempt supersedes whatever was still waiting; the old caller sees a cancellation
      // rather than hanging forever on a callback that will never be routed to it.
      pending?.result?.completeExceptionally(UserCancelledException())
      pending = flow
    }
    try {
      launchUrl(Uri.parse(url))
    } catch (throwable: Throwable) {
      clear(flow)
      throw throwable
    }
    return try {
      flow.result.await()
    } finally {
      clear(flow)
    }
  }

  private fun clear(flow: PendingFlow) {
    synchronized(lock) { if (pending === flow) pending = null }
  }

  companion object {
    /**
     * Whether [throwable] is the user walking away from the browser rather than a real failure.
     * Shared by `AppModel` (best-effort browser logout) and the login screen, which stays silent
     * for expected cancellations instead of showing an error.
     */
    fun isUserCancellation(throwable: Throwable): Boolean = throwable is UserCancelledException

    /** The production launcher: opens [Uri] in a Custom Tab hosted by [context]. */
    fun customTabsLauncher(context: Context): (Uri) -> Unit = { uri ->
      CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, uri)
    }
  }
}

/** Raised when the browser flow is abandoned before a callback arrives. */
class UserCancelledException : Exception("Autenticação cancelada.")
