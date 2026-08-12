import RentivoCore
import SwiftUI

struct AuthenticationView: View {
  var body: some View {
    LoginView()
      .background(RentivoColors.paper)
  }
}

private struct AuthScaffold<Content: View>: View {
  let title: String
  let subtitle: String
  let content: Content
  @State private var hasAppeared = false

  init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: RentivoSpacing.page) {
        BrandMark()
          .padding(.bottom, RentivoSpacing.small)
          // The sign-in window is the first thing a cold launch shows, so the mark settles in
          // instead of appearing fully formed with the rest of the card.
          .opacity(hasAppeared ? 1 : 0)
          .offset(y: hasAppeared ? 0 : -12)
        VStack(alignment: .leading, spacing: RentivoSpacing.small) {
          Text(title)
            .font(RentivoTypography.display)
            .foregroundStyle(RentivoColors.ink)
          Text(subtitle)
            .font(RentivoTypography.body)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        RentivoCard { content }
      }
      .padding(RentivoSpacing.page)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .rentivoPage()
    .onAppear {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { hasAppeared = true }
    }
  }
}

struct LoginView: View {
  @Environment(AppModel.self) private var app
  @State private var validationMessage: String?
  @State private var isAuthenticating = false

  var body: some View {
    AuthScaffold(
      title: "Boas-vindas",
      subtitle: "Entre com sua conta Rentivo para acessar seus dados."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        if let validationMessage {
          Label(validationMessage, systemImage: "exclamationmark.circle.fill")
            .font(RentivoTypography.captionStrong)
            .foregroundStyle(RentivoColors.coral)
            .accessibilityIdentifier("login.error")
        }
        Button(action: submit) {
          HStack(spacing: RentivoSpacing.small) {
            if isAuthenticating {
              ProgressView()
                .controlSize(.small)
                .tint(.white)
            }
            Text("Entrar")
          }
        }
        .buttonStyle(RentivoButtonStyle())
        .disabled(isAuthenticating)
        .accessibilityIdentifier("login.submit")
        Text("O login continua no site seguro do Rentivo para concluir a verificação de segurança.")
          .font(RentivoTypography.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    }
  }

  private func submit() {
    guard !isAuthenticating else { return }
    validationMessage = nil
    isAuthenticating = true
    Task {
      defer { isAuthenticating = false }
      do {
        try await app.signInWithWebAuthorization()
      } catch {
        guard !MobileWebAuthenticator.isUserCancellation(error) else { return }
        validationMessage = ptBRDescription(for: error)
      }
    }
  }

  private func ptBRDescription(for error: Error) -> String {
    if let liveError = error as? LiveAPIError, let description = liveError.errorDescription {
      return description
    }
    return "Não foi possível concluir o login. Tente novamente."
  }
}
