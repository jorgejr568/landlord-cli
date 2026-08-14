import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - Base64URL
//
// Every WebAuthn field on the contract travels as unpadded base64url, and the encoding has to
// match `frontend/src/features/auth/webauthn.ts` byte for byte or the server's signature check
// fails on bytes it never received.

@Test func base64URLRoundTripsEveryByteAndUsesTheUnpaddedURLAlphabet() throws {
  let allBytes = Data((0...255).map { UInt8($0) })
  #expect(Base64URL.decode(Base64URL.encode(allBytes)) == allBytes)

  // 0xFB 0xFF encodes to "+/8" in standard base64; the URL alphabet must substitute both.
  #expect(Base64URL.encode(Data([0xFB, 0xFF])) == "-_8")
  #expect(Base64URL.decode("-_8") == Data([0xFB, 0xFF]))

  // Padding is stripped on the way out (the server pads for itself) and re-added on the way in,
  // across all three remainder lengths.
  #expect(Base64URL.encode(Data([0x01])) == "AQ")
  #expect(Base64URL.encode(Data([0x01, 0x02])) == "AQI")
  #expect(Base64URL.encode(Data([0x01, 0x02, 0x03])) == "AQID")
  #expect(Base64URL.decode("AQ") == Data([0x01]))
  #expect(Base64URL.decode("AQI") == Data([0x01, 0x02]))
  #expect(Base64URL.decode("AQID") == Data([0x01, 0x02, 0x03]))

  // Padded input from a laxer producer still decodes, and garbage returns nil rather than trapping.
  #expect(Base64URL.decode("AQ==") == Data([0x01]))
  #expect(Base64URL.decode("!!!") == nil)
}

@Test func mfaMethodCoversExactlyTheMethodsTheLoginServiceEmits() {
  // `login_service._mfa_methods` emits these three strings and no others.
  #expect(Set(MFAMethod.allCases.map(\.rawValue)) == ["totp", "recovery", "passkey"])
  #expect(MFAMethod(rawValue: "sms") == nil)
}

// MARK: - `AuthRepository` forwarding
//
// `AppModel` only ever sees `AuthRepository`, so the live adapter has to translate the Data
// layer's `LiveSession` into the public `UserProfile` *and* record it as the current user — the
// same bookkeeping `exchangeMobileAuthorization` and `restoreSession` do.
//
// The suite is serialized because its tests share one routed `URLProtocol` stub (and its static
// route table), which is also why it keeps a stub class of its own rather than reusing
// `MobileAuthClientTests`': suite serialization does not extend across suites.

@Suite(.serialized)
@MainActor
struct MobileAuthRepositoryTests {

  @Test func mobileLoginAdoptsTheSessionProfileAsTheCurrentUser() async throws {
    RepositoryAuthStubURLProtocol.reset()
    RepositoryAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 200,
      body: #"""
        {"status":"authenticated","credential_transport":"body","access_token":"mobile-token",
         "token_type":"Bearer","expires_in":3600,
         "bootstrap":{"user":{"id":11,"email":"bruno@rentivo.com.br"}}}
        """#
    )
    let store = APIRentivoStore(client: stubbedClient())

    let outcome = try await store.mobileLogin(email: "bruno@rentivo.com.br", password: "segredo")

    #expect(outcome == .authenticated(UserProfile(id: 11, email: "bruno@rentivo.com.br")))
    #expect(store.currentUser == UserProfile(id: 11, email: "bruno@rentivo.com.br"))
  }

  @Test func mobileLoginForwardsTheChallengeWithoutClaimingASession() async throws {
    RepositoryAuthStubURLProtocol.reset()
    RepositoryAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 202,
      body: #"""
        {"status":"mfa_required","credential_transport":"body","challenge_id":"challenge-9",
         "challenge_token":"nonce-9","methods":["totp","recovery"]}
        """#
    )
    let store = APIRentivoStore(client: stubbedClient())

    let outcome = try await store.mobileLogin(email: "bruno@rentivo.com.br", password: "segredo")

    let expected = MFAChallenge(
      challengeId: "challenge-9", challengeToken: "nonce-9", methods: [.totp, .recovery])
    #expect(outcome == .mfaRequired(expected))
    // No session yet: the store must still report the empty placeholder user.
    #expect(store.currentUser == UserProfile(id: 0, email: ""))
  }

  @Test func signupAndEveryMFACompletionAdoptTheResultingProfile() async throws {
    let authenticated = #"""
      {"status":"authenticated","credential_transport":"body","access_token":"mobile-token",
       "token_type":"Bearer","expires_in":3600,
       "bootstrap":{"user":{"id":12,"email":"carla@rentivo.com.br"}}}
      """#
    let expected = UserProfile(id: 12, email: "carla@rentivo.com.br")
    let challenge = MFAChallenge(
      challengeId: "challenge-1", challengeToken: "nonce-1", methods: [.totp, .recovery, .passkey])
    let assertion = PasskeyAssertionPayload(
      credentialID: Data([0x01]), clientDataJSON: Data([0x02]),
      authenticatorData: Data([0x03]), signature: Data([0x04])
    )

    // Each call gets a fresh store, so passing proves that call adopted the profile rather than
    // inheriting it from an earlier one.
    let calls: [(String, @MainActor (APIRentivoStore) async throws -> UserProfile)] = [
      (
        "/api/v1/auth/mobile/signup",
        { try await $0.mobileSignup(email: "carla@rentivo.com.br", password: "segredo") }
      ),
      (
        "/api/v1/auth/mfa/totp/verify",
        { try await $0.verifyTotp(challenge: challenge, code: "123456") }
      ),
      (
        "/api/v1/auth/mfa/recovery/verify",
        { try await $0.verifyRecoveryCode(challenge: challenge, code: "AAAA-BBBB") }
      ),
      (
        "/api/v1/auth/mfa/passkeys/complete",
        { try await $0.completePasskeyAssertion(challenge: challenge, credential: assertion) }
      ),
    ]

    for (path, call) in calls {
      RepositoryAuthStubURLProtocol.reset()
      RepositoryAuthStubURLProtocol.routes[path] = .init(statusCode: 200, body: authenticated)
      let store = APIRentivoStore(client: stubbedClient())

      #expect(try await call(store) == expected, "\(path) should return the authenticated profile")
      #expect(store.currentUser == expected, "\(path) should adopt the authenticated profile")
    }
  }

  @Test func beginPasskeyAssertionForwardsTheDecodedOptions() async throws {
    RepositoryAuthStubURLProtocol.reset()
    RepositoryAuthStubURLProtocol.routes["/api/v1/auth/mfa/passkeys/begin"] = .init(
      statusCode: 200,
      body: """
        {"challenge":"\(Base64URL.encode(Data([0x09, 0x08])))","timeout":45000,
         "rpId":"rentivo.com.br","userVerification":"required","allowCredentials":[]}
        """
    )
    let store = APIRentivoStore(client: stubbedClient())

    let options = try await store.beginPasskeyAssertion(
      challenge: MFAChallenge(challengeId: "c", challengeToken: "t", methods: [.passkey]))

    #expect(
      options
        == PasskeyRequestOptions(
          challenge: Data([0x09, 0x08]), relyingPartyIdentifier: "rentivo.com.br",
          allowedCredentialIDs: [], userVerification: "required", timeoutMilliseconds: 45_000))
  }

  @Test func demoStoreNativeSignInAlwaysSucceedsAsTheDemoUserWithoutAChallenge() async throws {
    let store = MockRentivoStore()
    let demoUser = store.currentUser

    #expect(
      try await store.mobileLogin(email: "qualquer@rentivo.com.br", password: "x")
        == .authenticated(demoUser))
    #expect(try await store.mobileSignup(email: "qualquer@rentivo.com.br", password: "x") == demoUser)

    let challenge = MFAChallenge(challengeId: "c", challengeToken: "t", methods: [.totp])
    #expect(try await store.verifyTotp(challenge: challenge, code: "000000") == demoUser)
    #expect(try await store.verifyRecoveryCode(challenge: challenge, code: "AAAA") == demoUser)
    #expect(try await store.beginPasskeyAssertion(challenge: challenge).allowedCredentialIDs.isEmpty)
    #expect(
      try await store.completePasskeyAssertion(
        challenge: challenge,
        credential: PasskeyAssertionPayload(
          credentialID: Data(), clientDataJSON: Data(), authenticatorData: Data(), signature: Data())
      ) == demoUser)
  }

  private func stubbedClient() -> LiveAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RepositoryAuthStubURLProtocol.self]
    return LiveAPIClient(
      session: URLSession(configuration: configuration), credentials: MemoryCredentialStore())
  }
}

/// Path-routed stub for this suite only; see the suite comment for why it is not shared.
private final class RepositoryAuthStubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Route {
    let statusCode: Int
    let body: String
  }

  nonisolated(unsafe) static var routes: [String: Route] = [:]

  static func reset() { routes = [:] }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    let route =
      Self.routes[path]
      ?? Route(statusCode: 500, body: #"{"detail":"Endpoint inesperado: \#(path)"}"#)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: route.statusCode, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(route.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
