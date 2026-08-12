import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    Group {
      switch app.session {
      case .restoring:
        ProgressView("Restaurando sessão…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .anonymous:
        AuthenticationView()
      case .authenticated:
        MainSplitView()
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
        .transition(.rentivoNotice)
      }
    }
    // The banner is the app's only global overlay, so animating on the notice identity here
    // covers both arrival and replacement (a second notice while the first is still showing).
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: app.notice?.id)
  }
}
