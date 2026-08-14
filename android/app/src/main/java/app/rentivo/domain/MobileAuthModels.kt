package app.rentivo.domain

/**
 * A second factor the server is willing to accept for a pending login challenge. Port of
 * `ios/Rentivo/Domain/MobileAuthModels.swift`.
 *
 * The contract types `methods` as a bare `array[string]` (see `BodyMFARequiredResponse` in
 * `openapi.json`), so the values are not pinned by the schema; the server emits `totp`, `recovery`,
 * and `passkey`. Decoding therefore **drops** values this build does not know (via [fromWire])
 * instead of failing or smuggling them through as an opaque case: a method the app cannot present is
 * not actionable, and an unknown string must never crash the login screen. A challenge whose methods
 * are all unknown decodes to an empty [MFAChallenge.methods] list, which the UI has to treat as "no
 * factor available here" rather than as a decoding error.
 */
enum class MFAMethod(val wire: String) {
  TOTP("totp"),
  RECOVERY("recovery"),
  PASSKEY("passkey");

  companion object {
    /** The method named by [wire], or `null` for a value this build does not know. */
    fun fromWire(wire: String): MFAMethod? = entries.firstOrNull { it.wire == wire }
  }
}

/**
 * A login that stopped at the MFA step.
 *
 * Both identifiers are load-bearing: the server looks the challenge up by [challengeId] and
 * authenticates the caller against it with [challengeToken] (the body-transport stand-in for the
 * browser's challenge cookie), so every follow-up call has to carry the pair.
 */
data class MFAChallenge(
  val challengeId: String,
  val challengeToken: String,
  val methods: List<MFAMethod>,
)

/**
 * The two shapes `POST /api/v1/auth/mobile/login` can settle on: `200` with a session, or `202`
 * with a challenge to finish.
 */
sealed interface MobileLoginOutcome {
  data class Authenticated(val profile: UserProfile) : MobileLoginOutcome

  data class MfaRequired(val challenge: MFAChallenge) : MobileLoginOutcome
}

/**
 * `WebAuthnAuthenticationOptions` decoded into raw bytes for the platform passkey API.
 *
 * The wire format carries `challenge` and every `allowCredentials[].id` as base64url text; the
 * decoding happens once in the Data layer so the rest of the app only ever sees `ByteArray`.
 *
 * `equals`/`hashCode` are content-based (arrays compare by value, not identity) so the round-trip
 * tests can assert on a decoded-then-rebuilt value.
 */
class PasskeyRequestOptions(
  val challenge: ByteArray,
  val relyingPartyIdentifier: String,
  val allowedCredentialIDs: List<ByteArray>,
  val userVerification: String,
  val timeoutMilliseconds: Int,
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (other !is PasskeyRequestOptions) return false
    return challenge.contentEquals(other.challenge) &&
      relyingPartyIdentifier == other.relyingPartyIdentifier &&
      allowedCredentialIDs.size == other.allowedCredentialIDs.size &&
      allowedCredentialIDs.zip(other.allowedCredentialIDs).all { (a, b) -> a.contentEquals(b) } &&
      userVerification == other.userVerification &&
      timeoutMilliseconds == other.timeoutMilliseconds
  }

  override fun hashCode(): Int {
    var result = challenge.contentHashCode()
    result = 31 * result + relyingPartyIdentifier.hashCode()
    result = 31 * result + allowedCredentialIDs.sumOf { it.contentHashCode() }
    result = 31 * result + userVerification.hashCode()
    result = 31 * result + timeoutMilliseconds
    return result
  }
}

/**
 * The assertion an authenticator produced, in raw bytes.
 *
 * The Data layer re-encodes them as base64url into `WebAuthnAuthenticationCredential`, matching
 * exactly what the web and iOS clients send (`frontend/src/features/auth/webauthn.ts`): `id` and
 * `rawId` are both the base64url credential ID, `type` is always `public-key`, and `userHandle` is
 * omitted entirely when [userHandle] is `null`.
 *
 * `equals`/`hashCode` are content-based for the same reason as [PasskeyRequestOptions].
 */
class PasskeyAssertionPayload(
  val credentialID: ByteArray,
  val clientDataJSON: ByteArray,
  val authenticatorData: ByteArray,
  val signature: ByteArray,
  val userHandle: ByteArray? = null,
) {
  override fun equals(other: Any?): Boolean {
    if (this === other) return true
    if (other !is PasskeyAssertionPayload) return false
    return credentialID.contentEquals(other.credentialID) &&
      clientDataJSON.contentEquals(other.clientDataJSON) &&
      authenticatorData.contentEquals(other.authenticatorData) &&
      signature.contentEquals(other.signature) &&
      bytesEqual(userHandle, other.userHandle)
  }

  override fun hashCode(): Int {
    var result = credentialID.contentHashCode()
    result = 31 * result + clientDataJSON.contentHashCode()
    result = 31 * result + authenticatorData.contentHashCode()
    result = 31 * result + signature.contentHashCode()
    result = 31 * result + (userHandle?.contentHashCode() ?: 0)
    return result
  }

  private companion object {
    fun bytesEqual(lhs: ByteArray?, rhs: ByteArray?): Boolean = when {
      lhs == null && rhs == null -> true
      lhs == null || rhs == null -> false
      else -> lhs.contentEquals(rhs)
    }
  }
}
