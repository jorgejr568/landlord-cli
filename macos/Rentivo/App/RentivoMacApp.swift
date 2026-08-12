import RentivoCore
import SwiftUI

@main
struct RentivoMacApp: App {
  @State private var app: AppModel

  init() {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      let usesMockData = arguments.contains("--ui-testing") || arguments.contains("--screenshot-authenticated")
      let model = usesMockData
        ? AppModel(store: MockRentivoStore(fixtures: .canonical))
        : AppModel(dependencies: .live())
    #else
      let model = AppModel(dependencies: .live())
    #endif
    #if DEBUG
      if arguments.contains("--screenshot-authenticated") {
        model.signIn()
        if let tabIndex = arguments.firstIndex(of: "--screenshot-tab"),
          arguments.indices.contains(tabIndex + 1)
        {
          switch arguments[tabIndex + 1] {
          case "billings": model.selectedTab = .billings
          case "organizations": model.selectedTab = .organizations
          case "account": model.selectedTab = .account
          default: model.selectedTab = .home
          }
        }
        model.notice = nil
      }
    #endif
    _app = State(initialValue: model)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(app)
        .tint(RentivoColors.emerald)
        // The design system is light-appearance only on every platform (see `RentivoColors`),
        // so the window opts out of the system appearance rather than rendering fixed light
        // tokens against dark chrome.
        .preferredColorScheme(.light)
    }
    .defaultSize(width: 1200, height: 760)
    .commands {
      // Nothing in the app is "new" from the File menu — every create action lives inside a
      // section — so the placeholder item is removed rather than left dead.
      CommandGroup(replacing: .newItem) {}
      CommandMenu("Ir para") {
        ForEach(AppTab.allCases, id: \.self) { tab in
          Button(tab.title) { app.selectedTab = tab }
            .keyboardShortcut(KeyEquivalent(tab.keyboardShortcut), modifiers: .command)
        }
        .disabled(!app.isAuthenticated)
      }
      CommandMenu("Conta") {
        Button("Sair da conta") {
          Task { await app.signOut() }
        }
        .keyboardShortcut("q", modifiers: [.command, .shift])
        .disabled(!app.isAuthenticated || app.isSigningOut)
      }
    }
  }
}
