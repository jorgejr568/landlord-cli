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
    // Signing out and deleting the account both leave the current screen in place while they wait
    // on the server. Dimming and disabling it says the window is busy and stops the user from
    // starting work that is about to be thrown away with the session. The overlays below are
    // applied after this, so the banners stay lit and interactive.
    .opacity(app.globalActivityMessage == nil ? 1 : 0.55)
    .disabled(app.globalActivityMessage != nil)
    .task { await app.restoreSessionIfNeeded() }
    // One overlay for both banners, not one each: as two overlays with the same alignment and the
    // same padding they landed on top of each other, and signing out — which raises the activity
    // banner — would bury a notice that was still on screen, dismiss button and all.
    .overlay(alignment: .top) {
      VStack(spacing: RentivoSpacing.small) {
        if let notice = app.notice {
          NoticeBanner(notice: notice) {
            withAnimation { app.notice = nil }
          }
          .transition(.rentivoNotice)
        }
        if let message = app.globalActivityMessage {
          GlobalActivityBanner(message: message)
            .transition(.rentivoNotice)
        }
      }
      .padding(.horizontal, RentivoSpacing.page)
      .padding(.top, RentivoSpacing.small)
    }
    // The banner is the app's only global overlay, so animating on the notice identity here
    // covers both arrival and replacement (a second notice while the first is still showing).
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: app.notice?.id)
    .animation(.spring(response: 0.34, dampingFraction: 0.82), value: app.globalActivityMessage)
  }
}

/// The "the whole window is waiting on the server" banner, in `NoticeBanner`'s chrome so the two
/// read as the same surface. It carries no dismiss button on purpose: it is not something the user
/// acknowledges, it is something they wait for, and it clears itself when the request finishes.
private struct GlobalActivityBanner: View {
  let message: String

  var body: some View {
    HStack(spacing: RentivoSpacing.medium) {
      ProgressView()
        .controlSize(.small)
      Text(message)
        .font(RentivoTypography.bodyStrong)
        .foregroundStyle(RentivoColors.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(RentivoSpacing.medium)
    .background(RentivoColors.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(RentivoColors.ink, lineWidth: 2)
    }
    .shadow(color: RentivoColors.ink, radius: 0, x: 3, y: 3)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("app.globalActivity")
  }
}
