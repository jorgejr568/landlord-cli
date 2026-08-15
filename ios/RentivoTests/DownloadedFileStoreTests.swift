import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - `DownloadedFileStore`
//
// Every test that writes a downloaded file injects its own directory. Swift Testing runs `@Test`
// functions concurrently and `purge()` deletes a whole directory, so a shared one would let a
// purge in one test delete a file another test is still asserting on.

func makeIsolatedDownloadsStore() -> DownloadedFileStore {
  DownloadedFileStore(
    directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("RentivoDownloadsTests-\(UUID().uuidString)", isDirectory: true)
  )
}

@Test func downloadWritesInsideTheStoreDirectoryWithCompleteUnlessOpenProtection() async throws {
  let store = makeIsolatedDownloadsStore()
  defer { store.purge() }
  let credentials = MemoryCredentialStore(token: "stored-token")
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [ProtectedDownloadURLProtocol.self]
  let client = LiveAPIClient(
    session: URLSession(configuration: configuration), credentials: credentials, downloads: store
  )
  _ = try #require(try await client.restoreSession())

  let file = try await client.download(
    path: "/api/v1/billings/b/bills/1/invoice", filename: "fatura-julho.pdf"
  )

  #expect(
    file.fileURL.deletingLastPathComponent().standardizedFileURL.path
      == store.directory.standardizedFileURL.path
  )
  #expect(try Data(contentsOf: file.fileURL) == Data("%PDF-1.4".utf8))
  // Whether Darwin honors data-protection classes depends on the environment, not just the OS:
  // real devices enforce them, the iOS Simulator accepts the option but reports the container
  // default, and macOS hosts vary (developer Macs honor them on APFS; GitHub's virtualized
  // runners do not). Probe with a direct write using the same options in the same directory: when
  // the environment honors them, hold the store's file to the full end-to-end contract; when it
  // does not, the options the store passes are the only part that is the store's to guarantee.
  #if os(iOS)
    let probe = store.directory.appendingPathComponent("protection-probe")
    try Data("probe".utf8).write(to: probe, options: DownloadedFileStore.writingOptions)
    let probeProtection =
      try FileManager.default.attributesOfItem(atPath: probe.path)[.protectionKey]
      as? FileProtectionType
    if probeProtection == .completeUnlessOpen {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.fileURL.path)
      #expect(attributes[.protectionKey] as? FileProtectionType == .completeUnlessOpen)
    } else {
      #expect(DownloadedFileStore.writingOptions.contains(.completeFileProtectionUnlessOpen))
    }
  #else
    #expect(DownloadedFileStore.writingOptions == [.atomic])
  #endif
}

private final class ProtectedDownloadURLProtocol: URLProtocol, @unchecked Sendable {
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

@Test func removeDeletesASingleDownloadedFileAndToleratesAMissingOne() throws {
  let store = makeIsolatedDownloadsStore()
  defer { store.purge() }
  let destination = try store.makeDestination(pathExtension: "pdf")
  try Data("%PDF-1.4".utf8).write(to: destination, options: DownloadedFileStore.writingOptions)
  let file = DownloadedFile(
    fileURL: destination, filename: "fatura.pdf", mediaType: "application/pdf"
  )

  DownloadedFileStore.remove(file)

  #expect(!FileManager.default.fileExists(atPath: destination.path))
  // iOS reclaims `tmp/` on its own schedule, so removing an already-gone file is expected and
  // must stay silent rather than throw.
  DownloadedFileStore.remove(file)
  #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@Test func purgeRemovesTheWholeDownloadsDirectory() throws {
  let store = makeIsolatedDownloadsStore()
  let first = try store.makeDestination(pathExtension: "pdf")
  try Data("%PDF-1.4".utf8).write(to: first, options: DownloadedFileStore.writingOptions)
  let second = try store.makeDestination(pathExtension: "jpg")
  try Data([0xFF, 0xD8, 0xFF]).write(to: second, options: DownloadedFileStore.writingOptions)

  store.purge()

  #expect(!FileManager.default.fileExists(atPath: first.path))
  #expect(!FileManager.default.fileExists(atPath: second.path))
  #expect(!FileManager.default.fileExists(atPath: store.directory.path))
  // Purging a directory that no longer exists is a no-op, not a failure.
  store.purge()
}
