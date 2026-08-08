package app.rentivo.data.api

import app.rentivo.domain.LocalizedError
import java.net.URI
import java.net.URLDecoder

/**
 * The browser authorization handshake, expressed without any platform dependency.
 *
 * Port of the Swift `MobileWebAuthenticationFlow` enum. Everything here is pure so the JVM unit
 * tests can cover the whole protocol: URL building, callback validation, and code extraction. The
 * Android side ([MobileWebAuthenticator]) only owns the Custom Tabs plumbing around it.
 *
 * URLs are plain strings: the caller wraps them in `android.net.Uri` (or `HttpUrl`) at the edge.
 */
object MobileWebAuthenticationFlow {

  /** The app's production origin; the authorization pages live under it. */
  const val PRODUCTION_BASE_URL: String = "https://rentivo.com.br"

  /** Custom scheme the website redirects back to. Declared by the manifest's deep-link filter. */
  const val CALLBACK_SCHEME: String = "rentivo"

  /** Authority of every callback we accept, i.e. `rentivo://auth/…`. */
  const val CALLBACK_HOST: String = "auth"

  private const val AUTHORIZATION_PATH = "/login"
  private const val LOGOUT_PATH = "/mobile-logout"
  private const val AUTHORIZATION_CALLBACK_PATH = "/callback"
  private const val LOGOUT_CALLBACK_PATH = "/logout"
  private const val AUTHORIZATION_STATE_PARAMETER = "mobile_state"
  private const val STATE_PARAMETER = "state"
  private const val CODE_PARAMETER = "code"

  /** `<base>/login?mobile_state=<state>` — the page that mints a one-time authorization code. */
  fun authorizationUrl(baseUrl: String, state: String): String =
    url(baseUrl, AUTHORIZATION_PATH, AUTHORIZATION_STATE_PARAMETER, state)

  /** `<base>/mobile-logout?state=<state>` — clears the shared browser session. */
  fun logoutUrl(baseUrl: String, state: String): String =
    url(baseUrl, LOGOUT_PATH, STATE_PARAMETER, state)

  /**
   * The one-time code carried by [callbackUri], or `null` when the callback is not a well-formed
   * `rentivo://auth/callback` for [expectedState]. An empty `code` is rejected like a missing one.
   */
  fun authorizationCode(callbackUri: String, expectedState: String): String? {
    val query = callback(callbackUri, AUTHORIZATION_CALLBACK_PATH, expectedState) ?: return null
    return queryValue(query, CODE_PARAMETER)?.takeIf { it.isNotEmpty() }
  }

  /** Whether [callbackUri] is the `rentivo://auth/logout` confirmation for [expectedState]. */
  fun isLogoutCallback(callbackUri: String, expectedState: String): Boolean =
    callback(callbackUri, LOGOUT_CALLBACK_PATH, expectedState) != null

  /**
   * Whether [callbackUri] belongs to this flow at all (`rentivo://auth/…`), regardless of state or
   * path. Lets the deep-link entry point tell our callbacks apart from any other app link before
   * deciding whether to consume the intent.
   */
  fun isCallbackUri(callbackUri: String): Boolean {
    val uri = parse(callbackUri) ?: return false
    return uri.scheme.equals(CALLBACK_SCHEME, ignoreCase = true) &&
      uri.host.equals(CALLBACK_HOST, ignoreCase = true)
  }

  private fun url(baseUrl: String, path: String, name: String, value: String): String =
    baseUrl.trimEnd('/') + path + "?" + name + "=" + percentEncode(value)

  /**
   * The raw query of [callbackUri] when it matches scheme, host, [path] and [expectedState]
   * exactly — the Swift `callback(_:path:expectedState:)` guard, returning the query instead of
   * `URLComponents`. Scheme and host compare case-insensitively per RFC 3986.
   */
  private fun callback(callbackUri: String, path: String, expectedState: String): String? {
    val uri = parse(callbackUri) ?: return null
    if (!uri.scheme.equals(CALLBACK_SCHEME, ignoreCase = true)) return null
    if (!uri.host.equals(CALLBACK_HOST, ignoreCase = true)) return null
    if (uri.rawPath != path) return null
    val query = uri.rawQuery
    if (queryValue(query, STATE_PARAMETER) != expectedState) return null
    return query.orEmpty()
  }

  private fun parse(value: String): URI? = runCatching { URI(value) }.getOrNull()

  /**
   * The first value for [name] in a raw query string, percent-decoded. `a&b=1` yields `null` for
   * `a` — a valueless parameter is indistinguishable from a missing one here, matching how the
   * Swift guards treat both.
   */
  private fun queryValue(rawQuery: String?, name: String): String? {
    if (rawQuery.isNullOrEmpty()) return null
    for (pair in rawQuery.split('&')) {
      if (pair.isEmpty()) continue
      val separator = pair.indexOf('=')
      val rawName = if (separator < 0) pair else pair.substring(0, separator)
      if (percentDecode(rawName) != name) continue
      return if (separator < 0) null else percentDecode(pair.substring(separator + 1))
    }
    return null
  }

  /** RFC 3986 encoding: only unreserved characters survive, so any state round-trips verbatim. */
  private fun percentEncode(value: String): String {
    val hex = "0123456789ABCDEF"
    val encoded = StringBuilder()
    for (byte in value.toByteArray(Charsets.UTF_8)) {
      val code = byte.toInt() and 0xFF
      val character = code.toChar()
      if (character in UNRESERVED) {
        encoded.append(character)
      } else {
        encoded.append('%').append(hex[code shr 4]).append(hex[code and 0x0F])
      }
    }
    return encoded.toString()
  }

  /**
   * Percent-decodes a query component. `+` stays a literal plus (it is only a space in
   * `application/x-www-form-urlencoded` bodies, not in URLs), matching `URLComponents`.
   */
  private fun percentDecode(value: String): String? =
    runCatching { URLDecoder.decode(value.replace("+", "%2B"), "UTF-8") }.getOrNull()

  private const val UNRESERVED =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
}

/**
 * The browser handshake produced something we cannot trust: a callback for another state, on
 * another path, or without a code. Mirrors the `LiveAPIError.invalidResponse` the iOS
 * authenticator throws in the same situations, including its PT-BR copy.
 */
class MobileWebAuthenticationException :
  Exception("Não foi possível interpretar a resposta do Rentivo."), LocalizedError {
  override val errorDescription: String
    get() = "Não foi possível interpretar a resposta do Rentivo."
}
