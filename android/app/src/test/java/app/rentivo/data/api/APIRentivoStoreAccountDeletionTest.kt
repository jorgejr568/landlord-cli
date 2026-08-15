package app.rentivo.data.api

import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class APIRentivoStoreAccountDeletionTest {

  private val server = MockWebServer()
  private val credentials = MemoryCredentialStore(token = "stored-token")
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

  private suspend fun authenticatedStore(): APIRentivoStore {
    val store = APIRentivoStore(
      liveClient(server, credentials = credentials, downloads = downloads)
    )
    assertNotNull(store.restoreSession())
    return store
  }

  @Test
  fun `deleting the account posts the password and clears the credential`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "POST /api/v1/security/delete-account") {
        MockResponse().setResponseCode(204)
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()

    store.deleteAccount("s3cret")

    assertEquals(
      """{"password":"s3cret"}""",
      dispatcher.bodyOf("POST /api/v1/security/delete-account"),
    )
    assertNull(credentials.readAccessToken())
    assertEquals(0, store.currentUser.id)
    assertEquals("", store.currentUser.email)
  }

  @Test
  fun `a rejected password leaves the session intact`() = runTest {
    server.routeWithSession { jsonResponse("""{"detail":"Senha incorreta."}""", code = 400) }
    val store = authenticatedStore()

    val error = runCatching { store.deleteAccount("wrong") }.exceptionOrNull()

    assertTrue(error is LiveAPIError.Server)
    assertEquals("Senha incorreta.", error!!.message)
    assertEquals("stored-token", credentials.readAccessToken())
    assertEquals(7, store.currentUser.id)
  }

  @Test
  fun `account deletion readiness is decoded before destructive UI proceeds`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "GET /api/v1/security/account-deletion-readiness") {
        jsonResponse("""{"can_delete":false,"reason":"sole_organization_admin"}""")
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()

    val readiness = store.accountDeletionReadiness()

    assertFalse(readiness.canDelete)
    assertEquals("sole_organization_admin", readiness.reason)
    assertEquals(
      listOf(
        "GET /api/v1/auth/session",
        "GET /api/v1/security/account-deletion-readiness",
      ),
      dispatcher.routes,
    )
  }

  @Test
  fun `signing out revokes the token server-side and then clears everything`() = runTest {
    val dispatcher = server.routeWithSession { MockResponse().setResponseCode(204) }
    val store = authenticatedStore()

    store.logout()

    assertEquals(
      listOf("GET /api/v1/auth/session", "POST /api/v1/auth/logout"),
      dispatcher.routes,
    )
    assertNull(credentials.readAccessToken())
    assertEquals(0, store.currentUser.id)
  }

  @Test
  fun `signing out never throws even when revocation fails`() = runTest {
    server.routeWithSession { jsonResponse("""{"detail":"Sessão expirada."}""", code = 401) }
    val store = authenticatedStore()

    store.logout()

    assertNull(credentials.readAccessToken())
    assertEquals("", store.currentUser.email)
    assertFalse(downloads.directory.exists())
  }

  @Test
  fun `the live store always reports itself as backed by the api`() = runTest {
    server.routeWithSession { unexpected(it) }

    assertTrue(authenticatedStore().usesLiveAPI)
  }

  @Test
  fun `the live store surfaces no recent activity feed`() = runTest {
    server.routeWithSession { unexpected(it) }

    assertEquals(emptyList<Any>(), authenticatedStore().recentActivities)
  }
}
