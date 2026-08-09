package app.rentivo.data.api

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * `LiveAPIClient.defaultClient()` caching policy.
 *
 * OkHttp installs no response cache unless one is configured, and this asserts the app never
 * acquires one by accident: authenticated responses must not be written into the app's storage as
 * a side effect of the transport, and a cached "pending" `pdf_render_status` would make the render
 * poll re-read its own answer instead of the network. Adapted from the iOS suite, which asserts
 * the equivalent `URLCache`/`reloadIgnoringLocalCacheData` configuration.
 */
class LiveAPIClientCachingTest {

  private val server = MockWebServer()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
  }

  @Test
  fun `the app client stores nothing in a response cache`() {
    assertNull(LiveAPIClient.defaultClient().cache)
  }

  @Test
  fun `the app client keeps the timeout behavior it was created for`() {
    val client = LiveAPIClient.defaultClient()

    assertEquals(30_000, client.connectTimeoutMillis)
    assertEquals(30_000, client.readTimeoutMillis)
    assertEquals(30_000, client.writeTimeoutMillis)
    assertEquals(30_000, client.callTimeoutMillis)
  }

  @Test
  fun `every authenticated request asks intermediaries not to store it`() = runTest {
    val dispatcher = server.routeWithSession { jsonResponse("""{"items":[],"stats":{}}""") }
    val client = liveClient(server)
    client.restoreSession()

    runCatching { client.request(path = "/api/v1/billings") }

    assertEquals(
      listOf("no-store", "no-store"),
      dispatcher.calls.map { it.headers["Cache-Control"] },
    )
  }
}
