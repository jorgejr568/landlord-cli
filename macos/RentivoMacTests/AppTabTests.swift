import Testing

@testable import Rentivo

@Suite("macOS app sections")
struct AppTabTests {
  @Test("the sidebar order matches the iOS tab bar order")
  func allCasesFollowTheIOSTabOrder() {
    #expect(AppTab.allCases == [.home, .billings, .organizations, .account])
  }

  @Test("every section has PT-BR copy, an SF Symbol, and its own Command-digit shortcut")
  func everySectionIsFullyLabelled() {
    #expect(AppTab.allCases.map(\.title) == ["Início", "Cobranças", "Organizações", "Conta"])
    #expect(AppTab.allCases.map(\.systemImage) == ["house", "doc.text", "building.2", "person.crop.circle"])
    #expect(AppTab.allCases.map(\.keyboardShortcut) == ["1", "2", "3", "4"])
  }
}
