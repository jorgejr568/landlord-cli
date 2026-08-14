import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - Purging what a session left on disk
//
// Both tests inject their own downloads directory (see `makeIsolatedDownloadsStore()` in
// `DownloadedFileStoreTests.swift`) because these are the two tests that actually call `purge()`
// on a real directory, and Swift Testing runs `@Test` functions concurrently.

@Test func logoutRemovesFilesDownloadedDuringTheSession() async throws {
  let store = makeIsolatedDownloadsStore()
  defer { store.purge() }
  let credentials = MemoryCredentialStore(token: "stored-token")
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [PurgeAfterLogoutURLProtocol.self]
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration), credentials: credentials, downloads: store
  )
  _ = try #require(try await client.restoreSession())
  let file = try await client.download(
    path: "/api/v1/billings/b/bills/1/invoice", filename: "fatura.pdf"
  )
  #expect(FileManager.default.fileExists(atPath: file.fileURL.path))

  await client.logout()

  #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
  #expect(!FileManager.default.fileExists(atPath: store.directory.path))
}

private final class PurgeAfterLogoutURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let isSessionRestore = request.url?.path == "/api/v1/auth/session"
    let body =
      isSessionRestore
      ? #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
      : "%PDF-1.4"
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": isSessionRestore ? "application/json" : "application/pdf"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Test func anExpiredSessionRemovesFilesDownloadedDuringIt() async throws {
  let store = makeIsolatedDownloadsStore()
  defer { store.purge() }
  let credentials = MemoryCredentialStore(token: "stored-token")
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ExpiringAfterDownloadURLProtocol.self]
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration), credentials: credentials, downloads: store
  )
  _ = try #require(try await client.restoreSession())
  let file = try await client.download(
    path: "/api/v1/billings/b/bills/1/invoice", filename: "fatura.pdf"
  )
  #expect(FileManager.default.fileExists(atPath: file.fileURL.path))

  do {
    _ = try await client.request(path: "/api/v1/billings")
    Issue.record("Expected the stubbed 401 response to throw")
  } catch let error as LiveAPIError {
    guard case .sessionExpired = error else {
      Issue.record("Expected .sessionExpired, got \(error)")
      return
    }
  }

  // `invalidateSession()` detaches the purge so `.sessionExpired` reaches the UI without waiting on
  // a directory walk, which means the files are gone *shortly after* the throw rather than before
  // it. The session is already unusable at the point above — the token is dropped synchronously —
  // so only the disk cleanup is deferred, and this is the hook that lets the test observe it
  // instead of polling.
  await client.awaitPendingPurge()

  #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
}

/// Authenticates, serves one PDF, then 401s everything else — which is what drives
/// `invalidateSession()`.
private final class ExpiringAfterDownloadURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    let statusCode: Int
    let contentType: String
    let body: String
    if path == "/api/v1/auth/session" {
      statusCode = 200
      contentType = "application/json"
      body = #"{"status":"authenticated","bootstrap":{"user":{"id":7,"email":"ana@rentivo.com.br"}}}"#
    } else if path.hasSuffix("/invoice") {
      statusCode = 200
      contentType = "application/pdf"
      body = "%PDF-1.4"
    } else {
      statusCode = 401
      contentType = "application/json"
      body = #"{"detail":"Sessão expirada."}"#
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: statusCode, httpVersion: nil,
      headerFields: ["Content-Type": contentType]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
