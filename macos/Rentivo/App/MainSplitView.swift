import SwiftUI

extension AppTab {
  /// Sidebar label. Kept here rather than on the enum so `AppModel` stays free of presentation
  /// copy, matching how the iOS `TabView` spells its labels out at the call site.
  var title: String {
    switch self {
    case .home: "Início"
    case .billings: "Cobranças"
    case .organizations: "Organizações"
    case .account: "Conta"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .billings: "doc.text"
    case .organizations: "building.2"
    case .account: "person.crop.circle"
    }
  }

  /// Command-key digit that jumps to this section, mirroring the sidebar order.
  var keyboardShortcut: Character {
    switch self {
    case .home: "1"
    case .billings: "2"
    case .organizations: "3"
    case .account: "4"
    }
  }
}

/// The signed-in shell. Where iOS uses a bottom `TabView`, macOS uses a source-list sidebar with
/// a detail column, which is the platform-native way to expose four peer sections in a resizable
/// window.
struct MainSplitView: View {
  @Environment(AppModel.self) private var app

  // One navigation path per section, owned here rather than inside each section's stack. The
  // detail column shows a single `NavigationStack` at a time, so a section's stack is torn down
  // when the user switches away; keeping the paths out here is what makes a section come back to
  // the screen the user left it on instead of resetting to its root.
  @State private var homePath = NavigationPath()
  @State private var billingsPath = NavigationPath()
  @State private var organizationsPath = NavigationPath()
  @State private var accountPath = NavigationPath()

  /// The `List` sidebar needs an optional selection binding; the app model always has a section
  /// selected, so a nil write (clicking the empty area below the rows) is ignored rather than
  /// leaving the detail column blank.
  private var selection: Binding<AppTab?> {
    Binding(
      get: { app.selectedTab },
      set: { newValue in
        guard let newValue else { return }
        app.selectedTab = newValue
      }
    )
  }

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      detail
    }
  }

  private var sidebar: some View {
    List(selection: selection) {
      ForEach(AppTab.allCases, id: \.self) { tab in
        Label(tab.title, systemImage: tab.systemImage)
          .tag(tab)
      }
    }
    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
    .safeAreaInset(edge: .bottom) { sidebarFooter }
  }

  private var sidebarFooter: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
      Divider()
      VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
        Text(app.currentUser.email)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(RentivoColors.ink)
          .lineLimit(1)
          .truncationMode(.middle)
        if !app.usesLiveAPI {
          Text("Conta de demonstração")
            .font(RentivoTypography.metadata)
            .foregroundStyle(RentivoColors.amber)
            .padding(.horizontal, RentivoSpacing.small)
            .padding(.vertical, 3)
            .background(RentivoColors.amber.opacity(0.14))
            .clipShape(Capsule())
            .overlay { Capsule().stroke(RentivoColors.amber, lineWidth: 1) }
        }
      }
      .padding(.horizontal, RentivoSpacing.medium)
      .padding(.bottom, RentivoSpacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var detail: some View {
    Group {
      switch app.selectedTab {
      case .home:
        NavigationStack(path: $homePath) { HomeView() }
      case .billings:
        NavigationStack(path: $billingsPath) { BillingListView() }
      case .organizations:
        NavigationStack(path: $organizationsPath) { OrganizationListView() }
      case .account:
        NavigationStack(path: $accountPath) { AccountView() }
      }
    }
    .transition(.opacity.combined(with: .offset(x: 12)))
    .animation(.easeOut(duration: 0.18), value: app.selectedTab)
  }
}
