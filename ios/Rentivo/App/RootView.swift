import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    Group {
      switch app.session {
      case .restoring:
        SessionRestorationView()
      case .anonymous:
        AuthenticationView()
      case .authenticated:
        AuthenticatedTabView()
      }
    }
    .background(RentivoColors.paper.ignoresSafeArea())
    .task { await app.restoreSessionIfNeeded() }
    .overlay(alignment: .top) {
      if let notice = app.notice {
        NoticeBanner(notice: notice) {
          withAnimation { app.notice = nil }
        }
        .padding(.horizontal, RentivoSpacing.page)
        .padding(.top, RentivoSpacing.small)
        .transition(.move(edge: .top).combined(with: .opacity))
      }
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
      .tag(AppTab.home)
      .tabItem { Label("Início", systemImage: "house") }

      NavigationStack {
        BillingListView()
      }
      .tag(AppTab.billings)
      .tabItem { Label("Cobranças", systemImage: "doc.text") }

      NavigationStack {
        OrganizationListView()
      }
      .tag(AppTab.organizations)
      .tabItem { Label("Organizações", systemImage: "building.2") }

      NavigationStack {
        AccountView()
      }
      .tag(AppTab.account)
      .tabItem { Label("Conta", systemImage: "person.crop.circle") }
    }
  }
}
