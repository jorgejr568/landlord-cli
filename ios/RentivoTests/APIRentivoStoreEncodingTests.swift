import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@MainActor
@Test func liveCreateBillEncodesVariableAmountsForMatchingULIDsAndOmitsClientMintedIDs() async throws {
  // Regression test: createBill used to send only `extras`, silently dropping user-edited
  // variable line amounts. The server requires `variable_amounts` to be keyed by the billing's
  // own variable-item ULIDs; a freshly client-minted line item id must not be sent as a key.
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CapturingBillCreateURLProtocol.self]
  CapturingBillCreateURLProtocol.capturedBody = nil
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: URLSession(configuration: configuration), credentials: credentials)
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let variableItemULID = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  let clientMintedID = BillLineItemID(rawValue: UUID().uuidString)
  let draft = BillDraft(
    billingID: BillingID(rawValue: "billing-1"),
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: DateOnly(year: 2026, month: 7, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(id: BillLineItemID(rawValue: variableItemULID), description: "Água", amount: Money(centavos: 4_200), kind: .variable),
      BillLineItem(id: clientMintedID, description: "Taxa extra", amount: Money(centavos: 1_000), kind: .extra),
    ]
  )

  _ = try await store.createBill(draft)

  let body = try #require(CapturingBillCreateURLProtocol.capturedBody)
  let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  let variableAmountsRaw = try #require(json["variable_amounts"] as? [String: Any])
  let variableAmounts = variableAmountsRaw.compactMapValues { $0 as? Int }
  #expect(variableAmounts == [variableItemULID: 4_200])
  let extras = try #require(json["extras"] as? [[String: Any]])
  #expect(extras.count == 1)
  #expect(extras.first?["amount"] as? Int == 1_000)
}

@MainActor
@Test func liveSendCommunicationSendsRecipientUUIDsWithoutTouchingTheContactList() async throws {
  // Regression test: sendCommunication used to full-replace the billing's recipients via
  // PUT /recipients as a side effect of every send. It must now send the chosen recipient
  // uuids directly and never call any other mutating endpoint.
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CommunicationSendURLProtocol.self]
  CommunicationSendURLProtocol.capturedSendBody = nil
  CommunicationSendURLProtocol.unexpectedRequests = []
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: URLSession(configuration: configuration), credentials: credentials)
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let queued = try await store.sendCommunication(
    billingID: BillingID(rawValue: "billing-1"),
    billID: BillID(rawValue: "bill-1"),
    commType: .paymentReceipt,
    recipientIDs: [RecipientID(rawValue: "contact-1"), RecipientID(rawValue: "contact-2")],
    subject: "Recibo de julho",
    message: "Segue o recibo.",
    acknowledgeWarning: true,
    saveScope: .billing
  )

  #expect(queued == 2)
  #expect(CommunicationSendURLProtocol.unexpectedRequests.isEmpty)
  let sendBody = try #require(CommunicationSendURLProtocol.capturedSendBody)
  let json = try #require(JSONSerialization.jsonObject(with: sendBody) as? [String: Any])
  #expect(json["bill_uuid"] as? String == "bill-1")
  #expect(json["comm_type"] as? String == "payment_receipt")
  #expect(json["subject"] as? String == "Recibo de julho")
  #expect(json["body"] as? String == "Segue o recibo.")
  #expect(json["recipient_uuids"] as? [String] == ["contact-1", "contact-2"])
  #expect(json["acknowledge_warning"] as? Bool == true)
  #expect(json["save_scope"] as? String == "billing")
}

@MainActor
@Test func liveAPIKeyUpdateOmitsUnchangedGrants() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [CapturingAPIKeyUpdateURLProtocol.self]
  CapturingAPIKeyUpdateURLProtocol.capturedBody = nil
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: URLSession(configuration: configuration), credentials: credentials)
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  _ = try await store.updateAPIKey(
    id: APIKeyID(rawValue: "key-1"),
    draft: .demo,
    updateGrants: false
  )

  let body = try #require(CapturingAPIKeyUpdateURLProtocol.capturedBody)
  let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect(json["name"] as? String == "Painel financeiro")
  #expect(json["grants"] == nil)
  #expect(json["expires_at"] == nil)
}

// Dedicated to the createBill encoding test only, so its mutable capture state can't race with
// other tests.
private final class CapturingBillCreateURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var capturedBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch path {
    case "/api/v1/auth/session":
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case "/api/v1/billings/billing-1/bills":
      Self.capturedBody = Self.requestBody(from: request)
      body = #"{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"draft","due_date":"2026-07-10","status_updated_at": null,"line_items":[{"description":"Água","amount":4200,"item_type":"variable"},{"description":"Taxa extra","amount":1000,"item_type":"extra"}],"receipts":[],"total_amount":5200,"available_transitions":[{"target":"published","label":"Publicar","style":"primary","requires_confirmation":false},{"target":"cancelled","label":"Cancelar","style":"destructive","requires_confirmation":true}]}"#
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

  static func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}

private final class CapturingAPIKeyUpdateURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var capturedBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let body: String
    switch (request.httpMethod, request.url?.path) {
    case ("GET", "/api/v1/auth/session"):
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("PATCH", "/api/v1/api-keys/key-1"):
      Self.capturedBody = CapturingBillCreateURLProtocol.requestBody(from: request)
      body = #"{"uuid":"key-1","name":"Painel financeiro","hint":"rntv-v1-ab••cd","scopes":["billings:read","profile:read"],"grants":[{"resource_type":"organization","resource_id":null,"available":false}],"expires_at":"2026-12-31T23:59:59+00:00","last_used_at":null,"created_at":"2026-01-01T00:00:00+00:00","revoked_at":null}"#
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

// Dedicated to the sendCommunication encoding test only, so its mutable capture state can't race
// with other tests.
private final class CommunicationSendURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var capturedSendBody: Data?
  nonisolated(unsafe) static var unexpectedRequests: [String] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch (request.httpMethod, path) {
    case ("GET", "/api/v1/auth/session"):
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("POST", "/api/v1/billings/billing-1/communications/send"):
      Self.capturedSendBody = Self.requestBody(from: request)
      body = #"{"queued_count": 2}"#
    default:
      Self.unexpectedRequests.append("\(request.httpMethod ?? "?") \(path ?? "nil")")
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

  static func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
