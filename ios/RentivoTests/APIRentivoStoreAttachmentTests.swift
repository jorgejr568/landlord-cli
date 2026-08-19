import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@MainActor
@Test func attachmentResponseRetainsEveryFieldUsedByTheUI() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [AttachmentResponseURLProtocol.self]
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration),
    credentials: MemoryCredentialStore(token: "stored-token")
  )
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let attachments = try await store.listAttachments(
    billingID: BillingID(rawValue: "billing-1"))
  let attachment = try #require(attachments.first)

  #expect(attachment.id == AttachmentID(rawValue: "attachment-1"))
  #expect(attachment.name == "Contrato assinado")
  #expect(attachment.filename == "contrato-servidor.pdf")
  #expect(attachment.mediaType == "application/pdf")
  #expect(attachment.byteCount == 1_500_000)
  #expect(attachment.sortOrder == 7)
  #expect(attachment.createdAt == ISO8601DateFormatter().date(from: "2026-08-19T12:00:00Z"))
  #expect(attachment.displayName == "Contrato assinado")
}

private final class AttachmentResponseURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch path {
    case "/api/v1/auth/session":
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case "/api/v1/billings/billing-1/attachments":
      body = #"{"items":[{"uuid":"attachment-1","name":"Contrato assinado","filename":"contrato-servidor.pdf","content_type":"application/pdf","file_size":1500000,"sort_order":7,"created_at":"2026-08-19T12:00:00Z"}]}"#
    default:
      body = #"{"detail":"Endpoint inesperado"}"#
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
