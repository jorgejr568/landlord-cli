package app.rentivo.data.api

import app.rentivo.data.DownloadedFileStore
import app.rentivo.data.ReceiptCaptureStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.onSubscription
import kotlinx.coroutines.launch
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import java.nio.file.Files
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Shared MockWebServer plumbing for the live API suites. It replaces the stubbed `URLProtocol`
 * subclasses the iOS tests use: one dispatcher per test, routing on `METHOD path` and recording
 * every request so the encoding assertions can read the exact bytes that went out.
 */

internal const val SESSION_BODY =
  """{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"""

internal class CapturedCall(
  val method: String,
  val path: String,
  val body: ByteArray,
  val headers: Headers,
) {
  val bodyText: String get() = body.decodeToString()
  val route: String get() = "$method $path"
}

internal class RouteDispatcher(private val handler: (CapturedCall) -> MockResponse) : Dispatcher() {
  private val recorded = CopyOnWriteArrayList<CapturedCall>()

  val calls: List<CapturedCall> get() = recorded

  val routes: List<String> get() = recorded.map { it.route }

  override fun dispatch(request: RecordedRequest): MockResponse {
    val call = CapturedCall(
      method = request.method.orEmpty(),
      path = request.path.orEmpty().substringBefore("?"),
      body = request.body.readByteArray(),
      headers = request.headers,
    )
    recorded += call
    return handler(call)
  }

  fun callTo(route: String): CapturedCall? = recorded.lastOrNull { it.route == route }

  fun bodyOf(route: String): String =
    checkNotNull(callTo(route)) { "No request captured for $route (saw $routes)" }.bodyText
}

internal fun jsonResponse(body: String, code: Int = 200): MockResponse = MockResponse()
  .setResponseCode(code)
  .setHeader("Content-Type", "application/json")
  .setBody(body)

/** Routes every request through [handler], answering the session bootstrap on its own. */
internal fun MockWebServer.routeWithSession(
  handler: (CapturedCall) -> MockResponse,
): RouteDispatcher = route { call ->
  if (call.path == "/api/v1/auth/session") jsonResponse(SESSION_BODY) else handler(call)
}

internal fun MockWebServer.route(handler: (CapturedCall) -> MockResponse): RouteDispatcher {
  val routeDispatcher = RouteDispatcher(handler)
  dispatcher = routeDispatcher
  return routeDispatcher
}

internal fun unexpected(call: CapturedCall): MockResponse =
  jsonResponse("""{"detail":"Endpoint inesperado: ${call.route}"}""", code = 500)

/**
 * Its own downloads directory per test: the tests that reach `logout()`/`invalidateSession()`
 * purge the whole directory, and JUnit may run classes in any order.
 */
internal fun makeIsolatedDownloadsStore(): DownloadedFileStore =
  DownloadedFileStore(Files.createTempDirectory("rentivo-downloads").toFile())

/** Its own captures directory per test, for the same reason as [makeIsolatedDownloadsStore]. */
internal fun makeIsolatedCapturesStore(): ReceiptCaptureStore =
  ReceiptCaptureStore(Files.createTempDirectory("rentivo-captures").toFile())

/**
 * Watches [LiveAPIClient.sessionExpired] from a real dispatcher.
 *
 * The flow has no replay, so the collector must be subscribed *before* the call that expires the
 * session; and the waits below are wall-clock rather than `withTimeout`, because `runTest`'s
 * virtual clock would otherwise fire a timeout while the request is blocked on real socket I/O.
 */
internal class SessionExpiryProbe(client: LiveAPIClient) {
  private val scope = CoroutineScope(Dispatchers.Default)
  private val subscribed = CompletableDeferred<Unit>()
  private val signal = CompletableDeferred<Unit>()

  init {
    scope.launch {
      client.sessionExpired.onSubscription { subscribed.complete(Unit) }.first()
      signal.complete(Unit)
    }
    waitUntil(TIMEOUT_MILLIS) { subscribed.isCompleted }
    check(subscribed.isCompleted) { "Collector never subscribed" }
  }

  fun emitted(timeoutMillis: Long = TIMEOUT_MILLIS): Boolean {
    waitUntil(timeoutMillis) { signal.isCompleted }
    return signal.isCompleted
  }

  /** Answers whether anything was emitted within [quietMillis], for the "must stay silent" cases. */
  fun stayedSilent(quietMillis: Long = 200): Boolean {
    waitUntil(quietMillis) { signal.isCompleted }
    return !signal.isCompleted
  }

  fun close() {
    scope.cancel()
  }

  private fun waitUntil(timeoutMillis: Long, condition: () -> Boolean) {
    val deadline = System.currentTimeMillis() + timeoutMillis
    while (!condition() && System.currentTimeMillis() < deadline) Thread.sleep(5)
  }

  private companion object {
    const val TIMEOUT_MILLIS = 5_000L
  }
}

internal fun liveClient(
  server: MockWebServer,
  credentials: CredentialStore = MemoryCredentialStore(token = "stored-token"),
  downloads: DownloadedFileStore = makeIsolatedDownloadsStore(),
  captures: ReceiptCaptureStore = makeIsolatedCapturesStore(),
  okHttp: OkHttpClient = LiveAPIClient.defaultClient(),
): LiveAPIClient = LiveAPIClient(
  baseUrl = server.url("/"),
  credentials = credentials,
  downloads = downloads,
  captures = captures,
  client = okHttp,
)
