package app.rentivo.data.api

import app.rentivo.domain.PasskeyAssertionPayload
import app.rentivo.domain.PasskeyRequestOptions
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The pure bridge between the byte-oriented passkey types and the Credential Manager's base64url
 * JSON. Covers the whole encoding contract that the platform plumbing ([PasskeyAuthenticator])
 * cannot exercise under JVM tests.
 */
class PasskeyAssertionCodecTest {

  @Test
  fun `the request JSON re-encodes every binary field as base64url`() {
    val challenge = byteArrayOf(1, 2, 3, 4)
    val credentialA = byteArrayOf(9, 8)
    val credentialB = byteArrayOf(7)
    val options = PasskeyRequestOptions(
      challenge = challenge,
      relyingPartyIdentifier = "rentivo.com.br",
      allowedCredentialIDs = listOf(credentialA, credentialB),
      userVerification = "required",
      timeoutMilliseconds = 45000,
    )

    val request = Json.parseToJsonElement(PasskeyAssertionCodec.requestJson(options)).jsonObject

    assertEquals(Base64URL.encode(challenge), request["challenge"]!!.jsonPrimitive.content)
    assertEquals("rentivo.com.br", request["rpId"]!!.jsonPrimitive.content)
    assertEquals("required", request["userVerification"]!!.jsonPrimitive.content)
    assertEquals(45000, request["timeout"]!!.jsonPrimitive.content.toInt())
    val allowed = request["allowCredentials"]!!.jsonArray
    assertEquals(2, allowed.size)
    assertEquals("public-key", allowed[0].jsonObject["type"]!!.jsonPrimitive.content)
    assertEquals(Base64URL.encode(credentialA), allowed[0].jsonObject["id"]!!.jsonPrimitive.content)
    assertEquals(Base64URL.encode(credentialB), allowed[1].jsonObject["id"]!!.jsonPrimitive.content)
  }

  @Test
  fun `the assertion response parses into raw bytes`() {
    val credentialID = byteArrayOf(10, 20, 30)
    val clientDataJSON = byteArrayOf(1, 2, 3)
    val authenticatorData = byteArrayOf(4, 5)
    val signature = byteArrayOf(6, 7, 8, 9)
    val userHandle = byteArrayOf(42)
    val responseJson = """
      {
        "id": "${Base64URL.encode(credentialID)}",
        "rawId": "${Base64URL.encode(credentialID)}",
        "type": "public-key",
        "authenticatorAttachment": "platform",
        "clientExtensionResults": {},
        "response": {
          "clientDataJSON": "${Base64URL.encode(clientDataJSON)}",
          "authenticatorData": "${Base64URL.encode(authenticatorData)}",
          "signature": "${Base64URL.encode(signature)}",
          "userHandle": "${Base64URL.encode(userHandle)}"
        }
      }
    """.trimIndent()

    val payload = PasskeyAssertionCodec.assertionPayload(responseJson)

    assertTrue(credentialID.contentEquals(payload.credentialID))
    assertTrue(clientDataJSON.contentEquals(payload.clientDataJSON))
    assertTrue(authenticatorData.contentEquals(payload.authenticatorData))
    assertTrue(signature.contentEquals(payload.signature))
    assertTrue(userHandle.contentEquals(payload.userHandle!!))
  }

  @Test
  fun `an absent or empty userHandle parses as null`() {
    // The `response` object holds the three required fields plus whatever userHandle entry is under
    // test — absent entirely, or present but an empty string.
    fun payloadFor(responseFields: String) = PasskeyAssertionCodec.assertionPayload(
      """{"rawId":"${Base64URL.encode(byteArrayOf(1))}","response":{$responseFields}}"""
    )

    val requiredFields =
      """"clientDataJSON":"${Base64URL.encode(byteArrayOf(2))}",""" +
        """"authenticatorData":"${Base64URL.encode(byteArrayOf(3))}",""" +
        """"signature":"${Base64URL.encode(byteArrayOf(4))}""""

    assertNull(payloadFor(requiredFields).userHandle)
    assertNull(payloadFor(requiredFields + ",\"userHandle\":\"\"").userHandle)
  }

  @Test
  fun `a response missing the required fields is rejected`() {
    val error = runCatching {
      PasskeyAssertionCodec.assertionPayload("""{"rawId":"AAAA"}""")
    }.exceptionOrNull()

    assertTrue(error is PasskeyAssertionException)
  }

  @Test
  fun `a request JSON round-trips through the response parser`() {
    // The two halves agree on the base64url alphabet, so a value encoded for the request decodes
    // back to the same bytes the assertion parser would yield.
    val credentialID = byteArrayOf(-1, -2, -3, 0, 127)
    val payload = PasskeyAssertionCodec.assertionPayload(
      """
      {
        "rawId": "${Base64URL.encode(credentialID)}",
        "response": {
          "clientDataJSON": "${Base64URL.encode(credentialID)}",
          "authenticatorData": "${Base64URL.encode(credentialID)}",
          "signature": "${Base64URL.encode(credentialID)}"
        }
      }
      """.trimIndent()
    )

    assertTrue(credentialID.contentEquals(payload.credentialID))
    assertFalse(Base64URL.encode(credentialID).contains('='))
  }
}
