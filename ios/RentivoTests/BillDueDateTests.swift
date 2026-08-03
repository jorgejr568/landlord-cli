import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

/// A fixed UTC calendar keeps the `DateOnly` <-> `Date` round trip independent of the
/// machine's time zone, which would otherwise shift the day across the midnight boundary.
private let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

@Test func defaultDueDateIsDayTenOfTheMonthAfterTheReferenceMonth() {
  // A bill covering July is normally paid in early August: the reference month and the due
  // date are independent, and the default has to reflect that rather than reusing the month.
  #expect(
    ReferenceMonth(year: 2026, month: 7).defaultDueDate == DateOnly(year: 2026, month: 8, day: 10)
  )
}

@Test func defaultDueDateRollsOverIntoTheNextYearForDecember() {
  #expect(
    ReferenceMonth(year: 2026, month: 12).defaultDueDate == DateOnly(year: 2027, month: 1, day: 10)
  )
}

@Test func dateOnlyRoundTripsThroughDate() {
  let original = DateOnly(year: 2026, month: 8, day: 10)
  #expect(DateOnly(from: original.resolvedDate(in: utcCalendar), calendar: utcCalendar) == original)
}

@Test func dateOnlyResolvesImpossibleComponentsWithoutTrapping() throws {
  // 31/02 can arrive from the wire via the failable ISO initializer, which only range-checks
  // the day as 1...31 without consulting the month's length. Resolving it must produce a date
  // rather than crash the picker that seeds from it; `Calendar` normalizes it into March.
  let impossible = try #require(DateOnly(iso8601String: "2026-02-31"))
  let resolved = impossible.resolvedDate(in: utcCalendar)
  #expect(utcCalendar.component(.month, from: resolved) == 3)
}

@MainActor
@Test func liveBillWithNullDueDateDecodesToNilInsteadOfTheEpoch() async throws {
  // A `null` due_date used to become 1970-01-01 and render as "Vence 01/01/1970".
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [BillDueDateURLProtocol.self]
  BillDueDateURLProtocol.capturedCreateBody = nil
  BillDueDateURLProtocol.capturedUpdateBody = nil
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration), credentials: credentials
  )
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let bills = try await store.listBills(billingID: BillingID(rawValue: "billing-1"))

  #expect(bills.count == 1)
  #expect(bills[0].dueDate == nil)
}

@MainActor
@Test func liveCreateBillSendsADueDateOutsideTheReferenceMonth() async throws {
  // The whole point of the change: a July bill can be due in August.
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [BillDueDateURLProtocol.self]
  BillDueDateURLProtocol.capturedCreateBody = nil
  BillDueDateURLProtocol.capturedUpdateBody = nil
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration), credentials: credentials
  )
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let draft = BillDraft(
    billingID: BillingID(rawValue: "billing-1"),
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: DateOnly(year: 2026, month: 8, day: 10),
    notes: "",
    lineItems: [
      BillLineItem(
        id: BillLineItemID(rawValue: UUID().uuidString), description: "Taxa extra",
        amount: Money(centavos: 1_000), kind: .extra
      )
    ]
  )
  _ = try await store.createBill(draft)

  let body = try #require(BillDueDateURLProtocol.capturedCreateBody)
  let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect(json["reference_month"] as? String == "2026-07")
  #expect(json["due_date"] as? String == "2026-08-10")
}

@MainActor
@Test func liveUpdateBillWritesAnExplicitNullToClearTheDueDate() async throws {
  // The server keeps the existing value when `due_date` is absent from the PATCH body
  // (backend/rentivo/api/routes/bills.py `if "due_date" not in fields`), so a nil due date has
  // to serialize as an explicit JSON null rather than being omitted.
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [BillDueDateURLProtocol.self]
  BillDueDateURLProtocol.capturedCreateBody = nil
  BillDueDateURLProtocol.capturedUpdateBody = nil
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration), credentials: credentials
  )
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let draft = BillDraft(
    billingID: BillingID(rawValue: "billing-1"),
    referenceMonth: ReferenceMonth(year: 2026, month: 7),
    dueDate: nil,
    notes: "",
    lineItems: [
      BillLineItem(
        id: BillLineItemID(rawValue: UUID().uuidString), description: "Aluguel",
        amount: Money(centavos: 10_000), kind: .fixed
      )
    ]
  )
  _ = try await store.updateBill(
    billingID: BillingID(rawValue: "billing-1"),
    billID: BillID(rawValue: "bill-1"),
    draft: draft
  )

  let body = try #require(BillDueDateURLProtocol.capturedUpdateBody)
  let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
  #expect(json.keys.contains("due_date"))
  #expect(json["due_date"] is NSNull)
}

/// Dedicated to the due-date tests so its mutable capture state can't race with other suites.
private final class BillDueDateURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var capturedCreateBody: Data?
  nonisolated(unsafe) static var capturedUpdateBody: Data?

  /// A bill the server reports with no due date at all.
  private static let billWithoutDueDate = #"{"uuid":"bill-1","reference_month":"2026-07","notes":"","status":"draft","due_date":null,"status_updated_at":null,"line_items":[],"receipts":[],"total_amount":0,"available_transitions":[]}"#

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path
    let body: String
    switch (request.httpMethod, path) {
    case ("GET", "/api/v1/auth/session"):
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    case ("GET", "/api/v1/billings/billing-1/bills"):
      body = #"{"items":[\#(Self.billWithoutDueDate)]}"#
    case ("POST", "/api/v1/billings/billing-1/bills"):
      Self.capturedCreateBody = Self.requestBody(from: request)
      body = Self.billWithoutDueDate
    case ("PATCH", "/api/v1/billings/billing-1/bills/bill-1"):
      Self.capturedUpdateBody = Self.requestBody(from: request)
      body = Self.billWithoutDueDate
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
