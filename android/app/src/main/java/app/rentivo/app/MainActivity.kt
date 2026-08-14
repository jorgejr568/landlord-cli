package app.rentivo.app

import android.content.Context
import android.content.pm.ApplicationInfo
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
 * graph and publishes it to the tree. Sign-in is entirely native (e-mail/password + in-app MFA and
 * passkeys through the Credential Manager), so there is no browser handoff, no Custom Tab, and no
 * `rentivo://auth` deep link to route. Everything below this file — including [AppModel] — is plain
 * JVM code covered by unit tests.
 */
class MainActivity : ComponentActivity() {

  private val holder: AppModelHolder by viewModels()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)

    // The app renders light-only, so the status bar must always use dark icons — without this the
    // default (light icons) is invisible against the cream background.
    WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = true

    val model = holder.appModel { scope ->
      val graph = createAppGraph(applicationContext, useMockData = launchedForUITesting())
      AppModel(
        dependencies = graph.dependencies,
        sessionExpired = graph.sessionExpired,
        scope = scope,
      )
    }

    setContent {
      RentivoTheme {
        CompositionLocalProvider(LocalAppModel provides model) {
          RootView()
        }
      }
    }
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
   * The extra is read from the launch intent only; the graph is built once per process anyway.
   */
  private fun launchedForUITesting(): Boolean {
    val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    return debuggable && intent?.getBooleanExtra(UI_TESTING_EXTRA, false) == true
  }
}

/**
 * Keeps the app model alive across configuration changes, so the session, selected tab and any
 * pending sign-in survive. The iOS `@State` app model gets this from the SwiftUI `App` lifetime; on
 * Android a `ViewModel` is the equivalent scope.
 */
internal class AppModelHolder : ViewModel() {

  private var model: AppModel? = null

  fun appModel(build: (CoroutineScope) -> AppModel): AppModel =
    model ?: build(viewModelScope).also { model = it }
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
