package app.rentivo.data.api

import java.net.URI
import java.net.URLDecoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors ios/RentivoTests/MobileWebAuthenticatorTests.swift. */
class MobileWebAuthenticationFlowTest {

  private val baseUrl = MobileWebAuthenticationFlow.PRODUCTION_BASE_URL

  @Test
  fun `builds production login and logout urls`() {
    val state = "native state/+"

    val login = MobileWebAuthenticationFlow.authorizationUrl(baseUrl, state)
    val logout = MobileWebAuthenticationFlow.logoutUrl(baseUrl, state)

    assertEquals("/login", URI(login).path)
    assertEquals(mapOf("mobile_state" to state), queryParameters(login))
    assertEquals("/mobile-logout", URI(logout).path)
    assertEquals(mapOf("state" to state), queryParameters(logout))
  }

  @Test
  fun `builds urls verbatim for a state that needs no escaping`() {
    assertEquals(
      "https://rentivo.com.br/login?mobile_state=6C4A1E2F",
      MobileWebAuthenticationFlow.authorizationUrl(baseUrl, "6C4A1E2F"),
    )
    assertEquals(
      "https://rentivo.com.br/mobile-logout?state=6C4A1E2F",
      MobileWebAuthenticationFlow.logoutUrl(baseUrl, "6C4A1E2F"),
    )
  }

  @Test
  fun `collapses a trailing slash on the base url`() {
    assertEquals(
      "https://rentivo.com.br/login?mobile_state=abc",
      MobileWebAuthenticationFlow.authorizationUrl("https://rentivo.com.br/", "abc"),
    )
  }

  @Test
  fun `extracts only the expected authorization callback`() {
    val state = "native-state"

    assertEquals(
      "one-time-code",
      MobileWebAuthenticationFlow.authorizationCode(
        "rentivo://auth/callback?code=one-time-code&state=native-state",
        state,
      ),
    )

    val invalid = listOf(
      "other://auth/callback?code=one-time-code&state=native-state",
      "rentivo://other/callback?code=one-time-code&state=native-state",
      "rentivo://auth/logout?code=one-time-code&state=native-state",
      "rentivo://auth/callback?code=one-time-code&state=other-state",
      "rentivo://auth/callback?code=&state=native-state",
      "rentivo://auth/callback?state=native-state",
    )
    for (callback in invalid) {
      assertNull(callback, MobileWebAuthenticationFlow.authorizationCode(callback, state))
    }
  }

  @Test
  fun `accepts only the expected logout callback`() {
    val state = "native-state"

    assertTrue(
      MobileWebAuthenticationFlow.isLogoutCallback("rentivo://auth/logout?state=native-state", state)
    )

    val invalid = listOf(
      "other://auth/logout?state=native-state",
      "rentivo://other/logout?state=native-state",
      "rentivo://auth/callback?state=native-state",
      "rentivo://auth/logout?state=other-state",
      "rentivo://auth/logout",
    )
    for (callback in invalid) {
      assertFalse(callback, MobileWebAuthenticationFlow.isLogoutCallback(callback, state))
    }
  }

  @Test
  fun `round-trips a state that needs percent escaping through the callback`() {
    val state = "native state/+"
    val callback = "rentivo://auth/callback?code=one-time-code&state=native%20state%2F%2B"

    assertEquals(
      "one-time-code",
      MobileWebAuthenticationFlow.authorizationCode(callback, state),
    )
  }

  @Test
  fun `rejects a malformed callback uri instead of throwing`() {
    val state = "native-state"

    assertNull(MobileWebAuthenticationFlow.authorizationCode("not a uri", state))
    assertFalse(MobileWebAuthenticationFlow.isLogoutCallback("not a uri", state))
    assertFalse(MobileWebAuthenticationFlow.isCallbackUri("not a uri"))
  }

  @Test
  fun `accepts a callback carrying characters java net URI rejects`() {
    val state = "native-state"
    // `android.net.Uri` hands these through verbatim; `java.net.URI` throws on every one of them,
    // which used to strand the sign-in with no callback at all.
    val lenient = listOf(
      "rentivo://auth/callback?code=one time code&state=native-state",
      "rentivo://auth/callback?code=a|b&state=native-state",
      "rentivo://auth/callback?code={code}&state=native-state",
    )
    val expected = listOf("one time code", "a|b", "{code}")

    assertEquals(
      expected,
      lenient.map { MobileWebAuthenticationFlow.authorizationCode(it, state) },
    )
    for (callback in lenient) {
      assertTrue(callback, MobileWebAuthenticationFlow.isCallbackUri(callback))
    }
    assertTrue(
      MobileWebAuthenticationFlow.isLogoutCallback(
        "rentivo://auth/logout?state=native-state&x={}",
        state,
      )
    )
  }

  @Test
  fun `matches a percent-encoded callback path like URLComponents does`() {
    val state = "native-state"

    assertEquals(
      "one-time-code",
      MobileWebAuthenticationFlow.authorizationCode(
        "rentivo://auth/%63allback?code=one-time-code&state=native-state",
        state,
      ),
    )
    assertTrue(
      MobileWebAuthenticationFlow.isLogoutCallback(
        "rentivo://auth/log%6Fut?state=native-state",
        state,
      )
    )
    // Decoding the path must not make a *different* path match: `%2F` is an escaped separator, not
    // the start of `/callback`.
    assertNull(
      MobileWebAuthenticationFlow.authorizationCode(
        "rentivo://auth/other%2Fcallback?code=one-time-code&state=native-state",
        state,
      )
    )
  }

  @Test
  fun `ignores userinfo, port and fragment around the callback`() {
    val state = "native-state"

    assertEquals(
      "one-time-code",
      MobileWebAuthenticationFlow.authorizationCode(
        "rentivo://AUTH/callback?code=one-time-code&state=native-state#done",
        state,
      ),
    )
    // A scheme with no authority at all is never one of ours.
    assertFalse(MobileWebAuthenticationFlow.isCallbackUri("rentivo:auth/callback"))
    assertFalse(MobileWebAuthenticationFlow.isCallbackUri("://auth/callback"))
  }

  @Test
  fun `recognizes any rentivo auth uri as belonging to this flow`() {
    assertTrue(MobileWebAuthenticationFlow.isCallbackUri("rentivo://auth/callback?state=other"))
    assertTrue(MobileWebAuthenticationFlow.isCallbackUri("rentivo://auth/logout"))
    assertFalse(MobileWebAuthenticationFlow.isCallbackUri("rentivo://other/callback"))
    assertFalse(MobileWebAuthenticationFlow.isCallbackUri("https://rentivo.com.br/login"))
  }

  /** Decodes a built URL's query the way a server would, so escaping is checked by round trip. */
  private fun queryParameters(url: String): Map<String, String> =
    URI(url).rawQuery.split('&').associate { pair ->
      val separator = pair.indexOf('=')
      val decode = { value: String -> URLDecoder.decode(value.replace("+", "%2B"), "UTF-8") }
      decode(pair.substring(0, separator)) to decode(pair.substring(separator + 1))
    }
}
