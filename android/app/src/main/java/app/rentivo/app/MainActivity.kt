package app.rentivo.app

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.activity.viewModels
import androidx.compose.runtime.CompositionLocalProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.rentivo.data.AppDependencies
import app.rentivo.data.DownloadedFileStore
import app.rentivo.data.ReceiptCaptureStore
import app.rentivo.data.LiveDemoRepository
import app.rentivo.data.api.APIRentivoStore
import app.rentivo.data.api.EncryptedCredentialStore
import app.rentivo.data.api.LiveAPIClient
import app.rentivo.data.api.MobileWebAuthenticator
import app.rentivo.data.api.liveDependencies
import app.rentivo.data.mockDependencies
import app.rentivo.designsystem.RentivoTheme
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow

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

  /**
   * This activity's Custom Tabs launcher. It captures the activity, so it must never outlive it —
   * hence the identity check in [onDestroy] before clearing it off the retained [holder].
   */
  private val customTabsLauncher: (Uri) -> Unit = MobileWebAuthenticator.customTabsLauncher(this)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    // The app renders light-only, so the status bar must always use dark icons — without this the
    // default (light icons) is invisible against the cream background.
    WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = true

    // Publish this instance's launcher before anything can reach the authenticator, which resolves
    // it through the holder on every call rather than capturing one activity forever.
    holder.launchUrl = customTabsLauncher
    val authenticator = holder.ensureAuthenticator()
    val model = holder.appModel { scope ->
      val graph = createAppGraph(applicationContext, useMockData = launchedForUITesting())
      AppModel(
        dependencies = graph.dependencies,
        authenticator = MobileWebAuthenticating(authenticator),
        sessionExpired = graph.sessionExpired,
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

  override fun onDestroy() {
    super.onDestroy()
    // Only retract our own launcher. A recreated activity publishes its own in `onCreate`, and if
    // that has already happened this destroy belongs to the outgoing instance and must not undo it.
    if (holder.launchUrl === customTabsLauncher) holder.launchUrl = null
  }

  /**
   * Mirrors the iOS `#if DEBUG` + `--ui-testing` / `--screenshot-authenticated` check: a shippable
   * build is always live, and a debuggable one only falls back to the mock store when the launch
   * intent explicitly asks for it.
   *
   * ```
   * adb shell am start -n app.rentivo/.app.MainActivity --ez ui-testing true
   * ```
   *
   * The extra is read from the launch intent only, so it cannot be flipped mid-session by a later
   * deep link; the graph is built once per process anyway.
   */
  private fun launchedForUITesting(): Boolean {
    val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    return debuggable && intent?.getBooleanExtra(UI_TESTING_EXTRA, false) == true
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

  /**
   * Opens a URL in a Custom Tab on behalf of the activity that is currently attached, or `null`
   * between one being destroyed and the next publishing its own.
   *
   * This indirection is the whole point of the holder owning it. The authenticator is created once
   * and outlives any single activity, so a launcher captured into it at construction would pin the
   * first activity for the lifetime of the process and, worse, keep launching Custom Tabs from that
   * destroyed instance after a rotation. Resolving the launcher per call instead means the browser
   * always opens from the activity the user is actually looking at.
   */
  var launchUrl: ((Uri) -> Unit)? = null

  /** The browser authenticator, once created. Used for deep-link routing and cancellation. */
  var authenticator: MobileWebAuthenticator? = null
    private set

  fun ensureAuthenticator(): MobileWebAuthenticator =
    authenticator ?: MobileWebAuthenticator(
      launchUrl = { uri ->
        val launch = checkNotNull(launchUrl) {
          "No activity is attached to open the authorization page in a Custom Tab."
        }
        launch(uri)
      },
    ).also { authenticator = it }

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

/** Boolean launch-intent extra selecting the mock store; honoured by debuggable builds only. */
internal const val UI_TESTING_EXTRA = "ui-testing"

/**
 * Name of the cache subdirectory holding downloaded invoices and receipts. It must stay in sync
 * with the `cache-path` entry of `res/xml/file_paths.xml`, or the share sheet cannot grant the
 * receiving app read access to a downloaded file.
 */
private const val DOWNLOADS_DIRECTORY_NAME = "RentivoDownloads"

/**
 * The dependency graph the app runs against, together with the session-expiry stream that belongs
 * to it. The mock graph holds no token that can expire, so its [sessionExpired] is null.
 */
internal class AppGraph(
  val dependencies: AppDependencies,
  val sessionExpired: Flow<Unit>?,
)

/**
 * Builds the dependency graph, mirroring the choice `RentivoApp.init` makes on iOS: release builds
 * are always live; a debuggable build is live too unless it was launched for UI testing, in which
 * case the deterministic mock store stands in for the network (the Android analogue of
 * `--ui-testing` / `--screenshot-authenticated`).
 *
 * The live branch owns the only instances of the credential store, the download store and the API
 * client, so the token, the cache directories the session writes to and the 401 handling all share
 * one lifetime.
 */
internal fun createAppGraph(context: Context, useMockData: Boolean): AppGraph {
  if (useMockData) {
    return AppGraph(dependencies = mockDependencies(), sessionExpired = null)
  }
  val client = LiveAPIClient(
    credentials = EncryptedCredentialStore(context),
    downloads = DownloadedFileStore(File(context.cacheDir, DOWNLOADS_DIRECTORY_NAME)),
    captures = ReceiptCaptureStore(File(context.cacheDir, ReceiptCaptureStore.DIRECTORY_NAME)),
  )
  return AppGraph(
    dependencies = liveDependencies(APIRentivoStore(client), LiveDemoRepository()),
    sessionExpired = client.sessionExpired,
  )
}
