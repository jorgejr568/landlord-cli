package app.rentivo.data.api

import app.rentivo.domain.MFAChallenge
import app.rentivo.domain.MFAMethod
import app.rentivo.domain.PasskeyAssertionPayload
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The native (`/api/v1/auth/mobile/...`) client surface: the 200-vs-202 login split, MFA verify and
 * passkey encoding, and the error mapping the login screen relies on. Mirrors the iOS
 * `MobileAuthRepositoryTests` / `LiveAPIClient` passkey coverage, over `MockWebServer` here.
 */
class MobileAuthClientTest {

  private val server = MockWebServer()

  @Before
  fun start() {
    server.start()
  }

  @After
  fun stop() {
    server.shutdown()
  }

  private val sessionBody =
    """{"credential_transport":"body","access_token":"fresh-token",""" +
      """"bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"""

  @Test
  fun `a 200 login adopts the session and stores the token`() = runTest {
    val dispatcher = server.route { jsonResponse(sessionBody) }
    val credentials = MemoryCredentialStore()

    val outcome = liveClient(server, credentials = credentials)
      .mobileLogin("ana@rentivo.com.br", "senha-secreta")

    assertTrue(outcome is LiveLoginOutcome.Authenticated)
    val session = (outcome as LiveLoginOutcome.Authenticated).session
    assertEquals("fresh-token", session.accessToken)
    assertEquals("ana@rentivo.com.br", session.profile.email)
    assertEquals("fresh-token", credentials.readAccessToken())
    assertEquals(
      """{"email":"ana@rentivo.com.br","password":"senha-secreta"}""",
      dispatcher.bodyOf("POST /api/v1/auth/mobile/login"),
    )
  }

  @Test
  fun `a 202 login yields the MFA challenge and drops unknown methods`() = runTest {
    server.route {
      jsonResponse(
        """{"status":"mfa_required","credential_transport":"body","challenge_id":"chal-1",""" +
          """"challenge_token":"tok-1","methods":["totp","sms","recovery","passkey","carrier"]}""",
        code = 202,
      )
    }
    val credentials = MemoryCredentialStore()

    val outcome = liveClient(server, credentials = credentials)
      .mobileLogin("ana@rentivo.com.br", "senha")

    assertTrue(outcome is LiveLoginOutcome.MfaRequired)
    val challenge = (outcome as LiveLoginOutcome.MfaRequired).challenge
    assertEquals("chal-1", challenge.challengeId)
    assertEquals("tok-1", challenge.challengeToken)
    // `sms` and `carrier` are not methods this build knows, so they are dropped rather than raised.
    assertEquals(listOf(MFAMethod.TOTP, MFAMethod.RECOVERY, MFAMethod.PASSKEY), challenge.methods)
    // A challenge is not a session: nothing is stored yet.
    assertNull(credentials.readAccessToken())
  }

  @Test
  fun `a 202 login whose methods are all unknown yields an empty method list`() = runTest {
    server.route {
      jsonResponse(
        """{"credential_transport":"body","challenge_id":"c","challenge_token":"t",""" +
          """"methods":["sms","carrier"]}""",
        code = 202,
      )
    }

    val outcome = liveClient(server, credentials = MemoryCredentialStore())
      .mobileLogin("ana@rentivo.com.br", "senha")

    val challenge = (outcome as LiveLoginOutcome.MfaRequired).challenge
    assertTrue(challenge.methods.isEmpty())
  }

  @Test
  fun `a 202 login without a challenge token is an invalid response`() = runTest {
    server.route {
      jsonResponse(
        """{"credential_transport":"body","challenge_id":"c","methods":["totp"]}""",
        code = 202,
      )
    }

    val error = runCatching {
      liveClient(server, credentials = MemoryCredentialStore())
        .mobileLogin("ana@rentivo.com.br", "senha")
    }.exceptionOrNull()

    assertEquals(LiveAPIError.InvalidResponse, error)
  }

  @Test
  fun `bad credentials surface the server detail and 401 status`() = runTest {
    server.route {
      jsonResponse("""{"detail":"Credenciais inválidas."}""", code = 401)
    }

    val error = runCatching {
      liveClient(server, credentials = MemoryCredentialStore())
        .mobileLogin("ana@rentivo.com.br", "errada")
    }.exceptionOrNull() as LiveAPIError.Server

    assertEquals("Credenciais inválidas.", error.message)
    assertEquals(401, error.statusCode)
  }

  @Test
  fun `a rate-limited login surfaces the 429 status`() = runTest {
    server.route {
      jsonResponse("""{"detail":"Muitas tentativas. Aguarde um instante."}""", code = 429)
    }

    val error = runCatching {
      liveClient(server, credentials = MemoryCredentialStore())
        .mobileLogin("ana@rentivo.com.br", "senha")
    }.exceptionOrNull() as LiveAPIError.Server

    assertEquals("Muitas tentativas. Aguarde um instante.", error.message)
    assertEquals(429, error.statusCode)
  }

  @Test
  fun `a signup with an already-registered email surfaces the 400 detail`() = runTest {
    server.route {
      jsonResponse("""{"detail":"E-mail já cadastrado."}""", code = 400)
    }

    val error = runCatching {
      liveClient(server, credentials = MemoryCredentialStore())
        .mobileSignup("ana@rentivo.com.br", "senha")
    }.exceptionOrNull() as LiveAPIError.Server

    assertEquals("E-mail já cadastrado.", error.message)
    assertEquals(400, error.statusCode)
  }

  @Test
  fun `TOTP verify posts the challenge pair and code, and adopts the session`() = runTest {
    val dispatcher = server.route { jsonResponse(sessionBody) }
    val credentials = MemoryCredentialStore()
    val challenge = MFAChallenge("chal-1", "tok-1", listOf(MFAMethod.TOTP))

    val session = liveClient(server, credentials = credentials)
      .verifyTotp(challenge, "123456")

    assertEquals("fresh-token", session.accessToken)
    assertEquals("fresh-token", credentials.readAccessToken())
    val body = Json.parseToJsonElement(
      dispatcher.bodyOf("POST /api/v1/auth/mfa/totp/verify")
    ).jsonObject
    assertEquals("chal-1", body["challenge_id"]!!.jsonPrimitive.content)
    assertEquals("tok-1", body["challenge_token"]!!.jsonPrimitive.content)
    assertEquals("123456", body["code"]!!.jsonPrimitive.content)
    assertEquals("body", body["credential_transport"]!!.jsonPrimitive.content)
  }

  @Test
  fun `recovery-code verify posts to the recovery route`() = runTest {
    val dispatcher = server.route { jsonResponse(sessionBody) }
    val challenge = MFAChallenge("chal-1", "tok-1", listOf(MFAMethod.RECOVERY))

    liveClient(server, credentials = MemoryCredentialStore())
      .verifyRecoveryCode(challenge, "AAAA-BBBB")

    val body = Json.parseToJsonElement(
      dispatcher.bodyOf("POST /api/v1/auth/mfa/recovery/verify")
    ).jsonObject
    assertEquals("AAAA-BBBB", body["code"]!!.jsonPrimitive.content)
  }

  @Test
  fun `beginning a passkey assertion decodes the options into raw bytes`() = runTest {
    val challengeBytes = byteArrayOf(1, 2, 3, 4, 5)
    val credentialBytes = byteArrayOf(9, 8, 7)
    val dispatcher = server.route {
      jsonResponse(
        """{"challenge":"${Base64URL.encode(challengeBytes)}","timeout":60000,""" +
          """"rpId":"rentivo.com.br","userVerification":"preferred",""" +
          """"allowCredentials":[{"type":"public-key","id":"${Base64URL.encode(credentialBytes)}"}]}"""
      )
    }
    val challenge = MFAChallenge("chal-1", "tok-1", listOf(MFAMethod.PASSKEY))

    val options = liveClient(server, credentials = MemoryCredentialStore())
      .beginPasskeyAssertion(challenge)

    assertTrue(challengeBytes.contentEquals(options.challenge))
    assertEquals("rentivo.com.br", options.relyingPartyIdentifier)
    assertEquals("preferred", options.userVerification)
    assertEquals(60000, options.timeoutMilliseconds)
    assertEquals(1, options.allowedCredentialIDs.size)
    assertTrue(credentialBytes.contentEquals(options.allowedCredentialIDs.single()))
    // The request repeats the whole body-transport challenge envelope.
    val body = Json.parseToJsonElement(
      dispatcher.bodyOf("POST /api/v1/auth/mfa/passkeys/begin")
    ).jsonObject
    assertEquals("chal-1", body["challenge_id"]!!.jsonPrimitive.content)
    assertEquals("body", body["credential_transport"]!!.jsonPrimitive.content)
  }

  @Test
  fun `completing a passkey assertion encodes id equal to rawId and omits an absent userHandle`() =
    runTest {
      val dispatcher = server.route { jsonResponse(sessionBody) }
      val challenge = MFAChallenge("chal-1", "tok-1", listOf(MFAMethod.PASSKEY))
      val payload = PasskeyAssertionPayload(
        credentialID = byteArrayOf(10, 20, 30),
        clientDataJSON = byteArrayOf(1, 2),
        authenticatorData = byteArrayOf(3, 4),
        signature = byteArrayOf(5, 6),
        userHandle = null,
      )

      val session = liveClient(server, credentials = MemoryCredentialStore())
        .completePasskeyAssertion(challenge, payload)

      assertEquals("fresh-token", session.accessToken)
      val body = Json.parseToJsonElement(
        dispatcher.bodyOf("POST /api/v1/auth/mfa/passkeys/complete")
      ).jsonObject
      val credential = body["credential"]!!.jsonObject
      val expectedId = Base64URL.encode(byteArrayOf(10, 20, 30))
      assertEquals(expectedId, credential["id"]!!.jsonPrimitive.content)
      // id and rawId are the same base64url string, both derived from the raw credential ID.
      assertEquals(expectedId, credential["rawId"]!!.jsonPrimitive.content)
      assertEquals("public-key", credential["type"]!!.jsonPrimitive.content)
      val response = credential["response"]!!.jsonObject
      assertEquals(Base64URL.encode(byteArrayOf(1, 2)), response["clientDataJSON"]!!.jsonPrimitive.content)
      assertEquals(Base64URL.encode(byteArrayOf(5, 6)), response["signature"]!!.jsonPrimitive.content)
      // An absent userHandle is omitted entirely rather than written as null.
      assertFalse(response.containsKey("userHandle"))
    }

  @Test
  fun `a present userHandle is carried as base64url`() = runTest {
    val dispatcher = server.route { jsonResponse(sessionBody) }
    val challenge = MFAChallenge("chal-1", "tok-1", listOf(MFAMethod.PASSKEY))
    val payload = PasskeyAssertionPayload(
      credentialID = byteArrayOf(1),
      clientDataJSON = byteArrayOf(2),
      authenticatorData = byteArrayOf(3),
      signature = byteArrayOf(4),
      userHandle = byteArrayOf(42, 43),
    )

    liveClient(server, credentials = MemoryCredentialStore())
      .completePasskeyAssertion(challenge, payload)

    val response = Json.parseToJsonElement(
      dispatcher.bodyOf("POST /api/v1/auth/mfa/passkeys/complete")
    ).jsonObject["credential"]!!.jsonObject["response"]!!.jsonObject
    assertEquals(Base64URL.encode(byteArrayOf(42, 43)), response["userHandle"]!!.jsonPrimitive.content)
  }
}
