import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@MainActor
@Test func liveOrganizationListHydratesMembersForTheOrganizationCardCount() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: organizationSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let organization = try #require(try await store.listOrganizations().first)

  #expect(organization.members.map(\.userID) == [7, 11])
}

@MainActor
@Test func liveInviteMemberUsesTheRealOrganizationNameInsteadOfAPlaceholder() async throws {
  // Regression test: inviteMember used to hardcode organizationName to "Organização".
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: organizationSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let invitation = try await store.inviteMember(
    organizationID: OrganizationID(rawValue: "organization-1"), email: "bruno@rentivo.com.br", role: .viewer
  )

  #expect(invitation.organizationName == "Horizonte")
  #expect(invitation.email == "bruno@rentivo.com.br")
}

@MainActor
@Test func liveInviteMemberFallsBackToThePlaceholderNameWhenTheEnrichmentGetFails() async throws {
  // The name lookup is best effort and overlaps the POST: a caller who may invite but not read the
  // organization still gets the invitation the server created, under the placeholder name.
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: failingOrganizationGetSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let invitation = try await store.inviteMember(
    organizationID: OrganizationID(rawValue: "organization-1"), email: "bruno@rentivo.com.br", role: .viewer
  )

  #expect(invitation.organizationName == "Organização")
  #expect(invitation.id == InvitationID(rawValue: "invite-1"))
  #expect(invitation.email == "bruno@rentivo.com.br")
}

@MainActor
@Test func liveInviteMemberThrowsThePostErrorEvenThoughTheNameLookupSucceeds() async throws {
  // The mirror image: nothing was created, so the failure has to reach the caller instead of being
  // absorbed the way the name lookup's is.
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: failingInvitePostSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())

  do {
    _ = try await store.inviteMember(
      organizationID: OrganizationID(rawValue: "organization-1"), email: "bruno@rentivo.com.br", role: .viewer
    )
    Issue.record("Expected the stubbed 403 invite POST to throw")
  } catch let error as LiveAPIError {
    guard case .server(let message, let statusCode) = error else {
      Issue.record("Expected .server, got \(error)")
      return
    }
    #expect(message == "Você não pode convidar membros nesta organização.")
    #expect(statusCode == 403)
  }
}

private func failingOrganizationGetSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FailingOrganizationGetURLProtocol.self]
  return URLSession(configuration: configuration)
}

/// The invite POST succeeds while the organization GET that only supplies the display name 403s.
private final class FailingOrganizationGetURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let statusCode: Int
    let body: String
    switch (request.httpMethod, path) {
    case ("GET", "/api/v1/auth/session"):
      statusCode = 200
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("POST", "/api/v1/organizations/organization-1/invites"):
      statusCode = 200
      body = #"{"uuid":"invite-1","invited_email":"bruno@rentivo.com.br","role":"viewer","status":"pending"}"#
    case ("GET", "/api/v1/organizations/organization-1"):
      statusCode = 403
      body = #"{"code":"forbidden","detail":"Você não tem acesso a esta organização."}"#
    default:
      statusCode = 500
      body = #"{"detail":"Endpoint inesperado: \#(request.httpMethod ?? "?") \#(path ?? "nil")"}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: statusCode, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func failingInvitePostSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FailingInvitePostURLProtocol.self]
  return URLSession(configuration: configuration)
}

/// The name lookup succeeds while the invite POST itself 403s.
private final class FailingInvitePostURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let statusCode: Int
    let body: String
    switch (request.httpMethod, path) {
    case ("GET", "/api/v1/auth/session"):
      statusCode = 200
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("GET", "/api/v1/organizations/organization-1"):
      statusCode = 200
      body = #"{"uuid":"organization-1","name":"Horizonte","enforce_mfa":false,"current_role":"viewer","capabilities":{"can_manage":false,"can_invite":false,"can_create_billing":false,"can_view_billing_stats":true},"settings":null,"members":[{"user_id":7,"email":"ana@rentivo.com.br","role":"viewer"}]}"#
    case ("POST", "/api/v1/organizations/organization-1/invites"):
      statusCode = 403
      body = #"{"code":"forbidden","detail":"Você não pode convidar membros nesta organização.","fields":{}}"#
    default:
      statusCode = 500
      body = #"{"detail":"Endpoint inesperado: \#(request.httpMethod ?? "?") \#(path ?? "nil")"}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: statusCode, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@MainActor
@Test func liveCreateOrganizationSendsPixAtomicallyInThePost() async throws {
  OrganizationURLProtocol.createBody = nil
  OrganizationURLProtocol.patchRequests = 0
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: organizationSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let draft = OrganizationDraft(
    name: "Nova Org",
    pix: PixConfiguration(key: "chave-pix", merchantName: "Nova Org", merchantCity: "Sao Paulo")
  )
  let organization = try await store.createOrganization(draft)

  #expect(organization.id == OrganizationID(rawValue: "organization-2"))
  #expect(organization.pix == PixConfiguration(key: "chave-pix", merchantName: "Nova Org", merchantCity: "Sao Paulo"))
  #expect(OrganizationURLProtocol.patchRequests == 0)
  let body = try #require(OrganizationURLProtocol.createBody)
  let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect(json["pix_key"] as? String == "chave-pix")
  #expect(json["pix_merchant_name"] as? String == "Nova Org")
  #expect(json["pix_merchant_city"] as? String == "Sao Paulo")
}

@MainActor
@Test func liveCreateOrganizationDoesNotAttemptAFollowUpPixPatch() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: failingPixPatchSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let draft = OrganizationDraft(
    name: "Nova Org",
    pix: PixConfiguration(key: "chave-pix", merchantName: "Nova Org", merchantCity: "Sao Paulo")
  )
  let organization = try await store.createOrganization(draft)

  #expect(organization.id == OrganizationID(rawValue: "organization-3"))
  #expect(organization.pix == PixConfiguration(key: "chave-pix", merchantName: "Nova Org", merchantCity: "Sao Paulo"))
}

private func organizationSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [OrganizationURLProtocol.self]
  return URLSession(configuration: configuration)
}

private final class OrganizationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var createBody: Data?
  nonisolated(unsafe) static var patchRequests = 0
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch (request.httpMethod, path) {
    case ("GET", "/api/v1/auth/session"):
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("GET", "/api/v1/organizations"):
      body = #"{"items":[{"uuid":"organization-1","name":"Horizonte","enforce_mfa":false,"current_role":"admin","capabilities":{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true}}]}"#
    case ("GET", "/api/v1/organizations/organization-1"):
      body = #"{"uuid":"organization-1","name":"Horizonte","enforce_mfa":false,"current_role":"admin","capabilities":{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true},"settings":null,"members":[{"user_id":7,"email":"ana@rentivo.com.br","role":"admin"},{"user_id":11,"email":"bruno@rentivo.com.br","role":"viewer"}]}"#
    case ("POST", "/api/v1/organizations/organization-1/invites"):
      body = #"{"uuid":"invite-1","invited_email":"bruno@rentivo.com.br","role":"viewer","status":"pending"}"#
    case ("POST", "/api/v1/organizations"):
      Self.createBody = Self.requestBody(from: request)
      body = #"{"uuid":"organization-2","name":"Nova Org","enforce_mfa":false,"current_role":"admin","capabilities":{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true},"settings":{"pix_key":"chave-pix","pix_merchant_name":"Nova Org","pix_merchant_city":"Sao Paulo"},"members":[]}"#
    case ("PATCH", "/api/v1/organizations/organization-2"):
      Self.patchRequests += 1
      body = #"{"uuid":"organization-2","name":"Nova Org","enforce_mfa":false,"current_role":"admin","capabilities":{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true},"settings":{"pix_key":"chave-pix","pix_merchant_name":"Nova Org","pix_merchant_city":"Sao Paulo"},"members":[{"user_id":7,"email":"ana@rentivo.com.br","role":"admin"}]}"#
    default:
      body = #"{"detail":"Endpoint inesperado: \#(request.httpMethod ?? "?") \#(path ?? "nil")"}"#
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

  static func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

private func failingPixPatchSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FailingPixPatchURLProtocol.self]
  return URLSession(configuration: configuration)
}

/// Simulates a server that would fail any obsolete follow-up PATCH. The atomic POST returns PIX.
private final class FailingPixPatchURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let statusCode: Int
    let body: String
    switch (request.httpMethod, path) {
    case ("GET", "/api/v1/auth/session"):
      statusCode = 200
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("POST", "/api/v1/organizations"):
      statusCode = 200
      body = #"{"uuid":"organization-3","name":"Nova Org","enforce_mfa":false,"current_role":"admin","capabilities":{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true},"settings":{"pix_key":"chave-pix","pix_merchant_name":"Nova Org","pix_merchant_city":"Sao Paulo"},"members":[]}"#
    case ("PATCH", "/api/v1/organizations/organization-3"):
      statusCode = 500
      body = #"{"detail":"Falha ao salvar as configurações de PIX."}"#
    default:
      statusCode = 500
      body = #"{"detail":"Endpoint inesperado: \#(request.httpMethod ?? "?") \#(path ?? "nil")"}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: statusCode, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
