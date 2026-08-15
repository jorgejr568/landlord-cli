import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@MainActor
@Test func liveProfileLoadsPixFieldsFromTheSecuritySummaryEndpoint() async throws {
  // Regression test: GET /api/v1/profile only returns `CurrentProfileResponse` ({email}); the
  // pix fields must come from GET /api/v1/security's `profile` (a full `ProfileResponse`).
  // Every profile load used to fail because RemoteProfile required pix fields the endpoint omits.
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: profileSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let profile = try await store.profile()

  #expect(profile.email == "ana@rentivo.com.br")
  #expect(profile.pix == PixConfiguration(key: "chave-abc", merchantName: "Ana", merchantCity: "Sao Paulo"))
}

@MainActor
@Test func liveSecuritySummaryDecodesFractionalSecondTimestamps() async throws {
  // Regression test: the old `ISO8601DateFormatter()` had no fractional-seconds support and fell
  // back to `.distantPast` on failure, so backend timestamps with microseconds decoded as year 1.
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: profileSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let summary = try await store.securitySummary()

  #expect(!summary.setupRequired)
  #expect(summary.organizationEnforced)
  let passkey = try #require(summary.passkeys.first)
  let year = Calendar(identifier: .gregorian).component(.year, from: passkey.createdAt)
  #expect(year == 2026)
  #expect(passkey.createdAt != .distantPast)
}

@MainActor
@Test func liveSecuritySummaryDecodesTimestampsWithoutATimezoneDesignator() async throws {
  // Regression test: passkey rows live in naive `DATETIME` columns, so production served
  // `"2026-07-20T10:15:30"` with no offset. `ISO8601DateFormatter` requires one, so the decode
  // threw and the whole Segurança tab rendered "Não foi possível interpretar a resposta".
  // Those timestamps are São Paulo wall clock, so they must parse in that zone.
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: naiveTimestampSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let summary = try await store.securitySummary()

  let passkey = try #require(summary.passkeys.first)
  var saoPaulo = Calendar(identifier: .gregorian)
  saoPaulo.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
  let parts = saoPaulo.dateComponents([.year, .month, .day, .hour, .minute], from: passkey.createdAt)
  #expect(parts.year == 2026)
  #expect(parts.month == 7)
  #expect(parts.day == 20)
  #expect(parts.hour == 10)
  #expect(parts.minute == 15)

  // A microsecond timestamp without an offset must survive the same way.
  let lastUsedAt = try #require(passkey.lastUsedAt)
  #expect(saoPaulo.component(.hour, from: lastUsedAt) == 18)
}

@MainActor
@Test func liveSecuritySummaryHonoursExplicitOffsetsOverTheLocalFallback() async throws {
  // The offset-less formatters ignore any offset they are handed, so they must stay strictly a
  // fallback: a `Z` timestamp has to keep decoding as UTC, not as São Paulo wall clock.
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: profileSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let summary = try await store.securitySummary()

  let passkey = try #require(summary.passkeys.first)
  // 10:15:30 UTC is 07:15 in São Paulo (UTC-3).
  var saoPaulo = Calendar(identifier: .gregorian)
  saoPaulo.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
  #expect(saoPaulo.component(.hour, from: passkey.createdAt) == 7)
}

@MainActor
@Test func liveListAPIKeysPreservesRevokedKeyHistory() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: profileSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let keys = try await store.listAPIKeys()

  #expect(keys.map(\.name) == ["Ativa", "Revogada"])
  #expect(keys[0].revokedAt == nil)
  #expect(keys[1].revokedAt != nil)
}

@MainActor
@Test func liveAPIKeyOptionsUseServerScopesWorkspacesAndExpirationLimits() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: profileSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let options = try await store.apiKeyOptions()

  #expect(options.scopes == [.profileRead, .billingsRead])
  #expect(options.personalWorkspace.resourceID == .personal)
  #expect(options.organizations.map(\.resourceID) == [WorkspaceID(rawValue: "organization-1")])
  #expect(options.defaultExpirationDays == 30)
  #expect(options.maxExpirationDays == 180)
}

private func profileSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ProfileURLProtocol.self]
  return URLSession(configuration: configuration)
}

private func naiveTimestampSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [NaiveTimestampURLProtocol.self]
  return URLSession(configuration: configuration)
}

/// Serves the payload production actually returned before the backend re-attached the offset:
/// passkey timestamps with no timezone designator.
private final class NaiveTimestampURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch path {
    case "/api/v1/auth/session":
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case "/api/v1/security":
      body = #"""
      {
        "profile": {"email":"ana@rentivo.com.br","pix_key":"","pix_merchant_name":"","pix_merchant_city":""},
        "totp": {"enabled": false, "recovery_codes_remaining": 0},
        "mfa": {"setup_required": false, "organization_enforced": false},
        "passkeys": [
          {"uuid":"passkey-1","name":"iPhone de Ana","created_at":"2026-07-20T10:15:30","last_used_at":"2026-07-20T18:42:11.063639"}
        ]
      }
      """#
    default:
      body = #"{"detail":"Endpoint inesperado: \#(path ?? "nil")"}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class ProfileURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch path {
    case "/api/v1/auth/session":
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case "/api/v1/security":
      body = #"""
      {
        "profile": {"email":"ana@rentivo.com.br","pix_key":"chave-abc","pix_merchant_name":"Ana","pix_merchant_city":"Sao Paulo"},
        "totp": {"enabled": true, "recovery_codes_remaining": 5},
        "mfa": {"setup_required": false, "organization_enforced": true},
        "passkeys": [
          {"uuid":"passkey-1","name":"iPhone de Ana","created_at":"2026-07-20T10:15:30.123456+00:00","last_used_at": null}
        ]
      }
      """#
    case "/api/v1/api-keys":
      body = #"""
      {"items": [
        {"uuid":"key-1","name":"Ativa","hint":"rntv-v1-ab••cd","scopes":["profile:read"],"grants":[{"resource_type":"user","resource_id":"personal","available":true}],"expires_at":"2026-12-31T23:59:59.000000+00:00","last_used_at": null,"created_at":"2026-01-01T00:00:00.000000+00:00","revoked_at": null},
        {"uuid":"key-2","name":"Revogada","hint":"rntv-v1-ef••gh","scopes":["profile:read"],"grants":[{"resource_type":"user","resource_id":"personal","available":true}],"expires_at":"2026-12-31T23:59:59.000000+00:00","last_used_at": null,"created_at":"2026-01-01T00:00:00.000000+00:00","revoked_at":"2026-02-01T00:00:00.000000+00:00"}
      ]}
      """#
    case "/api/v1/api-keys/options":
      body = #"{"scopes":["profile:read","unknown:scope","billings:read"],"personal_workspace":{"resource_type":"user","resource_id":"personal"},"organizations":[{"resource_type":"organization","resource_id":"organization-1","name":"Horizonte"}],"default_expiration_days":30,"max_expiration_days":180}"#
    default:
      body = #"{"detail":"Endpoint inesperado: \#(path ?? "nil")"}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
