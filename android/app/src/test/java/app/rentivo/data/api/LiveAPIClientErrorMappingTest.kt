package app.rentivo.data.api

import kotlinx.coroutines.test.runTest
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.io.InterruptedIOException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Non-2xx and transport error mapping.
 *
 * A server-supplied `detail` must surface verbatim and an undecodable error body must fall back to
 * a fixed PT-BR message, in both cases carrying the original HTTP status. Transport failures
 * (thrown before any response arrives) must become actionable PT-BR copy rather than a raw
 * `IOException`, otherwise the login screen and the app-wide error mapping fall through to a
 * generic message with no connectivity/retry cue.
 */
class LiveAPIClientErrorMappingTest {

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

  private fun serverError(error: Throwable?): LiveAPIError.Server {
    assertTrue("Expected a LiveAPIError.Server, got $error", error is LiveAPIError.Server)
    return error as LiveAPIError.Server
  }

  @Test
  fun `a non-2xx response surfaces the server problem detail and status code`() = runTest {
    server.routeWithSession { jsonResponse("""{"detail":"Chave PIX inválida."}""", code = 422) }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())

    val error = serverError(
      runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull()
    )

    assertEquals("Chave PIX inválida.", error.message)
    assertEquals(422, error.statusCode)
  }

  @Test
  fun `an undecodable error body falls back to a generic message`() = runTest {
    server.routeWithSession {
      MockResponse()
        .setResponseCode(500)
        .setHeader("Content-Type", "text/plain")
        .setBody("internal server error, not json")
    }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())

    val error = serverError(
      runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull()
    )

    assertEquals("Não foi possível concluir a solicitação.", error.message)
    assertEquals(500, error.statusCode)
  }

  @Test
  fun `a download maps every other failure to one fixed file message`() = runTest {
    server.routeWithSession {
      jsonResponse("""{"detail":"Acesso negado, mas ignorado pelo download."}""", code = 403)
    }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())

    val error = serverError(
      runCatching {
        client.download(path = "/api/v1/billings/b/bills/1/invoice", filename = "fatura")
      }.exceptionOrNull()
    )

    // `download()` never attempts to read a problem document (unlike `request()`); every
    // non-2xx/non-401 status collapses to this one message, and no status code is kept.
    assertEquals("Não foi possível baixar o arquivo.", error.message)
    assertNull(error.statusCode)
  }

  @Test
  fun `a download appends the extension from the content type when the filename has none`() =
    runTest {
      server.routeWithSession {
        MockResponse()
          .setResponseCode(200)
          .setHeader("Content-Type", "image/jpeg")
          .setBody("JPEGBYTES")
      }
      val client = liveClient(server, downloads = downloads)
      assertNotNull(client.restoreSession())

      val file = client.download(
        path = "/api/v1/billings/b/attachments/1",
        filename = "comprovante",
        mediaType = "application/pdf",
      )

      assertEquals("comprovante.jpg", file.filename)
      assertEquals("image/jpeg", file.mediaType)
      assertEquals("JPEGBYTES", file.file.readText())
      assertTrue(file.file.name.endsWith(".jpg"))
    }

  @Test
  fun `a download keeps an already-extensioned filename whatever the content type says`() =
    runTest {
      server.routeWithSession {
        MockResponse()
          .setResponseCode(200)
          .setHeader("Content-Type", "application/pdf")
          .setBody("%PDF-1.4")
      }
      val client = liveClient(server, downloads = downloads)
      assertNotNull(client.restoreSession())

      val file = client.download(
        path = "/api/v1/billings/b/bills/1/invoice",
        filename = "fatura-julho.pdf",
      )

      assertEquals("fatura-julho.pdf", file.filename)
      assertTrue(file.file.name.endsWith(".pdf"))
    }

  @Test
  fun `a download leaves nothing but the finished file behind`() = runTest {
    server.routeWithSession {
      MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/pdf")
        .setBody("%PDF-1.4")
    }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())

    val file = client.download(path = "/api/v1/billings/b/bills/1/invoice", filename = "fatura")

    // The write goes through a sibling temp file that is renamed into place, so the share sheet can
    // never be handed a half-written document — and the temp file must not outlive the download.
    assertEquals(
      listOf(file.file.name),
      downloads.directory.listFiles().orEmpty().map { it.name },
    )
    assertEquals("%PDF-1.4", file.file.readText())
  }

  @Test
  fun `an unknown content type downloads as an opaque binary`() = runTest {
    server.routeWithSession {
      MockResponse()
        .setResponseCode(200)
        .setHeader("Content-Type", "application/x-rentivo; charset=utf-8")
        .setBody("opaque")
    }
    val client = liveClient(server, downloads = downloads)
    assertNotNull(client.restoreSession())

    val file = client.download(path = "/api/v1/billings/b/attachments/1", filename = "arquivo")

    assertEquals("arquivo.bin", file.filename)
    assertEquals("application/x-rentivo", file.mediaType)
  }

  @Test
  fun `a request timeout maps to a retryable message`() = runTest {
    server.route { MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE) }
    val impatient = LiveAPIClient.defaultClient().newBuilder()
      .readTimeout(300, TimeUnit.MILLISECONDS)
      .build()
    val client = liveClient(
      server,
      credentials = MemoryCredentialStore(),
      downloads = downloads,
      okHttp = impatient,
    )

    val error = serverError(
      runCatching { client.exchangeMobileAuthorization("any-code") }.exceptionOrNull()
    )

    assertEquals(
      "O Rentivo demorou para responder. Verifique sua conexão e tente novamente.",
      error.message,
    )
  }

  @Test
  fun `a whole-call timeout maps to the same retryable message as a read timeout`() = runTest {
    // OkHttp's `callTimeout` — the only bound covering a call that is slow overall rather than
    // stalled on one socket read — throws a plain `InterruptedIOException`, not the
    // `SocketTimeoutException` subclass, so it must not fall into the generic branch.
    val client = liveClient(
      server,
      credentials = MemoryCredentialStore(),
      downloads = downloads,
      okHttp = failingClient(InterruptedIOException("timeout")),
    )

    val error = serverError(
      runCatching { client.exchangeMobileAuthorization("any-code") }.exceptionOrNull()
    )

    assertEquals(
      "O Rentivo demorou para responder. Verifique sua conexão e tente novamente.",
      error.message,
    )
  }

  @Test
  fun `an offline transport failure maps to a connectivity message`() = runTest {
    val client = liveClient(
      server,
      credentials = MemoryCredentialStore(),
      downloads = downloads,
      okHttp = failingClient(UnknownHostException("rentivo.com.br")),
    )

    val error = serverError(
      runCatching { client.exchangeMobileAuthorization("any-code") }.exceptionOrNull()
    )

    assertEquals(
      "Sem conexão com o Rentivo. Verifique sua internet e tente novamente.",
      error.message,
    )
  }

  @Test
  fun `any other transport failure maps to the generic connection message`() = runTest {
    val client = liveClient(
      server,
      credentials = MemoryCredentialStore(),
      downloads = downloads,
      okHttp = failingClient(IOException("stream reset")),
    )

    val error = serverError(
      runCatching { client.exchangeMobileAuthorization("any-code") }.exceptionOrNull()
    )

    assertEquals("Não foi possível conectar ao Rentivo. Tente novamente.", error.message)
  }

  @Test
  fun `transport failures are translated for authenticated requests too`() = runTest {
    server.route { jsonResponse(SESSION_BODY) }
    // Restores a session normally, then loses the network before the first real call.
    val offlineAfterSignIn = LiveAPIClient.defaultClient().newBuilder()
      .addInterceptor(FailAfterFirstCall(UnknownHostException("rentivo.com.br")))
      .build()
    val client = liveClient(server, downloads = downloads, okHttp = offlineAfterSignIn)
    assertNotNull(client.restoreSession())

    val error = serverError(
      runCatching { client.request(path = "/api/v1/billings") }.exceptionOrNull()
    )

    assertEquals(
      "Sem conexão com o Rentivo. Verifique sua internet e tente novamente.",
      error.message,
    )
  }

  private fun failingClient(error: IOException): OkHttpClient =
    LiveAPIClient.defaultClient().newBuilder()
      .addInterceptor(FailAfterFirstCall(error, passThroughCalls = 0))
      .build()

  private class FailAfterFirstCall(
    private val error: IOException,
    private val passThroughCalls: Int = 1,
  ) : Interceptor {
    private val seen = AtomicInteger(0)

    override fun intercept(chain: Interceptor.Chain): Response =
      if (seen.getAndIncrement() < passThroughCalls) chain.proceed(chain.request()) else throw error
  }
}
