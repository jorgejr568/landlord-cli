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
  #expect(organization.members.map(\.isCurrentUser) == [true, false])
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
@Test func liveMFAPolicyReturnsWhetherTheCurrentUserStillNeedsSetup() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: organizationSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let policy = try await store.setOrganizationMFA(
    organizationID: OrganizationID(rawValue: "organization-1"), required: true
  )

  #expect(policy.enforceMFA)
  #expect(policy.mfaSetupRequired)
}

@MainActor
@Test func liveAcceptInvitationSurfacesRequiredMFASetup() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: organizationSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let outcome = try await store.acceptInvitation(id: InvitationID(rawValue: "invite-1"))

  #expect(outcome.organizationID == OrganizationID(rawValue: "organization-1"))
  #expect(outcome.mfaSetupRequired)
}

@MainActor
@Test func livePendingInvitationsPreserveSenderAndMFAPolicy() async throws {
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: organizationSession(), credentials: credentials)
  let store = APIRentivoStore(client: client)

  _ = try #require(try await store.restoreSession())
  let invitation = try #require(try await store.listPendingInvitations().first)

  #expect(invitation.invitedByEmail == "admin@horizonte.com.br")
  #expect(invitation.organizationEnforcesMFA)
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
    guard case .server(let message, let statusCode, _) = error else {
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
@Test func liveCreateOrganizationSendsPixAtomicallyInTheCreateRequest() async throws {
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
}

private func organizationSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [OrganizationURLProtocol.self]
  return URLSession(configuration: configuration)
}

private final class OrganizationURLProtocol: URLProtocol, @unchecked Sendable {
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
      body = #"{"uuid":"organization-1","name":"Horizonte","enforce_mfa":false,"current_role":"admin","capabilities":{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true},"settings":null,"members":[{"user_id":7,"email":"ana@rentivo.com.br","role":"admin","is_current_user":true},{"user_id":11,"email":"bruno@rentivo.com.br","role":"viewer","is_current_user":false}]}"#
    case ("POST", "/api/v1/organizations/organization-1/invites"):
      body = #"{"uuid":"invite-1","invited_email":"bruno@rentivo.com.br","role":"viewer","status":"pending"}"#
    case ("PUT", "/api/v1/organizations/organization-1/mfa-policy"):
      body = #"{"enforce_mfa":true,"mfa_setup_required":true}"#
    case ("POST", "/api/v1/invites/invite-1/accept"):
      body = #"{"status":"accepted","organization_uuid":"organization-1","mfa_setup_required":true}"#
    case ("GET", "/api/v1/invites"):
      body = #"{"items":[{"uuid":"invite-1","organization_uuid":"organization-1","organization_name":"Horizonte","role":"manager","enforce_mfa":true,"created_at":"2026-08-15T00:00:00Z","invited_by_email":"admin@horizonte.com.br"}]}"#
    case ("POST", "/api/v1/organizations"):
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
}
