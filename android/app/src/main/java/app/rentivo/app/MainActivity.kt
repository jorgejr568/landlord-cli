package app.rentivo.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.CompositionLocalProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.rentivo.data.AppDependencies
import app.rentivo.data.api.MobileWebAuthenticator
import app.rentivo.data.mockDependencies
import app.rentivo.designsystem.RentivoTheme
import kotlinx.coroutines.CoroutineScope

/**
 * The single activity hosting the Compose app shell. Port of `ios/Rentivo/App/RentivoApp.swift`.
 *
 * This is deliberately the only Android-coupled file in the app shell: it builds the dependency
 * graph, adapts `MobileWebAuthenticator` onto the pure-JVM [WebAuthenticating] seam, and routes
 * `rentivo://auth/…` deep links back into the pending browser flow. Everything below it — including
 * [AppModel] — is plain JVM code covered by unit tests.
 */
class MainActivity : ComponentActivity() {

  private val holder: AppModelHolder by viewModels()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    val authenticator = holder.ensureAuthenticator(MobileWebAuthenticator.customTabsLauncher(this))
    val model = holder.appModel { scope ->
      AppModel(
        dependencies = createAppDependencies(applicationContext),
        authenticator = MobileWebAuthenticating(authenticator),
        // TODO(live-wiring): pass `client.sessionExpired` once the live API layer exists. The demo
        // store has no token that can expire, so there is nothing to collect yet.
        sessionExpired = null,
        scope = scope,
      )
    }

    // A cold start can already carry the callback for a flow begun before the process was
    // recreated; a warm one arrives through `onNewIntent`.
    consumeAuthCallback(intent)

    setContent {
      RentivoTheme {
        CompositionLocalProvider(LocalAppModel provides model) {
          RootView()
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    consumeAuthCallback(intent)
  }

  override fun onResume() {
    super.onResume()
    // Resuming with a flow still pending means the user dismissed the Custom Tab without finishing;
    // a callback that already arrived cleared the flow, so this is a no-op in the happy path.
    holder.authenticator?.cancelPending()
  }

  private fun consumeAuthCallback(intent: Intent?) {
    val uri = intent?.data ?: return
    if (holder.authenticator?.handleCallback(uri) == true) {
      // Clear the URI so a later resume or recreation cannot replay it against a different flow.
      intent.data = null
    }
  }
}

/**
 * Keeps the app model and the in-flight browser flow alive across configuration changes, so the
 * session, selected tab and any pending authorization survive. The iOS `@State` app model gets this
 * from the SwiftUI `App` lifetime; on Android a `ViewModel` is the equivalent scope.
 */
internal class AppModelHolder : ViewModel() {

  private var model: AppModel? = null

  /** The browser authenticator, once created. Used for deep-link routing and cancellation. */
  var authenticator: MobileWebAuthenticator? = null
    private set

  fun ensureAuthenticator(launchUrl: (Uri) -> Unit): MobileWebAuthenticator =
    authenticator ?: MobileWebAuthenticator(launchUrl = launchUrl).also { authenticator = it }

  fun appModel(build: (CoroutineScope) -> AppModel): AppModel =
    model ?: build(viewModelScope).also { model = it }
}

/** Adapts the Custom Tabs authenticator onto the pure-JVM seam `AppModel` depends on. */
private class MobileWebAuthenticating(
  private val delegate: MobileWebAuthenticator,
) : WebAuthenticating {

  override suspend fun authorize(): String = delegate.authorize()

  override suspend fun logout() {
    delegate.logout()
  }

  override fun isUserCancellation(throwable: Throwable): Boolean =
    MobileWebAuthenticator.isUserCancellation(throwable)
}

/**
 * Builds the dependency graph the app runs against.
 *
 * iOS picks between `.live()` and the mock store in `RentivoApp.init`: release builds are always
 * live, debug builds are live unless launched with `--ui-testing`. The Android equivalent reads the
 * same seam here once the API layer lands:
 *
 * ```
 * val credentials = EncryptedCredentialStore(context)
 * val downloads = DownloadedFileStore(context.cacheDir)
 * val client = LiveAPIClient(credentials = credentials, downloads = downloads)
 * return liveDependencies(APIRentivoStore(client))
 * ```
 *
 * TODO(live-wiring): swap in the above once `APIRentivoStore`/`liveDependencies` exist, keeping the
 * demo store for the `ui-testing` launch flag. Until then the demo store is the only option, which
 * keeps the shell runnable and screenshot-testable exactly as `--ui-testing` does on iOS.
 */
internal fun createAppDependencies(context: Context): AppDependencies = mockDependencies()
