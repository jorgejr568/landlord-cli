import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - `LiveAPIClient.resolveBaseURL(environmentValue:defaultsValue:)`
//
// The DEBUG-only override that lets a simulator build talk to a local backend. It answers where API
// requests go; `productionURL` still answers where the support, privacy, terms, and forgot-password
// links go, so a mistake here must degrade to production rather than to an unusable address.

#if DEBUG

  @Test func theEnvironmentOverrideWinsOverTheStoredOne() {
    let resolved = LiveAPIClient.resolveBaseURL(
      environmentValue: "http://localhost:18080", defaultsValue: "http://localhost:9999")

    #expect(resolved == URL(string: "http://localhost:18080"))
  }

  @Test func theStoredOverrideIsUsedWhenTheEnvironmentCarriesNone() {
    let resolved = LiveAPIClient.resolveBaseURL(
      environmentValue: nil, defaultsValue: "http://192.168.0.10:18080")

    #expect(resolved == URL(string: "http://192.168.0.10:18080"))
  }

  // A candidate that cannot become an absolute request base is skipped rather than adopted: an
  // unusable environment value still lets the stored one through.
  @Test func anUnusableEnvironmentValueFallsThroughToTheStoredOne() {
    for environmentValue in ["", "   ", "localhost:18080", "http://", "/api/v1", "not a url"] {
      let resolved = LiveAPIClient.resolveBaseURL(
        environmentValue: environmentValue, defaultsValue: "http://localhost:18080")

      #expect(resolved == URL(string: "http://localhost:18080"), "rejected: \(environmentValue)")
    }
  }

  @Test func twoUnusableOverridesLeaveTheClientOnProduction() {
    let resolved = LiveAPIClient.resolveBaseURL(
      environmentValue: "not a url", defaultsValue: "")

    #expect(resolved == LiveAPIClient.productionURL)
  }

  @Test func noOverrideAtAllLeavesTheClientOnProduction() {
    let resolved = LiveAPIClient.resolveBaseURL(environmentValue: nil, defaultsValue: nil)

    #expect(resolved == LiveAPIClient.productionURL)
  }

  // Surrounding whitespace is what a copied-and-pasted URL arrives with; it must not be the reason
  // a build silently keeps talking to production.
  @Test func aPaddedOverrideIsStillAccepted() {
    let resolved = LiveAPIClient.resolveBaseURL(
      environmentValue: "  https://staging.example.com\n", defaultsValue: nil)

    #expect(resolved == URL(string: "https://staging.example.com"))
  }

#endif
