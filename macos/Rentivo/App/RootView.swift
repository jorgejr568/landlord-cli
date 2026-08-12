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
    // The app-wide text default. macOS resolves its own default to 13pt, which is the size the
    // readability complaint was about, and it reaches the text no `.font(...)` names directly:
    // sidebar labels, grouped-form rows and their `LabeledContent` values, empty-state copy, and
    // plain button titles. Setting it here rather than per call site keeps those in step with the
    // tokens, and any explicit `.font(...)` further down still wins.
    .font(RentivoTypography.body)
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
