import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - Native (Turnstile-free) authentication against `/api/v1/auth/mobile/*`
//
// These cover the wire contract the SwiftUI login flow depends on: which HTTP status means what,
// how a problem document becomes a PT-BR `LiveAPIError`, and the exact JSON the MFA follow-ups
// put on the wire (body transport, `challenge_id` + `challenge_token`, base64url WebAuthn fields).
//
// Unlike the rest of this suite, which gives every test its own `URLProtocol` subclass to keep
// Swift Testing's default parallelism from crossing static state, this file shares one routed stub
// and serializes the suite instead — there are enough scenarios here that a subclass apiece would
// bury the assertions.

@Suite(.serialized)
struct MobileAuthClientTests {

  // MARK: Login outcomes

  @Test func mobileLoginReturnsASessionOnHTTP200AndPersistsTheBearerToken() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 200, body: authenticatedBody)
    let credentials = MemoryCredentialStore()
    let client = LiveAPIClient(session: stubbedSession(), credentials: credentials)

    let outcome = try await client.mobileLogin(email: "ana@rentivo.com.br", password: "segredo")

    guard case .authenticated(let session) = outcome else {
      Issue.record("Expected .authenticated, got \(outcome)")
      return
    }
    #expect(session.accessToken == "mobile-token")
    #expect(session.profile == UserProfile(id: 7, email: "ana@rentivo.com.br"))
    #expect(await credentials.readAccessToken() == "mobile-token")

    // The mobile endpoints take credentials only — no Turnstile token, no CSRF header.
    let body = try #require(MobileAuthStubURLProtocol.capturedBodies["/api/v1/auth/mobile/login"])
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["email"] as? String == "ana@rentivo.com.br")
    #expect(json["password"] as? String == "segredo")
    #expect(json.count == 2)
  }

  @Test func mobileLoginReturnsAChallengeOnHTTP202AndDropsUnknownMFAMethods() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 202,
      body: #"""
        {"status":"mfa_required","credential_transport":"body","challenge_id":"challenge-1",
         "challenge_token":"nonce-1","methods":["totp","sms","passkey","recovery"]}
        """#
    )
    let credentials = MemoryCredentialStore()
    let client = LiveAPIClient(session: stubbedSession(), credentials: credentials)

    let outcome = try await client.mobileLogin(email: "ana@rentivo.com.br", password: "segredo")

    guard case .mfaRequired(let challenge) = outcome else {
      Issue.record("Expected .mfaRequired, got \(outcome)")
      return
    }
    #expect(challenge.challengeId == "challenge-1")
    #expect(challenge.challengeToken == "nonce-1")
    // "sms" is not a method this build can present, so it is dropped rather than crashing or
    // leaking through; the known methods keep their server order.
    #expect(challenge.methods == [.totp, .passkey, .recovery])
    // A challenge is not a session: nothing may be persisted yet.
    #expect(await credentials.readAccessToken() == nil)
  }

  @Test func mobileLoginRejectsAChallengeThatCarriesNoBodyTransportToken() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 202,
      body: #"{"status":"mfa_required","credential_transport":"cookie","challenge_id":"c","methods":["totp"]}"#
    )
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    await #expect(throws: LiveAPIError.invalidResponse) {
      _ = try await client.mobileLogin(email: "ana@rentivo.com.br", password: "segredo")
    }
  }

  // MARK: Error mapping

  @Test func mobileLoginSurfacesTheInvalidCredentialsProblemDetail() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 401,
      body: #"{"type":"about:blank","title":"Não autorizado","status":401,"code":"invalid_credentials","detail":"E-mail ou senha inválidos.","request_id":"r1"}"#
    )
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    let error = await #expect(throws: LiveAPIError.self) {
      _ = try await client.mobileLogin(email: "ana@rentivo.com.br", password: "errada")
    }

    // A 401 here is a rejected credential, not an expired session: it must stay a `.server`
    // error carrying the server's message, and must not trip the session-expiry path.
    #expect(error?.errorDescription == "E-mail ou senha inválidos.")
    #expect(error?.statusCode == 401)
  }

  @Test func mobileLoginSurfacesTheRateLimitProblemDetail() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/login"] = .init(
      statusCode: 429,
      body: #"{"type":"about:blank","title":"Muitas tentativas","status":429,"code":"login_rate_limited","detail":"Muitas tentativas. Aguarde um momento antes de tentar novamente.","request_id":"r2"}"#
    )
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    let error = await #expect(throws: LiveAPIError.self) {
      _ = try await client.mobileLogin(email: "ana@rentivo.com.br", password: "segredo")
    }

    #expect(error?.errorDescription == "Muitas tentativas. Aguarde um momento antes de tentar novamente.")
    #expect(error?.statusCode == 429)
  }

  // MARK: Signup

  @Test func mobileSignupReturnsASessionAndSurfacesTheDuplicateEmailProblem() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/signup"] = .init(
      statusCode: 200, body: authenticatedBody)
    let credentials = MemoryCredentialStore()
    let client = LiveAPIClient(session: stubbedSession(), credentials: credentials)

    let session = try await client.mobileSignup(email: "ana@rentivo.com.br", password: "segredo")
    #expect(session.profile.email == "ana@rentivo.com.br")
    #expect(await credentials.readAccessToken() == "mobile-token")

    MobileAuthStubURLProtocol.routes["/api/v1/auth/mobile/signup"] = .init(
      statusCode: 400,
      body: #"{"type":"about:blank","title":"E-mail em uso","status":400,"code":"email_already_registered","detail":"Este e-mail já está cadastrado.","request_id":"r3"}"#
    )
    let rejecting = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    let error = await #expect(throws: LiveAPIError.self) {
      _ = try await rejecting.mobileSignup(email: "ana@rentivo.com.br", password: "segredo")
    }
    #expect(error?.errorDescription == "Este e-mail já está cadastrado.")
    #expect(error?.statusCode == 400)
  }

  // MARK: MFA code verification

  @Test func verifyTotpPostsTheBodyTransportChallengePairAndReturnsTheSession() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/totp/verify"] = .init(
      statusCode: 200, body: authenticatedBody)
    let credentials = MemoryCredentialStore()
    let client = LiveAPIClient(session: stubbedSession(), credentials: credentials)

    let session = try await client.verifyTotp(challenge: challenge, code: "123456")

    #expect(session.accessToken == "mobile-token")
    #expect(await credentials.readAccessToken() == "mobile-token")
    let body = try #require(MobileAuthStubURLProtocol.capturedBodies["/api/v1/auth/mfa/totp/verify"])
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    // `challenge_id` names the challenge row and `challenge_token` authenticates against it in
    // place of the browser's challenge cookie — the server requires both.
    #expect(json["credential_transport"] as? String == "body")
    #expect(json["challenge_id"] as? String == "challenge-1")
    #expect(json["challenge_token"] as? String == "nonce-1")
    #expect(json["code"] as? String == "123456")
  }

  @Test func verifyRecoveryCodeUsesTheRecoveryRouteAndSurfacesRejectedCodes() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/recovery/verify"] = .init(
      statusCode: 200, body: authenticatedBody)
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    _ = try await client.verifyRecoveryCode(challenge: challenge, code: "AAAA-BBBB")

    let body = try #require(
      MobileAuthStubURLProtocol.capturedBodies["/api/v1/auth/mfa/recovery/verify"])
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["code"] as? String == "AAAA-BBBB")
    #expect(json["challenge_id"] as? String == "challenge-1")

    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/recovery/verify"] = .init(
      statusCode: 401,
      body: #"{"type":"about:blank","title":"Não autorizado","status":401,"code":"invalid_mfa_code","detail":"Código de verificação inválido.","request_id":"r4"}"#
    )
    let rejecting = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    let error = await #expect(throws: LiveAPIError.self) {
      _ = try await rejecting.verifyRecoveryCode(challenge: challenge, code: "ZZZZ-ZZZZ")
    }
    #expect(error?.errorDescription == "Código de verificação inválido.")
    #expect(error?.statusCode == 401)
  }

  // MARK: Passkey assertion

  @Test func beginPasskeyAssertionDecodesBase64URLOptionsIntoAuthenticationServicesBytes() async throws {
    MobileAuthStubURLProtocol.reset()
    // "challenge!" and "credential" as unpadded base64url; "credential" happens to contain a `-`
    // and `_` substitution target, which is exactly what the alphabet swap has to survive.
    let challengeBytes = Data("challenge!".utf8)
    let credentialBytes = Data([0xFF, 0xFE, 0xFD, 0x03, 0xE7])
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/passkeys/begin"] = .init(
      statusCode: 200,
      body: """
        {"challenge":"\(Base64URL.encode(challengeBytes))","timeout":60000,
         "rpId":"rentivo.com.br","userVerification":"preferred",
         "allowCredentials":[{"id":"\(Base64URL.encode(credentialBytes))","type":"public-key","transports":["internal"]}]}
        """
    )
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    let options = try await client.beginPasskeyAssertion(challenge: challenge)

    #expect(options.challenge == challengeBytes)
    #expect(options.relyingPartyIdentifier == "rentivo.com.br")
    #expect(options.allowedCredentialIDs == [credentialBytes])
    #expect(options.userVerification == "preferred")
    #expect(options.timeoutMilliseconds == 60_000)

    let body = try #require(MobileAuthStubURLProtocol.capturedBodies["/api/v1/auth/mfa/passkeys/begin"])
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["credential_transport"] as? String == "body")
    #expect(json["challenge_token"] as? String == "nonce-1")
  }

  @Test func beginPasskeyAssertionRejectsOptionsThatAreNotValidBase64URL() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/passkeys/begin"] = .init(
      statusCode: 200,
      body: #"{"challenge":"!!!not base64!!!","timeout":60000,"rpId":"rentivo.com.br","userVerification":"preferred","allowCredentials":[]}"#
    )
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    await #expect(throws: LiveAPIError.invalidResponse) {
      _ = try await client.beginPasskeyAssertion(challenge: challenge)
    }
  }

  @Test func completePasskeyAssertionEncodesTheAssertionExactlyAsTheWebClientDoes() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/passkeys/complete"] = .init(
      statusCode: 200, body: authenticatedBody)
    let credentials = MemoryCredentialStore()
    let client = LiveAPIClient(session: stubbedSession(), credentials: credentials)
    let payload = PasskeyAssertionPayload(
      credentialID: Data([0xFF, 0xFE, 0xFD, 0x03, 0xE7]),
      clientDataJSON: Data(#"{"type":"webauthn.get"}"#.utf8),
      authenticatorData: Data([0x01, 0x02, 0x03]),
      signature: Data([0xAA, 0xBB]),
      userHandle: Data([0x07])
    )

    let session = try await client.completePasskeyAssertion(challenge: challenge, credential: payload)
    #expect(session.accessToken == "mobile-token")
    #expect(await credentials.readAccessToken() == "mobile-token")

    let body = try #require(
      MobileAuthStubURLProtocol.capturedBodies["/api/v1/auth/mfa/passkeys/complete"])
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["credential_transport"] as? String == "body")
    #expect(json["challenge_id"] as? String == "challenge-1")
    let credential = try #require(json["credential"] as? [String: Any])
    #expect(credential["type"] as? String == "public-key")
    // The web client sends `id` and `rawId` as the same base64url credential ID; the server's
    // passkey lookup keys off `credential.id`, so the two must agree.
    #expect(credential["id"] as? String == Base64URL.encode(payload.credentialID))
    #expect(credential["rawId"] as? String == credential["id"] as? String)
    let response = try #require(credential["response"] as? [String: Any])
    #expect(Base64URL.decode(try #require(response["clientDataJSON"] as? String)) == payload.clientDataJSON)
    #expect(Base64URL.decode(try #require(response["authenticatorData"] as? String)) == payload.authenticatorData)
    #expect(Base64URL.decode(try #require(response["signature"] as? String)) == payload.signature)
    #expect(Base64URL.decode(try #require(response["userHandle"] as? String)) == payload.userHandle)
  }

  @Test func completePasskeyAssertionOmitsUserHandleWhenTheAuthenticatorSuppliedNone() async throws {
    MobileAuthStubURLProtocol.reset()
    MobileAuthStubURLProtocol.routes["/api/v1/auth/mfa/passkeys/complete"] = .init(
      statusCode: 200, body: authenticatedBody)
    let client = LiveAPIClient(session: stubbedSession(), credentials: MemoryCredentialStore())

    _ = try await client.completePasskeyAssertion(
      challenge: challenge,
      credential: PasskeyAssertionPayload(
        credentialID: Data([0x01]), clientDataJSON: Data([0x02]),
        authenticatorData: Data([0x03]), signature: Data([0x04])
      )
    )

    let body = try #require(
      MobileAuthStubURLProtocol.capturedBodies["/api/v1/auth/mfa/passkeys/complete"])
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let response = try #require(
      (json["credential"] as? [String: Any])?["response"] as? [String: Any])
    #expect(response["userHandle"] == nil)
  }
}

// MARK: - Fixtures

private let authenticatedBody = #"""
  {"status":"authenticated","credential_transport":"body","access_token":"mobile-token",
   "token_type":"Bearer","expires_in":3600,
   "bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}
  """#

private let challenge = MFAChallenge(
  challengeId: "challenge-1", challengeToken: "nonce-1", methods: [.totp, .recovery, .passkey])

private func stubbedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [MobileAuthStubURLProtocol.self]
  return URLSession(configuration: configuration)
}

/// A path-routed stub: tests register a status code and body per path, and the request bodies are
/// captured so the JSON actually put on the wire can be asserted against the contract. Private to
/// this file — suite serialization does not extend across suites, so the static state must not be
/// reachable from tests that run in parallel with these.
private final class MobileAuthStubURLProtocol: URLProtocol, @unchecked Sendable {
  struct Route {
    let statusCode: Int
    let body: String
  }

  nonisolated(unsafe) static var routes: [String: Route] = [:]
  nonisolated(unsafe) static var capturedBodies: [String: Data] = [:]

  static func reset() {
    routes = [:]
    capturedBodies = [:]
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    if let body = Self.requestBody(from: request) {
      Self.capturedBodies[path] = body
    }
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

  /// `URLSession` moves a JSON body onto `httpBodyStream` before the protocol sees it, so the
  /// stream has to be drained to recover what was sent.
  static func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
