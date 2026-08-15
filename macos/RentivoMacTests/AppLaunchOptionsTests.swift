import SwiftUI
import Testing

@testable import Rentivo

@Suite("App launch window options")
struct AppLaunchOptionsTests {
  @Test("the normal launch keeps the 1280 by 800 window")
  func defaultWindowSize() {
    #expect(
      AppLaunchOptions.initialWindowSize(arguments: ["Rentivo"])
        == CGSize(width: 1280, height: 800)
    )
  }

  @Test("UI tests can select both adaptive layout widths")
  func supportedUITestWidths() {
    #expect(
      AppLaunchOptions.initialWindowSize(
        arguments: ["Rentivo", "--ui-test-window-width=760"]
      ) == CGSize(width: 760, height: 800)
    )
    #expect(
      AppLaunchOptions.initialWindowSize(
        arguments: ["Rentivo", "--ui-test-window-width=1280"]
      ) == CGSize(width: 1280, height: 800)
    )
  }

  @Test("malformed and unsupported widths fall back safely")
  func invalidUITestWidths() {
    #expect(
      AppLaunchOptions.initialWindowSize(
        arguments: ["Rentivo", "--ui-test-window-width=nope"]
      ) == CGSize(width: 1280, height: 800)
    )
    #expect(
      AppLaunchOptions.initialWindowSize(
        arguments: ["Rentivo", "--ui-test-window-width=900"]
      ) == CGSize(width: 1280, height: 800)
    )
  }
}
