package app.rentivo.data.api

import app.rentivo.data.DownloadedFileStore
import app.rentivo.domain.DownloadedFile
import app.rentivo.domain.LocalizedError
import app.rentivo.domain.UserProfile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.PortUnreachableException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class LiveSession(val accessToken: String, val profile: UserProfile)

/** The error model every live API call fails with, carrying user-facing PT-BR copy. */
sealed class LiveAPIError(message: String) : Exception(message), LocalizedError {

  override val errorDescription: String get() = message.orEmpty()

  /** Only [Server] carries the originating HTTP status; everything else answers `null`. */
  open val statusCode: Int? get() = null

  class Server(message: String, override val statusCode: Int? = null) : LiveAPIError(message)

  object InvalidResponse : LiveAPIError("Não foi possível interpretar a resposta do Rentivo.")

  object SessionExpired : LiveAPIError("Sua sessão expirou. Entre novamente para continuar.")
}

/**
 * The single HTTP boundary to the Rentivo API: bearer-token auth, PT-BR error translation, and
 * ownership of the credential's lifetime.
 */
class LiveAPIClient(
  private val baseUrl: HttpUrl = PRODUCTION_URL,
  private val credentials: CredentialStore,
  private val downloads: DownloadedFileStore,
  private val client: OkHttpClient = defaultClient(),
) {

  /**
   * The in-memory copy of the credential. Every mutation happens on a single logical flow (sign
   * in, restore, invalidate, sign out) but may be observed from another dispatcher thread, so the
   * field is volatile — the Kotlin analogue of the `actor` isolation the iOS client relies on.
   */
  @Volatile
  private var accessToken: String? = null

  private val sessionExpiredEvents = MutableSharedFlow<Unit>(
    replay = 0,
    extraBufferCapacity = 1,
    onBufferOverflow = BufferOverflow.DROP_OLDEST,
  )

  /**
   * Emits whenever this client observes a 401 response while serving an authenticated request.
   * `AppModel` collects it to move the app back to the anonymous state; emitting is harmless if
   * nothing is collecting (e.g. before the app has authenticated).
   */
  val sessionExpired: SharedFlow<Unit> = sessionExpiredEvents

  suspend fun exchangeMobileAuthorization(code: String): LiveSession {
    val data = send(
      path = "/api/v1/auth/mobile/exchange",
      method = "POST",
      body = apiJson.encodeToString(MobileAuthorizationExchangeRequest(code)).toByteArray(),
      token = null,
    )
    val response = decodeOrInvalid<LoginResponse>(data)
    val accessToken = response.accessToken
    val user = response.bootstrap?.user
    if (response.credentialTransport != "body" || accessToken == null || user == null) {
      throw LiveAPIError.InvalidResponse
    }
    this.accessToken = accessToken
    credentials.saveAccessToken(accessToken)
    return LiveSession(
      accessToken = accessToken,
      profile = UserProfile(id = user.id, email = user.email),
    )
  }

  suspend fun restoreSession(): LiveSession? {
    val storedToken = credentials.readAccessToken() ?: return null
    val data = try {
      send(path = "/api/v1/auth/session", method = "GET", body = null, token = storedToken)
    } catch (error: LiveAPIError) {
      if (error.statusCode != 401) throw error
      invalidateSession()
      return null
    }
    val response = decodeOrInvalid<SessionResponse>(data)
    accessToken = storedToken
    return LiveSession(
      accessToken = storedToken,
      profile = UserProfile(id = response.bootstrap.user.id, email = response.bootstrap.user.email),
    )
  }

  suspend fun request(
    path: String,
    method: String = "GET",
    body: ByteArray? = null,
    contentType: String = "application/json",
  ): ByteArray {
    val accessToken = this.accessToken ?: throw LiveAPIError.SessionExpired
    val builder = Request.Builder()
      .url(urlFor(path))
      .method(method, requestBody(body, method, contentType))
      .header("Accept", "application/json")
      .header("Authorization", "Bearer $accessToken")
      .header("Cache-Control", NO_STORE)
    val result = perform(builder.build())
    if (result.statusCode == 401) {
      invalidateSession()
      throw LiveAPIError.SessionExpired
    }
    if (result.statusCode !in 200..299) {
      throw LiveAPIError.Server(
        message = problemDetail(result.payload),
        statusCode = result.statusCode,
      )
    }
    return result.payload
  }

  suspend fun download(
    path: String,
    filename: String,
    mediaType: String = "application/pdf",
  ): DownloadedFile {
    val accessToken = this.accessToken ?: throw LiveAPIError.SessionExpired
    val request = Request.Builder()
      .url(urlFor(path))
      .get()
      .header("Authorization", "Bearer $accessToken")
      .header("Accept", mediaType)
      .header("Cache-Control", NO_STORE)
      .build()
    val result = perform(request)
    if (result.statusCode == 401) {
      invalidateSession()
      throw LiveAPIError.SessionExpired
    }
    if (result.statusCode !in 200..299) {
      // Unlike `request()` this never attempts to read a problem document: every non-2xx/non-401
      // status collapses to one fixed message, and no status code is kept.
      throw LiveAPIError.Server(message = "Não foi possível baixar o arquivo.")
    }
    val responseMediaType = (result.contentType ?: mediaType).substringBefore(";")
    val resolvedFilename = if (filename.contains(".")) {
      filename
    } else {
      "$filename.${fileExtension(responseMediaType)}"
    }
    val destination = downloads.makeDestination(resolvedFilename.substringAfterLast('.', ""))
    destination.writeBytes(result.payload)
    return DownloadedFile(
      file = destination,
      filename = resolvedFilename,
      mediaType = responseMediaType,
    )
  }

  /** Drops the session deliberately. Unlike [invalidateSession] this emits no expiry event. */
  suspend fun logout() {
    accessToken = null
    deleteStoredCredential()
    purgeLocalArtifacts()
  }

  /**
   * Clears the in-memory token and the persisted credential, then notifies any collectors (see
   * `AppModel`) that the session is no longer valid.
   */
  private suspend fun invalidateSession() {
    accessToken = null
    deleteStoredCredential()
    purgeLocalArtifacts()
    sessionExpiredEvents.tryEmit(Unit)
  }

  /** Best effort: an unreachable platform store must not stop the session from being dropped. */
  private suspend fun deleteStoredCredential() {
    try {
      credentials.deleteAccessToken()
    } catch (error: CancellationException) {
      throw error
    } catch (error: Exception) {
      // Ignored on purpose — the in-memory token is already gone.
    }
  }

  /**
   * Drops what an authenticated session leaves behind on disk: documents the user downloaded
   * through the share sheet. There is no HTTP response cache to clear — [defaultClient] installs
   * none, so nothing an authenticated request returned was ever written to disk by the transport.
   */
  private fun purgeLocalArtifacts() {
    downloads.purge()
  }

  private fun fileExtension(mediaType: String): String = when (mediaType.lowercase()) {
    "application/pdf" -> "pdf"
    "image/jpeg" -> "jpg"
    "image/png" -> "png"
    "image/heic" -> "heic"
    "text/plain" -> "txt"
    else -> "bin"
  }

  /**
   * The pre-authentication transport, used by the two `/auth` calls. It deliberately skips the
   * 401 handling in [request]: there is no session to invalidate yet, and [restoreSession] needs
   * to see the status code to decide whether the *stored* credential should be dropped.
   */
  private suspend fun send(
    path: String,
    method: String,
    body: ByteArray?,
    token: String?,
  ): ByteArray {
    val builder = Request.Builder()
      .url(urlFor(path))
      .method(method, requestBody(body, method, "application/json"))
      .header("Accept", "application/json")
      .header("Cache-Control", NO_STORE)
    if (token != null) builder.header("Authorization", "Bearer $token")
    val result = perform(builder.build())
    if (result.statusCode !in 200..299) {
      throw LiveAPIError.Server(
        message = problemDetail(result.payload),
        statusCode = result.statusCode,
      )
    }
    return result.payload
  }

  /** An error body that is not a problem document (a proxy's HTML 502, say) still needs copy. */
  private fun problemDetail(payload: ByteArray): String {
    val detail = try {
      apiJson.decodeFromString<RemoteProblem>(payload.decodeToString()).detail
    } catch (error: IllegalArgumentException) {
      // `SerializationException` is an `IllegalArgumentException`; so is a malformed-input failure.
      null
    }
    return detail ?: "Não foi possível concluir a solicitação."
  }

  private fun urlFor(path: String): HttpUrl =
    baseUrl.newBuilder().addPathSegments(path.trimStart('/')).build()

  private fun requestBody(body: ByteArray?, method: String, contentType: String) = when {
    body != null -> body.toRequestBody(contentType.toMediaTypeOrNull())
    // OkHttp requires a body for these verbs; the API has several body-less POSTs (logout,
    // regenerate, TOTP setup, invitation accept/decline). An empty body carries no Content-Type,
    // matching the iOS client, which only sets one when it actually has a payload.
    method in METHODS_REQUIRING_BODY -> ByteArray(0).toRequestBody(null)
    else -> null
  }

  private class HTTPResult(val statusCode: Int, val contentType: String?, val payload: ByteArray)

  private suspend fun perform(request: Request): HTTPResult = performRaw(request).use { response ->
    HTTPResult(
      statusCode = response.code,
      contentType = response.header("Content-Type"),
      payload = response.body?.bytes() ?: ByteArray(0),
    )
  }

  private suspend fun performRaw(request: Request): Response =
    suspendCancellableCoroutine { continuation ->
      val call = client.newCall(request)
      continuation.invokeOnCancellation { call.cancel() }
      call.enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) {
          continuation.resumeWithException(transportError(e))
        }

        override fun onResponse(call: Call, response: Response) {
          continuation.resume(response)
        }
      })
    }

  /**
   * Translates a transport failure (thrown before any HTTP response arrives) into a
   * [LiveAPIError] carrying an actionable PT-BR message. Without this, an `IOException`
   * propagates raw and the login screen and app-wide error mapping fall through to a generic
   * message with no connectivity/retry cue.
   */
  private fun transportError(error: IOException): Throwable = when (error) {
    is SocketTimeoutException -> LiveAPIError.Server(
      message = "O Rentivo demorou para responder. Verifique sua conexão e tente novamente."
    )

    is UnknownHostException, is ConnectException, is NoRouteToHostException,
    is PortUnreachableException, is SocketException,
    -> LiveAPIError.Server(
      message = "Sem conexão com o Rentivo. Verifique sua internet e tente novamente."
    )

    else -> LiveAPIError.Server(message = "Não foi possível conectar ao Rentivo. Tente novamente.")
  }

  companion object {
    val PRODUCTION_URL: HttpUrl = "https://rentivo.com.br".toHttpUrl()

    private const val NO_STORE = "no-store"
    private val METHODS_REQUIRING_BODY = setOf("POST", "PUT", "PATCH")

    /**
     * The app's default client. It bounds each request so a stalled connection (a dropped mobile
     * network, a wedged proxy) fails fast and stays retryable instead of freezing the UI, and it
     * installs no response cache at all: authenticated payloads — PIX details on a billing, tenant
     * names and e-mail addresses on a contact, downloaded documents — must never be written into
     * the app's storage purely as a side effect of the transport, and a cached "pending"
     * `pdf_render_status` would make the render poll re-read its own answer forever. The app is a
     * thin client over a live API with no offline mode, so nothing is lost by dropping the cache.
     */
    fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
      .connectTimeout(30, TimeUnit.SECONDS)
      .readTimeout(30, TimeUnit.SECONDS)
      .writeTimeout(30, TimeUnit.SECONDS)
      .callTimeout(30, TimeUnit.SECONDS)
      .cache(null)
      .build()
  }
}

/**
 * The server answered, but not in a shape this build understands. The raw serialization failure is
 * never user-facing copy, so it always becomes [LiveAPIError.InvalidResponse].
 */
internal inline fun <reified T> decodeOrInvalid(payload: ByteArray): T = try {
  apiJson.decodeFromString<T>(payload.decodeToString())
} catch (error: IllegalArgumentException) {
  // `SerializationException` is an `IllegalArgumentException`; so is a malformed-input failure.
  throw LiveAPIError.InvalidResponse
}

@Serializable
internal data class LoginResponse(
  @SerialName("credential_transport") val credentialTransport: String,
  @SerialName("access_token") val accessToken: String? = null,
  val bootstrap: BootstrapResponse? = null,
)

@Serializable
internal data class SessionResponse(val bootstrap: BootstrapResponse)

@Serializable
internal data class BootstrapResponse(val user: BootstrapUser)

@Serializable
internal data class BootstrapUser(val id: Int, val email: String)

@Serializable
internal data class MobileAuthorizationExchangeRequest(
  @SerialName("authorization_code") val authorizationCode: String,
)
