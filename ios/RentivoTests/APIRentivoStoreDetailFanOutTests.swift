import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - Concurrent detail fan-out (`listBillings` / `listOrganizations`)
//
// Both list endpoints return summaries that omit what the app shows, so each row costs a detail
// request. Those used to run one `await` at a time, making the wait grow linearly with the list.
// They now run in a bounded task group, which is only correct if two things hold: the results come
// back in the *list's* order no matter which request finishes first, and the requests really do
// overlap. Each stub below answers detail requests in deliberately reversed time order — the first
// row is the slowest — so a sequential implementation and a concurrent one are distinguishable, and
// counts how many were in flight at once. As elsewhere in this suite, each test owns its own
// `URLProtocol` subclass because Swift Testing runs `@Test` functions concurrently.

@MainActor
@Test func liveBillingListFetchesDetailsConcurrentlyAndReassemblesThemInListOrder() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ConcurrentBillingDetailURLProtocol.self]
  ConcurrentBillingDetailURLProtocol.counters.reset()
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: URLSession(configuration: configuration), credentials: credentials)
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let billings = try await store.listBillings()

  // The stub answers `billing-6` first and `billing-1` last, so this order can only come from the
  // group reassembling by index rather than by completion.
  #expect(billings.map(\.id.rawValue) == (1...6).map { "billing-\($0)" })
  #expect(billings.map(\.name) == (1...6).map { "Imóvel \($0)" })
  let peak = ConcurrentBillingDetailURLProtocol.counters.peak
  #expect(peak > 1, "detail requests still ran one at a time (peak in flight: \(peak))")
  // Six rows, five slots: the group must not open a request per row.
  #expect(peak <= 5, "more detail requests were in flight than the group's bound (\(peak))")
}

@MainActor
@Test func liveOrganizationListReassemblesOutOfOrderDetailsInListOrder() async throws {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ConcurrentOrganizationDetailURLProtocol.self]
  ConcurrentOrganizationDetailURLProtocol.counters.reset()
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: URLSession(configuration: configuration), credentials: credentials)
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  let organizations = try await store.listOrganizations()

  #expect(organizations.map(\.id.rawValue) == (1...4).map { "organization-\($0)" })
  #expect(organizations.map(\.name) == (1...4).map { "Organização \($0)" })
  // Each stubbed organization carries a distinct member list, so a mis-assembled result would pair
  // the wrong members with the wrong organization even if the ids happened to line up.
  #expect(organizations.map { $0.members.map(\.userID) } == (1...4).map { [$0] })
  let peak = ConcurrentOrganizationDetailURLProtocol.counters.peak
  #expect(peak > 1, "detail requests still ran one at a time (peak in flight: \(peak))")
}

@MainActor
@Test func liveBillingListPropagatesADetailFailureInsteadOfReturningAShortList() async throws {
  // The sequential loop this replaced threw on the first failing detail request; the group must
  // keep that contract rather than dropping the row and handing back a quietly incomplete list.
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [FailingBillingDetailURLProtocol.self]
  let credentials = MemoryCredentialStore(token: "stored-token")
  let client = LiveAPIClient(session: URLSession(configuration: configuration), credentials: credentials)
  let store = APIRentivoStore(client: client)
  _ = try #require(try await store.restoreSession())

  do {
    _ = try await store.listBillings()
    Issue.record("Expected the failing detail request to throw")
  } catch let error as LiveAPIError {
    guard case .server(_, let statusCode, _) = error else {
      Issue.record("Expected .server, got \(error)")
      return
    }
    #expect(statusCode == 403)
  }
}

/// Tracks how many stubbed requests are in flight at once, so a test can tell a concurrent fan-out
/// from a sequential one. `URLProtocol` instances load on `URLSession`'s own queues, hence the lock.
private final class InFlightCounters: @unchecked Sendable {
  private let lock = NSLock()
  private var current = 0
  private var highWaterMark = 0

  var peak: Int { lock.withLock { highWaterMark } }

  func reset() { lock.withLock { current = 0; highWaterMark = 0 } }

  func enter() {
    lock.withLock {
      current += 1
      highWaterMark = max(highWaterMark, current)
    }
  }

  func leave() { lock.withLock { current -= 1 } }
}

/// Serves a six-billing list whose detail responses are answered in reverse order: `billing-6`
/// after 10 ms, `billing-1` after 60 ms.
private final class ConcurrentBillingDetailURLProtocol: URLProtocol, @unchecked Sendable {
  static let counters = InFlightCounters()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    if path == "/api/v1/auth/session" {
      finish(with: #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#)
      return
    }
    if path == "/api/v1/billings" {
      finish(with: BillingFixtures.list(count: 6))
      return
    }
    guard let index = BillingFixtures.index(fromDetailPath: path) else {
      finish(with: #"{"detail":"Endpoint inesperado: \#(path)"}"#)
      return
    }
    Self.counters.enter()
    let delay = Double(7 - index) * 0.01
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
      Self.counters.leave()
      self?.finish(with: BillingFixtures.detail(index: index))
    }
  }

  private func finish(with body: String) {
    guard let url = request.url else { return }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Same shape as above, but the third billing's detail request 403s.
private final class FailingBillingDetailURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    switch path {
    case "/api/v1/auth/session":
      finish(with: #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#, statusCode: 200)
    case "/api/v1/billings":
      finish(with: BillingFixtures.list(count: 4), statusCode: 200)
    case "/api/v1/billings/billing-3":
      finish(with: #"{"detail":"Você não tem acesso a esta cobrança."}"#, statusCode: 403)
    default:
      guard let index = BillingFixtures.index(fromDetailPath: path) else {
        finish(with: #"{"detail":"Endpoint inesperado: \#(path)"}"#, statusCode: 200)
        return
      }
      finish(with: BillingFixtures.detail(index: index), statusCode: 200)
    }
  }

  private func finish(with body: String, statusCode: Int) {
    guard let url = request.url else { return }
    let response = HTTPURLResponse(
      url: url, statusCode: statusCode, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

/// Serves a four-organization list whose detail responses are likewise answered in reverse order.
private final class ConcurrentOrganizationDetailURLProtocol: URLProtocol, @unchecked Sendable {
  static let counters = InFlightCounters()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    if path == "/api/v1/auth/session" {
      finish(with: #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#)
      return
    }
    if path == "/api/v1/organizations" {
      finish(with: OrganizationFixtures.list(count: 4))
      return
    }
    guard let index = OrganizationFixtures.index(fromDetailPath: path) else {
      finish(with: #"{"detail":"Endpoint inesperado: \#(path)"}"#)
      return
    }
    Self.counters.enter()
    let delay = Double(5 - index) * 0.01
    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
      Self.counters.leave()
      self?.finish(with: OrganizationFixtures.detail(index: index))
    }
  }

  private func finish(with body: String) {
    guard let url = request.url else { return }
    let response = HTTPURLResponse(
      url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private enum BillingFixtures {
  static let capabilities = #"{"can_edit":true,"can_read_bills":true,"can_create_bills":true,"can_manage_bills":true,"can_read_expenses":true,"can_write_expenses":true,"can_create_exports":true,"can_read_attachments":true,"can_write_attachments":true,"can_read_theme":true,"can_manage_theme":true,"can_upload_bill_receipts":true,"can_delete":true,"can_transfer":true}"#

  static func index(fromDetailPath path: String) -> Int? {
    guard path.hasPrefix("/api/v1/billings/") else { return nil }
    return Int(path.dropFirst("/api/v1/billings/billing-".count))
  }

  static func list(count: Int) -> String {
    let items = (1...count).map { index in
      #"{"uuid":"billing-\#(index)","name":"Imóvel \#(index)","description":"Aluguel","owner":{"type":"user","name":"Ana"},"capabilities":\#(capabilities)}"#
    }
    return #"{"items":[\#(items.joined(separator: ","))],"user_pix_incomplete":false,"stats":{"year":2026,"expected":0,"received":0,"pending":0,"overdue":0,"paid_count":0,"pending_count":0,"overdue_count":0,"active_count":0,"billed_count":0,"total_expenses":0,"net_income":0}}"#
  }

  static func detail(index: Int) -> String {
    #"{"uuid":"billing-\#(index)","name":"Imóvel \#(index)","description":"Aluguel","owner":{"type":"user","name":"Ana"},"items":[],"pix_key":"","pix_merchant_name":"","pix_merchant_city":"","recipients":[],"reply_to":[],"capabilities":\#(capabilities)}"#
  }
}

private enum OrganizationFixtures {
  static let capabilities = #"{"can_manage":true,"can_invite":true,"can_create_billing":true,"can_view_billing_stats":true}"#

  static func index(fromDetailPath path: String) -> Int? {
    guard path.hasPrefix("/api/v1/organizations/") else { return nil }
    return Int(path.dropFirst("/api/v1/organizations/organization-".count))
  }

  static func list(count: Int) -> String {
    let items = (1...count).map { index in
      #"{"uuid":"organization-\#(index)","name":"Organização \#(index)","enforce_mfa":false,"current_role":"admin","capabilities":\#(capabilities)}"#
    }
    return #"{"items":[\#(items.joined(separator: ","))]}"#
  }

  static func detail(index: Int) -> String {
    #"{"uuid":"organization-\#(index)","name":"Organização \#(index)","enforce_mfa":false,"current_role":"admin","capabilities":\#(capabilities),"settings":null,"members":[{"user_id":\#(index),"email":"membro\#(index)@rentivo.com.br","role":"admin"}]}"#
  }
}
