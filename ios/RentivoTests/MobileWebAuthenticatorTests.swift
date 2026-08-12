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

  @MainActor
  @Test func mobileWebAuthenticatorTreatsOnlyTheDismissalAsAUserCancellation() {
    func sessionError(_ code: ASWebAuthenticationSessionError.Code) -> Error {
      ASWebAuthenticationSessionError(
        _nsError: NSError(
          domain: ASWebAuthenticationSessionErrorDomain, code: code.rawValue))
    }

    #expect(MobileWebAuthenticator.isUserCancellation(sessionError(.canceledLogin)))
    #expect(!MobileWebAuthenticator.isUserCancellation(sessionError(.presentationContextInvalid)))
    #expect(!MobileWebAuthenticator.isUserCancellation(LiveAPIError.invalidResponse))
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
