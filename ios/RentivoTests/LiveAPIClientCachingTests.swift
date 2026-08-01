import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - `LiveAPIClient.makeSession()` caching policy
//
// `URLSessionConfiguration.default` binds to the disk-backed `URLCache.shared`, so authenticated
// responses would be written into the app container purely as a side effect of the transport. The
// app is a thin client over a live API with no offline mode, so it opts out entirely.

@Test func theAppSessionStoresNothingInAURLCache() {
  let configuration = LiveAPIClient.makeSession().configuration

  #expect(configuration.urlCache == nil)
  #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func theAppSessionKeepsTheTimeoutBehaviorItWasCreatedFor() {
  let configuration = LiveAPIClient.makeSession().configuration

  #expect(configuration.timeoutIntervalForRequest == 30)
  #expect(configuration.waitsForConnectivity == false)
}
