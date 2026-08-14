package app.rentivo.data.api

import app.rentivo.domain.APIKeyDraft
import app.rentivo.domain.APIKeyGrant
import app.rentivo.domain.APIKeyScope
import app.rentivo.domain.PixConfiguration
import app.rentivo.domain.WorkspaceID
import app.rentivo.domain.WorkspaceResourceType
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class APIRentivoStoreProfileTest {

  private val server = MockWebServer()
  private val saoPaulo = ZoneId.of("America/Sao_Paulo")

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
  }

  private suspend fun authenticatedStore(): APIRentivoStore {
    val store = APIRentivoStore(liveClient(server))
    assertNotNull(store.restoreSession())
    return store
  }

  private fun profileRoutes(): RouteDispatcher = server.routeWithSession { call ->
    when (call.route) {
      "GET /api/v1/security" -> jsonResponse(
        """{"profile":{"email":"ana@rentivo.com.br","pix_key":"chave-abc",""" +
          """"pix_merchant_name":"Ana","pix_merchant_city":"Sao Paulo"},""" +
          """"totp":{"enabled":true,"recovery_codes_remaining":5},"mfa":{},"passkeys":[""" +
          """{"uuid":"passkey-1","name":"iPhone de Ana",""" +
          """"created_at":"2026-07-20T10:15:30.123456+00:00","last_used_at":null}]}"""
      )

      "GET /api/v1/api-keys" -> jsonResponse(
        """{"items":[{"uuid":"key-1","name":"Ativa","hint":"rntv-v1-ab••cd",""" +
          """"scopes":["profile:read","teleportation:manage"],"grants":[""" +
          """{"resource_type":"user","resource_id":"personal","available":true},""" +
          """{"resource_type":"user","resource_id":null,"available":true},""" +
          """{"resource_type":"organization","resource_id":"organization-hidden",""" +
          """"available":false}],""" +
          """"expires_at":"2026-12-31T23:59:59.000000+00:00","last_used_at":null,""" +
          """"created_at":"2026-01-01T00:00:00.000000+00:00","revoked_at":null},""" +
          """{"uuid":"key-2","name":"Revogada","hint":"rntv-v1-ef••gh",""" +
          """"scopes":["profile:read"],"grants":[],""" +
          """"expires_at":"2026-12-31T23:59:59.000000+00:00","last_used_at":null,""" +
          """"created_at":"2026-01-01T00:00:00.000000+00:00",""" +
          """"revoked_at":"2026-02-01T00:00:00.000000+00:00"}]}"""
      )

      else -> unexpected(call)
    }
  }

  @Test
  fun `the profile loads pix fields from the security summary endpoint`() = runTest {
    // Regression test: GET /api/v1/profile only returns `CurrentProfileResponse` ({email}); the
    // pix fields must come from GET /api/v1/security's `profile` (a full `ProfileResponse`).
    val dispatcher = profileRoutes()
    val store = authenticatedStore()

    val profile = store.profile()

    assertEquals("ana@rentivo.com.br", profile.email)
    assertEquals(
      PixConfiguration(key = "chave-abc", merchantName = "Ana", merchantCity = "Sao Paulo"),
      profile.pix,
    )
    // The account id comes from the session bootstrap, not from this payload.
    assertEquals(7, profile.id)
    assertEquals(listOf("GET /api/v1/auth/session", "GET /api/v1/security"), dispatcher.routes)
  }

  @Test
  fun `updating pix posts the flattened fields and re-reads the profile`() = runTest {
    val dispatcher = server.routeWithSession {
      jsonResponse(
        """{"profile":{"email":"ana@rentivo.com.br","pix_key":"nova-chave",""" +
          """"pix_merchant_name":"Ana","pix_merchant_city":"Santos"}}"""
      )
    }
    val store = authenticatedStore()

    val profile = store.updatePix(
      PixConfiguration(key = "nova-chave", merchantName = "Ana", merchantCity = "Santos")
    )

    assertEquals("nova-chave", profile.pix?.key)
    assertEquals("Santos", profile.pix?.merchantCity)
    assertEquals(
      """{"pix_key":"nova-chave","pix_merchant_name":"Ana","pix_merchant_city":"Santos"}""",
      dispatcher.bodyOf("POST /api/v1/security/pix"),
    )
  }

  @Test
  fun `an entirely empty pix block decodes as no pix at all`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"profile":{"email":"ana@rentivo.com.br","pix_key":"","pix_merchant_name":"",""" +
          """"pix_merchant_city":""},"totp":{"enabled":false,"recovery_codes_remaining":0},""" +
          """"passkeys":[]}"""
      )
    }
    val store = authenticatedStore()

    assertNull(store.profile().pix)
  }

  @Test
  fun `the security summary decodes fractional-second timestamps`() = runTest {
    // Regression test: a formatter without fractional-seconds support used to fall back to a
    // sentinel, so backend timestamps with microseconds decoded as year 1.
    profileRoutes()
    val store = authenticatedStore()

    val summary = store.securitySummary()

    val passkey = summary.passkeys.first()
    assertEquals(2026, passkey.createdAt.atZone(saoPaulo).year)
    assertEquals(true, summary.totpEnabled)
    assertEquals(5, summary.recoveryCodeCount)
    assertNull(passkey.lastUsedAt)
  }

  @Test
  fun `the security summary decodes timestamps without a timezone designator`() = runTest {
    // Regression test: passkey rows live in naive `DATETIME` columns, so production served
    // "2026-07-20T10:15:30" with no offset and the whole Segurança tab failed to decode. Those
    // timestamps are São Paulo wall clock, so they must parse in that zone.
    server.routeWithSession {
      jsonResponse(
        """{"profile":{"email":"ana@rentivo.com.br","pix_key":"","pix_merchant_name":"",""" +
          """"pix_merchant_city":""},"totp":{"enabled":false,"recovery_codes_remaining":0},""" +
          """"mfa":{},"passkeys":[{"uuid":"passkey-1","name":"iPhone de Ana",""" +
          """"created_at":"2026-07-20T10:15:30",""" +
          """"last_used_at":"2026-07-20T18:42:11.063639"}]}"""
      )
    }
    val store = authenticatedStore()

    val passkey = store.securitySummary().passkeys.first()

    val createdAt = passkey.createdAt.atZone(saoPaulo)
    assertEquals(2026, createdAt.year)
    assertEquals(7, createdAt.monthValue)
    assertEquals(20, createdAt.dayOfMonth)
    assertEquals(10, createdAt.hour)
    assertEquals(15, createdAt.minute)
    // A microsecond timestamp without an offset must survive the same way.
    assertEquals(18, passkey.lastUsedAt!!.atZone(saoPaulo).hour)
  }

  @Test
  fun `the security summary honours explicit offsets over the local fallback`() = runTest {
    // The offset-less formatters must stay strictly a fallback: a UTC timestamp has to keep
    // decoding as UTC, not as São Paulo wall clock. 10:15:30 UTC is 07:15 in São Paulo (UTC-3).
    profileRoutes()
    val store = authenticatedStore()

    val passkey = store.securitySummary().passkeys.first()

    assertEquals(7, passkey.createdAt.atZone(saoPaulo).hour)
  }

  @Test
  fun `a malformed passkey timestamp is a decode error rather than a sentinel date`() = runTest {
    server.routeWithSession {
      jsonResponse(
        """{"profile":{"email":"a@b.c","pix_key":"","pix_merchant_name":"",""" +
          """"pix_merchant_city":""},"totp":{"enabled":false,"recovery_codes_remaining":0},""" +
          """"passkeys":[{"uuid":"passkey-1","name":"iPhone","created_at":"ontem",""" +
          """"last_used_at":null}]}"""
      )
    }
    val store = authenticatedStore()

    assertEquals(
      LiveAPIError.InvalidResponse,
      runCatching { store.securitySummary() }.exceptionOrNull(),
    )
  }

  @Test
  fun `listing api keys hides revoked keys like the mock`() = runTest {
    // Regression test: the server returns revoked integration keys too; the mock filters them out
    // and the live store must match.
    profileRoutes()
    val store = authenticatedStore()

    val keys = store.listAPIKeys()

    assertEquals(listOf("Ativa"), keys.map { it.name })
    // Unknown scopes and grants with no resource id do not fail the decode. The latter remain
    // represented by the unavailable count so an edit cannot replace and destroy them.
    assertEquals(setOf(APIKeyScope.PROFILE_READ), keys.first().scopes)
    assertEquals(2, keys.first().grants.size)
    assertEquals(false, keys.first().grants.last().available)
    assertEquals(2, keys.first().unavailableGrantCount)
    assertEquals(1, keys.first().unavailableScopeCount)
    assertNull(keys.first().revokedAt)
  }

  @Test
  fun `creating an api key sorts its scopes and decodes the flattened secret`() = runTest {
    val dispatcher = server.routeWithSession {
      jsonResponse(
        """{"secret":"rntv-v1-super-secret","uuid":"key-1","name":"Painel financeiro",""" +
          """"hint":"rntv-v1-ab••cd","scopes":["billings:read","profile:read"],"grants":[""" +
          """{"resource_type":"user","resource_id":"personal","available":true}],""" +
          """"expires_at":"2026-12-31T23:59:59+00:00","last_used_at":null,""" +
          """"created_at":"2026-01-01T00:00:00+00:00","revoked_at":null}"""
      )
    }
    val store = authenticatedStore()

    val created = store.createAPIKey(APIKeyDraft.demo)

    assertEquals("rntv-v1-super-secret", created.secret)
    assertEquals("Painel financeiro", created.metadata.name)
    assertEquals(
      setOf(APIKeyScope.PROFILE_READ, APIKeyScope.BILLINGS_READ),
      created.metadata.scopes,
    )
    val body = apiJson.parseToJsonElement(dispatcher.bodyOf("POST /api/v1/api-keys")).jsonObject
    assertEquals(
      listOf("billings:read", "profile:read"),
      body["scopes"]!!.jsonArray.map { it.jsonPrimitive.content },
    )
    assertEquals(
      WireInstant.iso8601(Instant.ofEpochSecond(1_798_761_600L)),
      body["expires_at"]!!.jsonPrimitive.content,
    )
    assertEquals(
      "personal",
      body["grants"]!!.jsonArray[0].jsonObject["resource_id"]!!.jsonPrimitive.content,
    )
  }

  @Test
  fun `an api key expiry is rendered as an internet date-time in UTC`() {
    assertEquals(
      "2026-12-31T23:59:59Z",
      WireInstant.iso8601(Instant.parse("2026-12-31T23:59:59Z")),
    )
  }

  @Test
  fun `api key options use the lightweight picker endpoint`() = runTest {
    val dispatcher = server.routeWithSession { call ->
      if (call.route == "GET /api/v1/api-keys/options") {
        jsonResponse(
          """{"scopes":["profile:read","billings:read"],""" +
            """"personal_workspace":{"resource_type":"user","resource_id":"personal"},""" +
            """"organizations":[{"resource_type":"organization","resource_id":"organization-1",""" +
            """"name":"Horizonte"}],"default_expiration_days":30,"max_expiration_days":90}"""
        )
      } else {
        unexpected(call)
      }
    }
    val store = authenticatedStore()

    val options = store.apiKeyOptions()

    assertEquals(setOf(APIKeyScope.PROFILE_READ, APIKeyScope.BILLINGS_READ), options.scopes)
    assertEquals(30, options.defaultExpirationDays)
    assertEquals(90, options.maxExpirationDays)
    assertEquals("Horizonte", options.workspaces.single { it.resourceID.rawValue == "organization-1" }.name)
    assertEquals(
      listOf("GET /api/v1/auth/session", "GET /api/v1/api-keys/options"),
      dispatcher.routes,
    )
  }

  @Test
  fun `changing the password uses the api contract field names`() = runTest {
    val dispatcher = server.routeWithSession { MockResponse().setResponseCode(204) }
    val store = authenticatedStore()

    store.changePassword(
      currentPassword = "old-password",
      newPassword = "new-password",
      confirmPassword = "new-password",
    )

    assertEquals(
      """{"current_password":"old-password","new_password":"new-password",""" +
        """"confirm_password":"new-password"}""",
      dispatcher.bodyOf("POST /api/v1/security/change-password"),
    )
  }
}
