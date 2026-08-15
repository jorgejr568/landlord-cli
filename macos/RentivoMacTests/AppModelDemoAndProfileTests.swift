import RentivoCore
import Testing

@testable import Rentivo

@Suite("macOS AppModel demo settings")
@MainActor
struct AppModelDemoSettingsTests {
  @Test("invalidating data bumps the shared revision")
  func invalidationBumpsRevision() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let initialRevision = app.dataRevision

    app.invalidateData()

    #expect(app.dataRevision == initialRevision + 1)
  }

  @Test("only the content-shaping toggles bump dataRevision")
  func delayToggleSkipsDataRevisionButEmptyAndViewerToggleBumpIt() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let initialRevision = app.dataRevision

    // Only the delay toggle is a "how content loads" setting, not a "what content loads" setting;
    // bumping `dataRevision` for it would force every visible screen to redundantly reload.
    app.setDelayEnabled(true)
    #expect(app.demoSettings.delayEnabled == true)
    #expect(app.dataRevision == initialRevision)

    app.setEmptyMode(true)
    #expect(app.demoSettings.emptyMode == true)
    #expect(app.dataRevision == initialRevision + 1)

    app.setViewerMode(true)
    #expect(app.demoSettings.viewerMode == true)
    #expect(app.dataRevision == initialRevision + 2)
  }

  @Test("resetting the demo restores the default settings and bumps dataRevision")
  func resetDemoRestoresDefaultSettingsAndBumpsDataRevision() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.setDelayEnabled(true)
    app.setEmptyMode(true)
    app.setViewerMode(true)
    let revisionBeforeReset = app.dataRevision

    app.resetDemo()

    #expect(app.demoSettings == .standard)
    #expect(app.dataRevision == revisionBeforeReset + 1)
  }

  @Test("arming the next failure leaves the visible demo state untouched")
  func failNextOperationDoesNotDisturbSettingsOrRevision() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let revision = app.dataRevision

    app.failNextOperation()

    #expect(app.demoSettings == .standard)
    #expect(app.dataRevision == revision)
  }
}

@Suite("macOS AppModel profile")
@MainActor
struct AppModelProfileTests {
  @Test("loading the profile refreshes the authenticated session")
  func loadProfileRefreshesTheAuthenticatedSession() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()

    let profile = try await app.loadProfile()

    guard case .authenticated(let sessionProfile) = app.session else {
      Issue.record("Expected the session to stay authenticated after loadProfile()")
      return
    }
    #expect(sessionProfile == profile)
  }

  @Test("saving PIX writes through to the store and to the session profile")
  func updateProfilePIXWritesThroughToTheSession() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.signIn()
    let pix = PixConfiguration(
      key: "jorge@example.com", merchantName: "JORGE JUNIOR", merchantCity: "SALVADOR"
    )

    let updated = try await app.updateProfilePIX(pix)

    #expect(updated.pix == pix)
    guard case .authenticated(let sessionProfile) = app.session else {
      Issue.record("Expected the session to stay authenticated after updateProfilePIX()")
      return
    }
    #expect(sessionProfile.pix == pix)
    #expect(app.currentUser.pix == pix)
  }

  @Test("saving PIX while signed out does not fabricate an authenticated session")
  func updateProfilePIXLeavesAnAnonymousSessionAlone() async throws {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let pix = PixConfiguration(
      key: "jorge@example.com", merchantName: "JORGE JUNIOR", merchantCity: "SALVADOR"
    )

    _ = try await app.updateProfilePIX(pix)

    guard case .anonymous = app.session else {
      Issue.record("Expected updateProfilePIX() to leave an anonymous session anonymous")
      return
    }
    #expect(app.isAuthenticated == false)
  }
}
