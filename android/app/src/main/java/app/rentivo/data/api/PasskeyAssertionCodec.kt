package app.rentivo.data.api

import app.rentivo.domain.LocalizedError
import app.rentivo.domain.PasskeyAssertionPayload
import app.rentivo.domain.PasskeyRequestOptions
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/**
 * The pure bridge between the app's byte-oriented passkey types and the JSON that Android's
 * `androidx.credentials` Credential Manager speaks. It has no Android dependency, so the whole of
 * the base64url encoding contract is covered by JVM unit tests — the platform plumbing that calls
 * it ([PasskeyAuthenticator]) stays a thin, untestable shell, mirroring the
 * `MobileWebAuthenticationFlow` / `MobileWebAuthenticator` split the browser flow used.
 *
 * The iOS equivalent lives in `PasskeyAssertionController` on top of `AuthenticationServices`,
 * which speaks raw bytes; Android speaks base64url JSON on both ends, so the same
 * [PasskeyRequestOptions]/[PasskeyAssertionPayload] round-trip through base64url here instead.
 */
internal object PasskeyAssertionCodec {

  private val json = Json { ignoreUnknownKeys = true }

  /**
   * The `requestJson` for `GetPublicKeyCredentialOption`: a `PublicKeyCredentialRequestOptionsJSON`
   * carrying the challenge, relying-party id, allowed credentials and user-verification preference
   * the server issued. Every binary field is re-encoded as unpadded base64url so the Credential
   * Manager parses it exactly as a browser would.
   */
  fun requestJson(options: PasskeyRequestOptions): String = buildJsonObject {
    put("challenge", Base64URL.encode(options.challenge))
    put("timeout", options.timeoutMilliseconds)
    put("rpId", options.relyingPartyIdentifier)
    put("userVerification", options.userVerification)
    putJsonArray("allowCredentials") {
      for (credentialID in options.allowedCredentialIDs) {
        add(
          buildJsonObject {
            put("type", "public-key")
            put("id", Base64URL.encode(credentialID))
          }
        )
      }
    }
  }.toString()

  /**
   * Parses the `authenticationResponseJson` a `PublicKeyCredential` hands back into the raw-byte
   * [PasskeyAssertionPayload] the Data layer re-encodes for `/passkeys/complete`. `userHandle` is
   * absent, not empty, when the authenticator returns none.
   *
   * @throws PasskeyAssertionException when the response is not the expected WebAuthn shape.
   */
  fun assertionPayload(responseJson: String): PasskeyAssertionPayload {
    val root = runCatching { json.parseToJsonElement(responseJson).jsonObject }
      .getOrElse { throw PasskeyAssertionException() }
    val response = root["response"]?.jsonObject ?: throw PasskeyAssertionException()
    // The credential id travels as `rawId` (base64url of the raw bytes); `id` is the same string.
    val credentialID = decode(root["rawId"]?.jsonPrimitive?.contentOrNull ?: root["id"]?.string())
    return PasskeyAssertionPayload(
      credentialID = credentialID,
      clientDataJSON = decode(response["clientDataJSON"]?.string()),
      authenticatorData = decode(response["authenticatorData"]?.string()),
      signature = decode(response["signature"]?.string()),
      userHandle = response["userHandle"]?.string()
        ?.takeIf { it.isNotEmpty() }
        ?.let { decode(it) },
    )
  }

  private fun kotlinx.serialization.json.JsonElement.string(): String? = jsonPrimitive.contentOrNull

  private fun decode(value: String?): ByteArray =
    value?.let(Base64URL::decode) ?: throw PasskeyAssertionException()
}

/** The Credential Manager returned something that is not a usable WebAuthn assertion. */
class PasskeyAssertionException :
  Exception("Não foi possível interpretar a resposta da chave de acesso."), LocalizedError {
  override val errorDescription: String
    get() = "Não foi possível concluir a verificação com a chave de acesso."
}
