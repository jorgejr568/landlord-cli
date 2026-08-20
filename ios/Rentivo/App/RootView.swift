import SwiftUI
import UIKit

struct RootView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      switch app.session {
      case .restoring:
        SessionRestorationView()
      case .anonymous:
        AuthenticationView()
          .noticeArea(.authentication)
          .noticeSafeAreaHost()
      case .authenticated:
        AuthenticatedTabView()
      }
    }
    .background(RentivoColors.paper.ignoresSafeArea())
    .onAppear { app.updateNoticeReduceMotion(reduceMotion) }
    .onChange(of: reduceMotion) { _, enabled in app.updateNoticeReduceMotion(enabled) }
    .task { await app.restoreSessionIfNeeded() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { app.sceneDidBecomeInactive() }
    }
  }
}

private struct SessionRestorationView: View {
  var body: some View {
    ZStack {
      RentivoColors.paper.ignoresSafeArea()
      VStack(spacing: RentivoSpacing.large) {
        BrandMark()
          .accessibilityHidden(true)
        ProgressView()
          .tint(RentivoColors.emerald)
          .accessibilityHidden(true)
        Text("Restaurando sua sessão…")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(RentivoColors.secondaryInk)
          .fixedSize(horizontal: false, vertical: true)
      }
      .multilineTextAlignment(.center)
      .padding(RentivoSpacing.page)
    }
    .accessibilityIdentifier("session.restore")
  }
}

struct AuthenticatedTabView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    @Bindable var app = app
    TabView(selection: $app.selectedTab) {
      NavigationStack {
        HomeView()
      }
      .noticeArea(.home)
      .noticeSafeAreaHost(isActive: app.selectedTab == .home)
      .rentivoTabBarAppearance()
      .tag(AppTab.home)
      .tabItem { Label("Início", systemImage: "house") }

      NavigationStack {
        BillingListView()
      }
      .noticeArea(.billings)
      .noticeSafeAreaHost(isActive: app.selectedTab == .billings)
      .rentivoTabBarAppearance()
      .tag(AppTab.billings)
      .tabItem { Label("Cobranças", systemImage: "doc.text") }

      NavigationStack {
        OrganizationListView()
      }
      .noticeArea(.organizations)
      .noticeSafeAreaHost(isActive: app.selectedTab == .organizations)
      .rentivoTabBarAppearance()
      .tag(AppTab.organizations)
      .tabItem { Label("Organizações", systemImage: "building.2") }

      NavigationStack {
        AccountView()
      }
      .noticeArea(.account)
      .noticeSafeAreaHost(isActive: app.selectedTab == .account)
      .rentivoTabBarAppearance()
      .tag(AppTab.account)
      .tabItem { Label("Conta", systemImage: "person.crop.circle") }
    }
    // A fully opaque surface behind the native floating material prevents content from being
    // legible through it without assuming a fixed tab-bar height.
    .background(RentivoColors.surface.ignoresSafeArea(edges: .bottom))
    .accessibilityIdentifier("tab.scaffold")
    .onAppear { app.activateNoticeArea(app.selectedTab.noticeArea) }
  }
}

private struct NoticeSafeAreaHostModifier: ViewModifier {
  @Environment(AppModel.self) private var app
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let isActive: Bool

  func body(content: Content) -> some View {
    content.safeAreaInset(edge: .bottom, spacing: 0) {
      if isActive, let notice = app.notice {
        NoticeToast(
          notice: notice,
          reduceMotion: reduceMotion,
          didMount: {
            app.noticeDidMount(
              id: notice.id,
              voiceOverEnabled: UIAccessibility.isVoiceOverRunning,
              reduceMotion: reduceMotion
            )
          },
          interactionBegan: { app.noticeInteractionBegan(id: notice.id) },
          interactionEnded: { committed in
            app.noticeInteractionEnded(id: notice.id, committed: committed)
          },
          dismiss: { app.dismissNotice(id: notice.id) }
        )
        .frame(maxWidth: 560)
        .padding(.horizontal, RentivoSpacing.page)
        // The card's 3 pt hard shadow also has to clear the required 12 pt gap.
        .padding(.bottom, RentivoSpacing.medium + RentivoSpacing.tiny)
        .transition(
          reduceMotion
            ? .opacity
            : .asymmetric(
              insertion: .offset(y: 16).combined(with: .opacity),
              removal: .offset(y: 12).combined(with: .opacity)
            )
        )
      }
    }
  }
}

extension View {
  fileprivate func noticeSafeAreaHost(isActive: Bool = true) -> some View {
    modifier(NoticeSafeAreaHostModifier(isActive: isActive))
  }
}
