package app.rentivo.data.api

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class LiveSessionTest {

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
  fun `a stored bearer token restores the profile`() = runTest {
    server.route { jsonResponse(SESSION_BODY) }
    val credentials = MemoryCredentialStore(token = "stored-token")

    val restored = liveClient(server, credentials = credentials).restoreSession()

    assertNotNull(restored)
    assertEquals(7, restored!!.profile.id)
    assertEquals("ana@rentivo.com.br", restored.profile.email)
    assertEquals("stored-token", credentials.readAccessToken())
  }

  @Test
  fun `an expired stored token is deleted and answers no session`() = runTest {
    server.route {
      jsonResponse("""{"detail":"Credencial inválida ou expirada."}""", code = 401)
    }
    val credentials = MemoryCredentialStore(token = "expired-token")

    assertNull(liveClient(server, credentials = credentials).restoreSession())
    assertNull(credentials.readAccessToken())
  }

  @Test
  fun `no stored credential means no session and no request`() = runTest {
    val dispatcher = server.route { jsonResponse(SESSION_BODY) }

    assertNull(liveClient(server, credentials = MemoryCredentialStore()).restoreSession())
    assertEquals(emptyList<String>(), dispatcher.routes)
  }

  @Test
  fun `native signup stores the access token it is handed`() = runTest {
    val dispatcher = server.route {
      jsonResponse(
        """{"credential_transport":"body","access_token":"fresh-token",""" +
          """"bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"""
      )
    }
    val credentials = MemoryCredentialStore()

    val session = liveClient(server, credentials = credentials)
      .mobileSignup("ana@rentivo.com.br", "senha-secreta")

    assertEquals("fresh-token", session.accessToken)
    assertEquals("ana@rentivo.com.br", session.profile.email)
    assertEquals("fresh-token", credentials.readAccessToken())
    assertEquals(
      """{"email":"ana@rentivo.com.br","password":"senha-secreta"}""",
      dispatcher.bodyOf("POST /api/v1/auth/mobile/signup"),
    )
  }

  @Test
  fun `a session without a body-transported token is an invalid response`() = runTest {
    server.route {
      jsonResponse(
        """{"credential_transport":"cookie","bootstrap":{"user":{"id":7,"email":"a@b.c"}}}"""
      )
    }

    val error = runCatching {
      liveClient(server, credentials = MemoryCredentialStore())
        .mobileSignup("a@b.c", "senha-secreta")
    }.exceptionOrNull()

    assertEquals(LiveAPIError.InvalidResponse, error)
  }
}
