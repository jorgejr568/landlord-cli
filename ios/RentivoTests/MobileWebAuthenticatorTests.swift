import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func mobileWebAuthenticationBuildsProductionLoginAndLogoutURLs() throws {
  let baseURL = try #require(URL(string: "https://rentivo.com.br"))
  let state = "native state/+"

  let login = MobileWebAuthenticationFlow.authorizationURL(baseURL: baseURL, state: state)
  let logout = MobileWebAuthenticationFlow.logoutURL(baseURL: baseURL, state: state)

  #expect(login.path == "/login")
  #expect(URLComponents(url: login, resolvingAgainstBaseURL: false)?.queryItems == [
    URLQueryItem(name: "mobile_state", value: state)
  ])
  #expect(logout.path == "/mobile-logout")
  #expect(URLComponents(url: logout, resolvingAgainstBaseURL: false)?.queryItems == [
    URLQueryItem(name: "state", value: state)
  ])
}

@Test func mobileWebAuthenticationExtractsOnlyTheExpectedAuthorizationCallback() throws {
  let state = "native-state"
  let callback = try #require(URL(string: "rentivo://auth/callback?code=one-time-code&state=native-state"))

  #expect(MobileWebAuthenticationFlow.authorizationCode(from: callback, expectedState: state) == "one-time-code")

  for invalid in [
    "other://auth/callback?code=one-time-code&state=native-state",
    "rentivo://other/callback?code=one-time-code&state=native-state",
    "rentivo://auth/logout?code=one-time-code&state=native-state",
    "rentivo://auth/callback?code=one-time-code&state=other-state",
    "rentivo://auth/callback?code=&state=native-state",
    "rentivo://auth/callback?state=native-state",
  ] {
    let invalidURL = try #require(URL(string: invalid))
    #expect(MobileWebAuthenticationFlow.authorizationCode(from: invalidURL, expectedState: state) == nil)
  }
}

@Test func mobileWebAuthenticationAcceptsOnlyTheExpectedLogoutCallback() throws {
  let state = "native-state"
  let callback = try #require(URL(string: "rentivo://auth/logout?state=native-state"))

  #expect(MobileWebAuthenticationFlow.isLogoutCallback(callback, expectedState: state))

  for invalid in [
    "other://auth/logout?state=native-state",
    "rentivo://other/logout?state=native-state",
    "rentivo://auth/callback?state=native-state",
    "rentivo://auth/logout?state=other-state",
    "rentivo://auth/logout",
  ] {
    let invalidURL = try #require(URL(string: invalid))
    #expect(!MobileWebAuthenticationFlow.isLogoutCallback(invalidURL, expectedState: state))
  }
}

#if canImport(UIKit) || canImport(AppKit)
  import AuthenticationServices

  // Every test below is deliberately left without `@MainActor`: on macOS
  // `ASWebAuthenticationSession` invokes its completion handler on an arbitrary
  // XPC reply queue, so the completion path must stay callable from a
  // nonisolated context. These bodies call the helpers synchronously, which
  // only compiles while that contract holds.

  private func sessionError(_ code: ASWebAuthenticationSessionError.Code) -> Error {
    ASWebAuthenticationSessionError(
      _nsError: NSError(
        domain: ASWebAuthenticationSessionErrorDomain, code: code.rawValue))
  }

  private func isInvalidResponse(_ error: Error?) -> Bool {
    guard let error = error as? LiveAPIError, case .invalidResponse = error else { return false }
    return true
  }

  private func authorizationFailure(callbackURL: URL?, error: Error? = nil) -> Error? {
    guard
      case .failure(let failure) = MobileWebAuthenticator.authorizationResult(
        callbackURL: callbackURL, error: error, expectedState: "native-state")
    else { return nil }
    return failure
  }

  private func logoutFailure(callbackURL: URL?, error: Error? = nil) -> Error? {
    guard
      case .failure(let failure) = MobileWebAuthenticator.logoutResult(
        callbackURL: callbackURL, error: error, expectedState: "native-state")
    else { return nil }
    return failure
  }

  @Test func mobileWebAuthenticatorTreatsOnlyTheDismissalAsAUserCancellation() {
    #expect(MobileWebAuthenticator.isUserCancellation(sessionError(.canceledLogin)))
    #expect(!MobileWebAuthenticator.isUserCancellation(sessionError(.presentationContextInvalid)))
    #expect(!MobileWebAuthenticator.isUserCancellation(LiveAPIError.invalidResponse))
  }

  @Test func mobileWebAuthenticatorResolvesTheAuthorizationCallbackWithoutActorHops() throws {
    let callback = try #require(
      URL(string: "rentivo://auth/callback?code=one-time-code&state=native-state"))

    let result = MobileWebAuthenticator.authorizationResult(
      callbackURL: callback, error: nil, expectedState: "native-state")

    #expect(try result.get() == "one-time-code")
  }

  @Test func mobileWebAuthenticatorRejectsAuthorizationCallbacksItCannotTrust() throws {
    let mismatchedState = try #require(
      URL(string: "rentivo://auth/callback?code=one-time-code&state=other-state"))
    let missingCode = try #require(URL(string: "rentivo://auth/callback?state=native-state"))

    #expect(isInvalidResponse(authorizationFailure(callbackURL: mismatchedState)))
    #expect(isInvalidResponse(authorizationFailure(callbackURL: missingCode)))
    #expect(isInvalidResponse(authorizationFailure(callbackURL: nil)))
  }

  @Test func mobileWebAuthenticatorForwardsTheAuthorizationErrorUnchanged() throws {
    let cancellation = sessionError(.canceledLogin)
    let callback = try #require(
      URL(string: "rentivo://auth/callback?code=one-time-code&state=native-state"))

    // The error wins even when a callback URL is also delivered, so a dismissal
    // still reaches `isUserCancellation` and is silenced instead of surfaced.
    let failure = try #require(authorizationFailure(callbackURL: callback, error: cancellation))
    #expect(MobileWebAuthenticator.isUserCancellation(failure))
    #expect((failure as NSError) == (cancellation as NSError))
  }

  @Test func mobileWebAuthenticatorResolvesTheLogoutCallbackWithoutActorHops() throws {
    let callback = try #require(URL(string: "rentivo://auth/logout?state=native-state"))

    #expect(throws: Never.self) {
      try MobileWebAuthenticator.logoutResult(
        callbackURL: callback, error: nil, expectedState: "native-state"
      ).get()
    }
  }

  @Test func mobileWebAuthenticatorRejectsLogoutCallbacksItCannotTrust() throws {
    let mismatchedState = try #require(URL(string: "rentivo://auth/logout?state=other-state"))
    let cancellation = sessionError(.canceledLogin)

    #expect(isInvalidResponse(logoutFailure(callbackURL: mismatchedState)))
    #expect(isInvalidResponse(logoutFailure(callbackURL: nil)))

    let failure = try #require(logoutFailure(callbackURL: nil, error: cancellation))
    #expect(MobileWebAuthenticator.isUserCancellation(failure))
  }
#endif

#if !canImport(UIKit) && canImport(AppKit)
  @Test func mobileWebAuthenticatorPrefersTheKeyWindowAsPresentationAnchor() {
    final class StubWindow {}
    let key = StubWindow()
    let main = StubWindow()
    let first = StubWindow()

    #expect(MobileWebAuthenticator.preferredAnchor(key: key, main: main, first: first) === key)
    #expect(MobileWebAuthenticator.preferredAnchor(key: nil, main: main, first: first) === main)
    #expect(MobileWebAuthenticator.preferredAnchor(key: nil, main: nil, first: first) === first)
    #expect(
      MobileWebAuthenticator.preferredAnchor(
        key: StubWindow?.none, main: nil, first: nil) == nil)
  }
#endif
