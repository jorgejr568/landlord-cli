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

/// A labelled credential field, drawn with the same ink outline the cards and buttons use.
private struct AuthField<Field: View>: View {
  let label: String
  let field: Field

  init(_ label: String, @ViewBuilder field: () -> Field) {
    self.label = label
    self.field = field()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
      Text(label)
        .font(RentivoTypography.metadata)
        .foregroundStyle(RentivoColors.secondaryInk)
      field
        .textFieldStyle(.plain)
        .font(RentivoTypography.body)
        .foregroundStyle(RentivoColors.ink)
        .padding(RentivoSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RentivoColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(RentivoColors.ink, lineWidth: 2)
        }
    }
  }
}

/// An inline text action ("Criar conta", "Usar código de recuperação"): a button that reads as a
/// link instead of taking the primary `RentivoButtonStyle` treatment.
private struct AuthLinkButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(title, action: action)
      .buttonStyle(.plain)
      .font(RentivoTypography.captionStrong)
      .foregroundStyle(RentivoColors.blue)
  }
}

private struct AuthErrorLabel: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(RentivoTypography.captionStrong)
      .foregroundStyle(RentivoColors.coral)
  }
}

/// The sign-in flow: credentials, account creation, and the second factor a login can stop at.
///
/// The pending `MFAChallenge` lives here rather than in `AppModel` because it is screen state —
/// it exists only while this view is on screen, and leaving the screen (or going back to the
/// credential form) is what discards it. The typed credentials live here for the same reason:
/// showing the challenge takes `SignInForm` out of the hierarchy, and a `@State` property dies with
/// the view that owns it. Held one level up, "Voltar" comes back to the form the user actually
/// filled in instead of two empty fields.
struct LoginView: View {
  @State private var challenge: MFAChallenge?
  @State private var isCreatingAccount = false
  @State private var email = ""
  @State private var password = ""

  var body: some View {
    if let challenge {
      MFAChallengeForm(challenge: challenge, onCancel: { self.challenge = nil })
    } else if isCreatingAccount {
      SignUpForm(onSignIn: { isCreatingAccount = false })
    } else {
      SignInForm(
        email: $email,
        password: $password,
        onCreateAccount: { isCreatingAccount = true },
        onChallenge: { challenge = $0 }
      )
    }
  }
}

private struct SignInForm: View {
  @Environment(AppModel.self) private var app
  @Binding var email: String
  @Binding var password: String
  let onCreateAccount: () -> Void
  let onChallenge: (MFAChallenge) -> Void
  @State private var validationMessage: String?
  @State private var isAuthenticating = false

  private var canSubmit: Bool {
    !isAuthenticating && !email.trimmed.isEmpty && !password.isEmpty
  }

  var body: some View {
    AuthScaffold(
      title: "Boas-vindas",
      subtitle: "Entre com sua conta Rentivo para acessar seus dados."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        AuthField("E-MAIL") {
          TextField("voce@exemplo.com.br", text: $email)
            .textContentType(.username)
            .autocorrectionDisabled()
            .onSubmit(submit)
            .accessibilityIdentifier("login.email")
        }
        AuthField("SENHA") {
          SecureField("Sua senha", text: $password)
            .textContentType(.password)
            .onSubmit(submit)
            .accessibilityIdentifier("login.password")
        }
        Link(
          "Esqueceu sua senha?",
          destination: LiveAPIClient.productionURL.appending(path: "forgot-password")
        )
        .font(RentivoTypography.captionStrong)
        .accessibilityIdentifier("login.forgot")
        if let validationMessage {
          AuthErrorLabel(message: validationMessage)
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
        .disabled(!canSubmit)
        .accessibilityIdentifier("login.submit")
        HStack(spacing: RentivoSpacing.tiny) {
          Text("Ainda não tem uma conta?")
            .font(RentivoTypography.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
          AuthLinkButton(title: "Criar conta", action: onCreateAccount)
            .accessibilityIdentifier("login.signup")
        }
      }
    }
  }

  private func submit() {
    guard canSubmit else { return }
    validationMessage = nil
    isAuthenticating = true
    Task {
      defer { isAuthenticating = false }
      do {
        if case .mfaRequired(let challenge) = try await app.signIn(
          email: email.trimmed, password: password)
        {
          onChallenge(challenge)
        }
      } catch {
        validationMessage = ptBRDescription(for: error)
      }
    }
  }
}

private struct SignUpForm: View {
  @Environment(AppModel.self) private var app
  let onSignIn: () -> Void
  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var validationMessage: String?
  @State private var isAuthenticating = false

  private var canSubmit: Bool {
    !isAuthenticating && !email.trimmed.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
  }

  var body: some View {
    AuthScaffold(
      title: "Criar conta",
      subtitle: "Crie sua conta Rentivo para organizar as cobranças dos seus imóveis."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        AuthField("E-MAIL") {
          TextField("voce@exemplo.com.br", text: $email)
            .textContentType(.username)
            .autocorrectionDisabled()
            .accessibilityIdentifier("signup.email")
        }
        AuthField("SENHA") {
          SecureField("Crie uma senha", text: $password)
            .textContentType(.newPassword)
            .accessibilityIdentifier("signup.password")
        }
        AuthField("CONFIRMAR SENHA") {
          SecureField("Repita a senha", text: $confirmPassword)
            .textContentType(.newPassword)
            .onSubmit(submit)
            .accessibilityIdentifier("signup.confirm")
        }
        if let validationMessage {
          AuthErrorLabel(message: validationMessage)
            .accessibilityIdentifier("signup.error")
        }
        Button(action: submit) {
          HStack(spacing: RentivoSpacing.small) {
            if isAuthenticating {
              ProgressView()
                .controlSize(.small)
                .tint(.white)
            }
            Text("Criar Conta")
          }
        }
        .buttonStyle(RentivoButtonStyle())
        .disabled(!canSubmit)
        .accessibilityIdentifier("signup.submit")
        HStack(spacing: RentivoSpacing.tiny) {
          Text("Já tem uma conta?")
            .font(RentivoTypography.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
          AuthLinkButton(title: "Entrar", action: onSignIn)
            .accessibilityIdentifier("signup.login")
        }
      }
    }
  }

  private func submit() {
    guard canSubmit else { return }
    // The API takes only e-mail and password; the confirmation exists to catch a mistyped
    // password here, before an account is created with it.
    guard password == confirmPassword else {
      validationMessage = "As senhas não coincidem."
      return
    }
    validationMessage = nil
    isAuthenticating = true
    Task {
      defer { isAuthenticating = false }
      do {
        try await app.signUp(email: email.trimmed, password: password)
      } catch {
        validationMessage = ptBRDescription(for: error)
      }
    }
  }
}

/// The second factor a login stopped at. Which factors appear is decided by the challenge: the
/// server lists exactly what it will accept, and a factor the app cannot present (or one this
/// build does not know) is simply not offered.
private struct MFAChallengeForm: View {
  private enum CodeKind {
    case totp
    case recovery

    var label: String {
      switch self {
      case .totp: "CÓDIGO DO APLICATIVO AUTENTICADOR"
      case .recovery: "CÓDIGO DE RECUPERAÇÃO"
      }
    }

    var placeholder: String {
      switch self {
      case .totp: "000000"
      case .recovery: "XXXX-XXXX"
      }
    }
  }

  @Environment(AppModel.self) private var app
  let challenge: MFAChallenge
  let onCancel: () -> Void
  @State private var code = ""
  @State private var codeKind: CodeKind
  @State private var validationMessage: String?
  @State private var isAuthenticating = false

  init(challenge: MFAChallenge, onCancel: @escaping () -> Void) {
    self.challenge = challenge
    self.onCancel = onCancel
    // The authenticator app is the everyday factor; recovery codes are the fallback the user
    // asks for, so the form only starts there when TOTP is not on offer at all.
    _codeKind = State(initialValue: challenge.methods.contains(.totp) ? .totp : .recovery)
  }

  private var offersPasskey: Bool { challenge.methods.contains(.passkey) }
  private var offersTOTP: Bool { challenge.methods.contains(.totp) }
  private var offersRecovery: Bool { challenge.methods.contains(.recovery) }
  private var offersCode: Bool { offersTOTP || offersRecovery }

  private var canSubmitCode: Bool { !isAuthenticating && !code.trimmed.isEmpty }

  var body: some View {
    AuthScaffold(
      title: "Verificação em duas etapas",
      subtitle: "Confirme que é você para concluir a entrada."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        if offersPasskey {
          Button(action: submitPasskey) {
            HStack(spacing: RentivoSpacing.small) {
              if isAuthenticating {
                ProgressView()
                  .controlSize(.small)
                  .tint(.white)
              }
              Text("Usar chave de acesso")
            }
          }
          .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
          .disabled(isAuthenticating)
          .accessibilityIdentifier("login.mfa.passkey")
        }
        if offersCode {
          AuthField(codeKind.label) {
            TextField(codeKind.placeholder, text: $code)
              // `.oneTimeCode` is what surfaces the authenticator code from the keychain/handoff; a
              // recovery code is a stored secret, never an incoming one, so the hint would only
              // offer an unrelated TOTP in its place.
              .textContentType(codeKind == .totp ? .oneTimeCode : nil)
              .autocorrectionDisabled()
              .onSubmit(submitCode)
              .accessibilityIdentifier("login.mfa.code")
          }
        }
        if let validationMessage {
          AuthErrorLabel(message: validationMessage)
            .accessibilityIdentifier("login.mfa.error")
        }
        if offersCode {
          Button(action: submitCode) {
            HStack(spacing: RentivoSpacing.small) {
              if isAuthenticating {
                ProgressView()
                  .controlSize(.small)
                  .tint(.white)
              }
              Text("Confirmar")
            }
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(!canSubmitCode)
          .accessibilityIdentifier("login.mfa.submit")
        }
        if offersRecovery && offersTOTP {
          AuthLinkButton(
            title: codeKind == .totp
              ? "Usar código de recuperação" : "Usar código do aplicativo autenticador"
          ) {
            codeKind = codeKind == .totp ? .recovery : .totp
            code = ""
            validationMessage = nil
          }
          .accessibilityIdentifier("login.mfa.recovery")
        }
        if !offersCode && !offersPasskey {
          Text("Nenhuma verificação disponível neste aplicativo. Tente entrar novamente.")
            .font(RentivoTypography.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        AuthLinkButton(title: "Voltar", action: onCancel)
          .disabled(isAuthenticating)
          .accessibilityIdentifier("login.mfa.cancel")
      }
    }
  }

  private func submitCode() {
    guard canSubmitCode else { return }
    let submitted = code.trimmed
    verify {
      switch codeKind {
      case .totp:
        try await app.completeTOTP(challenge: challenge, code: submitted)
      case .recovery:
        try await app.completeRecoveryCode(challenge: challenge, code: submitted)
      }
    }
  }

  private func submitPasskey() {
    guard !isAuthenticating else { return }
    verify {
      let options = try await app.dependencies.auth.beginPasskeyAssertion(challenge: challenge)
      // Held for the whole assertion: `ASAuthorizationController` only calls back while its
      // owner is alive.
      let controller = PasskeyAssertionController()
      do {
        let credential = try await controller.assert(options: options)
        try await app.completePasskey(challenge: challenge, credential: credential)
      } catch {
        // Closing the system sheet is a choice, not a failure — the challenge stays on screen
        // with its other factors.
        guard !PasskeyAssertionController.isUserCancellation(error) else { return }
        throw error
      }
    }
  }

  private func verify(_ operation: @escaping () async throws -> Void) {
    validationMessage = nil
    isAuthenticating = true
    Task {
      defer { isAuthenticating = false }
      do {
        try await operation()
      } catch {
        code = ""
        validationMessage = ptBRDescription(for: error)
      }
    }
  }
}

/// The server already answers in PT-BR (`detail` on the problem document), so its message is
/// preferred over anything invented here; everything else falls back to one generic sentence
/// rather than leaking a system error string in English.
private func ptBRDescription(for error: Error) -> String {
  if let liveError = error as? LiveAPIError, let description = liveError.errorDescription {
    return description
  }
  return "Não foi possível concluir o login. Tente novamente."
}

extension String {
  fileprivate var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
