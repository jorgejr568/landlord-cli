package app.rentivo.data.api

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The 401-during-a-request path: a token that expired server-side after login must clear every
 * trace of the session locally and surface as [LiveAPIError.SessionExpired], never as a generic
 * failure the caller would offer to retry.
 */
class SessionExpiryTest {

  private val server = MockWebServer()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
  }

  /** Authenticates once, then 401s every other path. */
  private fun expiringRoutes(): MockWebServer = server.apply {
    routeWithSession { jsonResponse("""{"detail":"Sessão expirada."}""", code = 401) }
  }

  @Test
  fun `a 401 clears the stored credential and throws session expired`() = runTest {
    val credentials = MemoryCredentialStore(token = "stored-token")
    val client = liveClient(expiringRoutes(), credentials = credentials)
    assertNotNull(client.restoreSession())
    assertEquals("stored-token", credentials.readAccessToken())

    val error = runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull()

    assertEquals(LiveAPIError.SessionExpired, error)
    assertNull(credentials.readAccessToken())
  }

  @Test
  fun `a 401 during a download clears the credential and throws session expired`() = runTest {
    val credentials = MemoryCredentialStore(token = "stored-token")
    val client = liveClient(expiringRoutes(), credentials = credentials)
    assertNotNull(client.restoreSession())

    val error = runCatching {
      client.download(path = "/api/v1/billings/b/bills/1/invoice", filename = "fatura")
    }.exceptionOrNull()

    assertEquals(LiveAPIError.SessionExpired, error)
    assertNull(credentials.readAccessToken())
  }

  @Test
  fun `a request without a token throws session expired before touching the network`() = runTest {
    val dispatcher = server.route { jsonResponse(SESSION_BODY) }
    val client = liveClient(server, credentials = MemoryCredentialStore())

    val error = runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull()

    assertEquals(LiveAPIError.SessionExpired, error)
    assertEquals(emptyList<String>(), dispatcher.routes)
  }

  @Test
  fun `a 401 announces the expiry so the app shell can sign out`() = runTest {
    val client = liveClient(expiringRoutes(), credentials = MemoryCredentialStore("stored-token"))
    assertNotNull(client.restoreSession())
    val probe = SessionExpiryProbe(client)

    runCatching { client.request(path = "/api/v1/billings") }

    assertTrue(probe.emitted())
    probe.close()
  }

  @Test
  fun `a deliberate sign-out announces nothing`() = runTest {
    server.routeWithSession { MockResponse().setResponseCode(204) }
    val client = liveClient(server, credentials = MemoryCredentialStore("stored-token"))
    assertNotNull(client.restoreSession())
    val probe = SessionExpiryProbe(client)

    client.logout()

    assertTrue(probe.stayedSilent())
    probe.close()
  }

  @Test
  fun `signing out drops the in-memory token so later calls fail closed`() = runTest {
    val credentials = MemoryCredentialStore(token = "stored-token")
    server.routeWithSession { MockResponse().setResponseCode(204) }
    val client = liveClient(server, credentials = credentials)
    assertNotNull(client.restoreSession())

    client.logout()

    assertNull(credentials.readAccessToken())
    assertEquals(
      LiveAPIError.SessionExpired,
      runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull(),
    )
  }
}
