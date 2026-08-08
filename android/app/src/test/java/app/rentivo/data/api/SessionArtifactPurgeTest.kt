package app.rentivo.data.api

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Purging what a session left on disk. Each test injects its own downloads directory, because
 * these are the tests that actually call `purge()` on a real one.
 */
class SessionArtifactPurgeTest {

  private val server = MockWebServer()
  private val downloads = makeIsolatedDownloadsStore()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
    downloads.purge()
  }

  private fun pdfResponse(): MockResponse = MockResponse()
    .setResponseCode(200)
    .setHeader("Content-Type", "application/pdf")
    .setBody("%PDF-1.4")

  @Test
  fun `signing out removes files downloaded during the session`() = runTest {
    server.routeWithSession { pdfResponse() }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())
    val file = client.download(
      path = "/api/v1/billings/b/bills/1/invoice",
      filename = "fatura.pdf",
    )
    assertTrue(file.file.exists())

    client.logout()

    assertFalse(file.file.exists())
    assertFalse(downloads.directory.exists())
  }

  @Test
  fun `an expired session removes files downloaded during it`() = runTest {
    server.routeWithSession { call ->
      if (call.path.endsWith("/invoice")) {
        pdfResponse()
      } else {
        jsonResponse("""{"detail":"Sessão expirada."}""", code = 401)
      }
    }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())
    val file = client.download(
      path = "/api/v1/billings/b/bills/1/invoice",
      filename = "fatura.pdf",
    )
    assertTrue(file.file.exists())

    val error = runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull()

    assertEquals(LiveAPIError.SessionExpired, error)
    assertFalse(file.file.exists())
  }
}
