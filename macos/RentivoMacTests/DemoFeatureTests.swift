import RentivoCore
import Testing

@testable import Rentivo

@Suite("macOS demo scenarios")
@MainActor
struct DemoScenariosTests {
  @Test("a toggle row reads Ativo or Inativo")
  func stateLabelIsThePTBRToggleCopy() {
    #expect(demoScenarioStateLabel(enabled: true) == "Ativo")
    #expect(demoScenarioStateLabel(enabled: false) == "Inativo")
  }

  @Test("arming the next failure announces itself without changing the demo state")
  func armNextDemoFailureShowsAnInformationalNotice() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    let revision = app.dataRevision

    app.armNextDemoFailure()

    #expect(app.notice?.message == "A próxima operação falhará de forma controlada.")
    #expect(app.notice?.kind == .information)
    // The failure is armed, not fired: nothing has changed about what the screens would load.
    #expect(app.demoSettings == .standard)
    #expect(app.dataRevision == revision)
  }

  @Test("restoring the demonstration resets every setting, reloads content, and confirms")
  func restoreDemoDataResetsSettingsAndShowsASuccessNotice() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))
    app.setDelayEnabled(true)
    app.setEmptyMode(true)
    app.setViewerMode(true)
    let revisionBeforeReset = app.dataRevision

    app.restoreDemoData()

    #expect(app.demoSettings == .standard)
    // Every visible screen has to reload: the fixtures behind them were just replaced.
    #expect(app.dataRevision == revisionBeforeReset + 1)
    #expect(app.notice?.message == "Demonstração restaurada.")
    #expect(app.notice?.kind == .success)
  }

  @Test("each toggle row drives its own setting and leaves the others alone")
  func toggleRowsDriveIndependentSettings() {
    let app = AppModel(store: MockRentivoStore(fixtures: .canonical))

    app.setDelayEnabled(!app.demoSettings.delayEnabled)

    #expect(app.demoSettings.delayEnabled == true)
    #expect(app.demoSettings.emptyMode == false)
    #expect(app.demoSettings.viewerMode == false)

    app.setViewerMode(!app.demoSettings.viewerMode)

    #expect(app.demoSettings.delayEnabled == true)
    #expect(app.demoSettings.viewerMode == true)
    #expect(app.demoSettings.emptyMode == false)
  }
}
