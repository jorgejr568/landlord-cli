package app.rentivo.data.api

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import app.rentivo.domain.PasskeyAssertionPayload
import app.rentivo.domain.PasskeyRequestOptions

/**
 * Runs one WebAuthn assertion ("chave de acesso") for a login challenge through the Android
 * Credential Manager, handing the raw authenticator output back as the Domain payload the Data
 * layer re-encodes for the server. Port of the iOS `PasskeyAssertionController`, which wraps
 * `AuthenticationServices`.
 *
 * All the protocol logic — building the request JSON and parsing the assertion response — lives in
 * the pure [PasskeyAssertionCodec]; this class is only the Credential Manager plumbing around it and
 * so is deliberately not covered by JVM unit tests, exactly like `MobileWebAuthenticator` was for
 * the browser flow.
 *
 * Passkeys are presented against the *website's* relying party (`webauthn_rp_id`), which requires a
 * Digital Asset Links file at `https://<rp>/.well-known/assetlinks.json` vouching for this app —
 * the Android analogue of the iOS associated-domains file. Until that is served the system will
 * simply find no credential; [isUserCancellation] and the UI's graceful degradation keep that from
 * reading as a hard error.
 */
class PasskeyAuthenticator(
  private val credentialManagerFactory: (Context) -> CredentialManager = CredentialManager::create,
) {

  /**
   * Presents the system passkey sheet for [options] and returns the assertion, or throws. The
   * [context] must be an `Activity` so the system UI can attach to it.
   */
  suspend fun assert(
    context: Context,
    options: PasskeyRequestOptions,
  ): PasskeyAssertionPayload {
    val request = GetCredentialRequest(
      listOf(GetPublicKeyCredentialOption(PasskeyAssertionCodec.requestJson(options)))
    )
    val response = credentialManagerFactory(context).getCredential(context, request)
    val credential = response.credential
    if (credential !is PublicKeyCredential) throw PasskeyAssertionException()
    return PasskeyAssertionCodec.assertionPayload(credential.authenticationResponseJson)
  }

  companion object {
    /**
     * Whether [throwable] is the user dismissing the system passkey sheet — an expected outcome the
     * login screen swallows rather than reporting as an error.
     */
    fun isUserCancellation(throwable: Throwable): Boolean =
      throwable is GetCredentialCancellationException

    /**
     * Whether [throwable] is the Credential Manager reporting it has nothing to offer (no matching
     * credential, or the feature being unavailable on this device). The passkey button degrades to
     * a soft, actionable message in these cases instead of a raw stack of platform exceptions.
     */
    fun isUnavailable(throwable: Throwable): Boolean =
      throwable is GetCredentialException && throwable !is GetCredentialCancellationException
  }
}
