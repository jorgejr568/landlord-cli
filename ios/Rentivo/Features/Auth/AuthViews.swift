import SwiftUI
import UIKit

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
        VStack(alignment: .leading, spacing: RentivoSpacing.small) {
          Text(title)
            .font(RentivoTypography.display)
            .foregroundStyle(RentivoColors.ink)
          Text(subtitle)
            .font(.body)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        RentivoCard { content }
      }
      .padding(RentivoSpacing.page)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .rentivoPage()
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
        .font(.body)
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

private extension View {
  /// Renders a placeholder we own, so its colour is deterministic. iOS tints the *native*
  /// placeholder of an autofill-eligible username field in the system accent once saved
  /// credentials exist, which reads like pre-filled link text; owning it keeps the placeholder
  /// the exact system placeholder grey the other fields render natively.
  func authFieldPlaceholder(_ text: String, visible: Bool) -> some View {
    overlay(alignment: .leading) {
      if visible {
        Text(text)
          .foregroundStyle(Color(uiColor: .placeholderText))
          .allowsHitTesting(false)
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
      .rentivoInlineLink()
  }
}

private struct AuthErrorLabel: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote.weight(.semibold))
      .foregroundStyle(RentivoColors.error)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// The sign-in flow: credentials, account creation, and the second factor a login can stop at.
///
/// The pending `MFAChallenge` lives here rather than in `AppModel` because it is screen state —
/// it exists only while this view is on screen, and leaving the screen (or going back to the
/// credential form) is what discards it.
/// The typed credentials live here rather than inside `SignInForm` for the same reason: showing
/// the challenge takes `SignInForm` out of the hierarchy, and a `@State` property dies with the
/// view that owns it. Held one level up, "Voltar" comes back to the form the user actually filled
/// in instead of two empty fields. The password is kept alongside the e-mail on purpose — the MFA
/// step is the same screen and the same sign-in attempt, so re-typing it would be a penalty for
/// nothing; it goes away with the whole screen the moment the login lands.
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
  @State private var isPasswordRevealed = false

  private var canSubmit: Bool {
    !isAuthenticating && AuthEmailAddress.isValid(email)
      && BcryptPasswordRules.isAccepted(password)
  }

  var body: some View {
    AuthScaffold(
      title: "Boas-vindas",
      subtitle: "Entre com sua conta Rentivo para acessar seus dados."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        AuthField("E-MAIL") {
          TextField("", text: $email)
            .keyboardType(.emailAddress)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .authFieldPlaceholder("voce@exemplo.com.br", visible: email.isEmpty)
            .accessibilityIdentifier("login.email")
        }
        RentivoSecureFormField(
          label: "SENHA",
          text: $password,
          isRevealed: $isPasswordRevealed,
          prompt: "Sua senha",
          textContentType: .password,
          accessibilityIdentifier: "login.password",
          visibilityAccessibilityName: "senha"
        )
        .submitLabel(.go)
        .onSubmit(submit)
        Link(
          "Esqueceu sua senha?",
          destination: LiveAPIClient.productionURL.appending(path: "forgot-password")
        )
        .rentivoInlineLink()
        .tint(RentivoColors.link)
        .accessibilityIdentifier("login.forgot")
        if let validationMessage {
          AuthErrorLabel(message: validationMessage)
            .accessibilityIdentifier("login.error")
        }
        Button(action: submit) {
          Text("Entrar")
        }
        .buttonStyle(RentivoButtonStyle(isBusy: isAuthenticating))
        .disabled(!canSubmit)
        .accessibilityIdentifier("login.submit")
        HStack(spacing: RentivoSpacing.tiny) {
          Text("Ainda não tem uma conta?")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
          AuthLinkButton(title: "Criar conta", action: onCreateAccount)
            .accessibilityIdentifier("login.signup")
        }
      }
    }
  }

  private func submit() {
    guard canSubmit else { return }
    authenticate {
      if case .mfaRequired(let challenge) = try await app.signIn(
        email: email.trimmed, password: password)
      {
        onChallenge(challenge)
      }
    }
  }

  private func authenticate(_ operation: @escaping () async throws -> Void) {
    validationMessage = nil
    isAuthenticating = true
    Task {
      defer { isAuthenticating = false }
      do {
        try await operation()
      } catch {
        validationMessage = AuthFeedback.presentation(for: error, context: .signIn).message
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
  @State private var isPasswordRevealed = false
  @State private var isConfirmationRevealed = false
  @State private var confirmationTouched = false
  @State private var shouldValidateConfirmation = false
  @State private var confirmationIsFocused = false
  @State private var confirmationValidationTask: Task<Void, Never>?

  private var confirmationError: String? {
    SignUpConfirmationRules.errorMessage(
      password: password,
      confirmation: confirmPassword,
      isTouched: confirmationTouched,
      shouldValidate: shouldValidateConfirmation
    )
  }

  private var canSubmit: Bool {
    !isAuthenticating && AuthEmailAddress.isValid(email)
      && BcryptPasswordRules.isAccepted(password) && password == confirmPassword
  }

  var body: some View {
    AuthScaffold(
      title: "Criar conta",
      subtitle: "Crie sua conta Rentivo para organizar as cobranças dos seus imóveis."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        AuthField("E-MAIL") {
          TextField("", text: $email)
            .keyboardType(.emailAddress)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .authFieldPlaceholder("voce@exemplo.com.br", visible: email.isEmpty)
            .accessibilityIdentifier("signup.email")
        }
        RentivoSecureFormField(
          label: "SENHA",
          text: $password,
          isRevealed: $isPasswordRevealed,
          prompt: "Crie uma senha",
          textContentType: .newPassword,
          accessibilityIdentifier: "signup.password",
          visibilityAccessibilityName: "senha"
        )
        RentivoSecureFormField(
          label: "CONFIRMAR SENHA",
          text: $confirmPassword,
          isRevealed: $isConfirmationRevealed,
          prompt: "Repita a senha",
          errorMessage: confirmationError,
          isFocused: $confirmationIsFocused,
          textContentType: .newPassword,
          accessibilityIdentifier: "signup.confirm",
          visibilityAccessibilityName: "confirmação da senha",
          errorAccessibilityIdentifier: "signup.confirm.error"
        )
        .submitLabel(.go)
        .onSubmit {
          validateConfirmationImmediately(announce: true)
          submit()
        }
        if let validationMessage {
          AuthErrorLabel(message: validationMessage)
            .accessibilityIdentifier("signup.error")
        }
        Button(action: submit) {
          Text("Criar Conta")
        }
        .buttonStyle(RentivoButtonStyle(isBusy: isAuthenticating))
        .disabled(!canSubmit)
        .accessibilityIdentifier("signup.submit")
        HStack(spacing: RentivoSpacing.tiny) {
          Text("Já tem uma conta?")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
          AuthLinkButton(title: "Entrar", action: onSignIn)
            .accessibilityIdentifier("signup.login")
        }
      }
    }
    .onChange(of: password) { _, _ in confirmationInputChanged() }
    .onChange(of: confirmPassword) { oldValue, newValue in
      if oldValue != newValue { confirmationTouched = true }
      confirmationInputChanged()
    }
    .onChange(of: confirmationIsFocused) { oldValue, newValue in
      if oldValue && !newValue { validateConfirmationImmediately(announce: true) }
    }
    .onDisappear { confirmationValidationTask?.cancel() }
  }

  private func submit() {
    validateConfirmationImmediately(announce: true)
    guard canSubmit else { return }
    validationMessage = nil
    isAuthenticating = true
    Task {
      defer { isAuthenticating = false }
      do {
        try await app.signUp(email: email.trimmed, password: password)
      } catch {
        validationMessage = AuthFeedback.presentation(for: error, context: .signUp).message
      }
    }
  }

  private func confirmationInputChanged() {
    confirmationValidationTask?.cancel()
    guard confirmationTouched, !confirmPassword.isEmpty, password != confirmPassword else {
      shouldValidateConfirmation = false
      return
    }
    shouldValidateConfirmation = false
    let passwordSnapshot = password
    let confirmationSnapshot = confirmPassword
    confirmationValidationTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled,
        password == passwordSnapshot,
        confirmPassword == confirmationSnapshot
      else { return }
      shouldValidateConfirmation = true
    }
  }

  private func validateConfirmationImmediately(announce: Bool) {
    confirmationValidationTask?.cancel()
    confirmationTouched = true
    let hadError = confirmationError != nil
    shouldValidateConfirmation = true
    if announce, !hadError, confirmationError != nil {
      UIAccessibility.post(
        notification: .announcement,
        argument: SignUpConfirmationRules.mismatchMessage
      )
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

  private enum Operation: Equatable {
    case totp
    case recovery
    case passkey
  }

  @Environment(AppModel.self) private var app
  let challenge: MFAChallenge
  let onCancel: () -> Void
  @State private var code = ""
  @State private var codeKind: CodeKind
  @State private var validationMessage: String?
  @State private var operation: Operation?
  @State private var lastSubmittedValue: String?
  @State private var isTerminal = false
  @FocusState private var codeIsFocused: Bool
  @AccessibilityFocusState private var terminalErrorIsFocused: Bool

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

  private var isAuthenticating: Bool { operation != nil }
  private var canSubmitCode: Bool {
    guard !isAuthenticating else { return false }
    return switch codeKind {
    case .totp: code.count == TOTPCodeRules.requiredLength
    case .recovery: !code.trimmed.isEmpty
    }
  }

  var body: some View {
    AuthScaffold(
      title: "Verificação em duas etapas",
      subtitle: "Confirme que é você para concluir a entrada."
    ) {
      VStack(alignment: .leading, spacing: RentivoSpacing.large) {
        if isTerminal {
          if let validationMessage {
            AuthErrorLabel(message: validationMessage)
              .accessibilityIdentifier("login.mfa.error")
              .accessibilityFocused($terminalErrorIsFocused)
          }
          Button("Voltar para entrar", action: onCancel)
            .buttonStyle(RentivoButtonStyle())
            .accessibilityIdentifier("login.mfa.return-to-login")
        } else if offersPasskey {
          Button(action: submitPasskey) {
            Text("Usar chave de acesso")
          }
          .buttonStyle(
            RentivoSecondaryButtonStyle(isBusy: operation == .passkey)
          )
          .disabled(isAuthenticating)
          .accessibilityIdentifier("login.mfa.passkey")
        }
        if !isTerminal {
          if offersCode {
            switch codeKind {
            case .totp:
              totpInput
            case .recovery:
              AuthField(codeKind.label) {
                TextField(codeKind.placeholder, text: $code)
                  .keyboardType(.asciiCapable)
                  .textInputAutocapitalization(.characters)
                  .autocorrectionDisabled()
                  .submitLabel(.go)
                  .onSubmit { submitCode() }
                  .focused($codeIsFocused)
                  .disabled(isAuthenticating)
                  .accessibilityIdentifier("login.mfa.code")
              }
            }
          }
          if let validationMessage {
            AuthErrorLabel(message: validationMessage)
              .accessibilityIdentifier("login.mfa.error")
          }
          if offersCode {
            Button(action: { submitCode() }) {
              Text("Confirmar")
            }
            .buttonStyle(
              RentivoButtonStyle(isBusy: operation == codeOperation)
            )
            .disabled(!canSubmitCode)
            .accessibilityIdentifier("login.mfa.submit")
          }
          if offersRecovery && offersTOTP {
            AuthLinkButton(
              title: codeKind == .totp
                ? "Usar código de recuperação" : "Usar código do aplicativo autenticador"
            ) {
              switchCodeKind()
            }
            .disabled(isAuthenticating)
            .accessibilityIdentifier("login.mfa.recovery")
          }
          if !offersCode && !offersPasskey {
            Text("Nenhuma verificação disponível para este dispositivo.")
              .font(.footnote)
              .foregroundStyle(RentivoColors.secondaryInk)
          }
          AuthLinkButton(title: "Voltar", action: onCancel)
            .disabled(isAuthenticating)
            .accessibilityIdentifier("login.mfa.cancel")
        }
      }
    }
    .onChange(of: code) { oldValue, newValue in codeChanged(from: oldValue, to: newValue) }
    .task {
      if codeKind == .totp { codeIsFocused = true }
    }
  }

  private var codeOperation: Operation {
    codeKind == .totp ? .totp : .recovery
  }

  private var totpInput: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.small) {
      Text(CodeKind.totp.label)
        .font(RentivoTypography.metadata)
        .foregroundStyle(RentivoColors.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
      Text("Digite os 6 dígitos exibidos no seu aplicativo autenticador.")
        .font(.footnote)
        .foregroundStyle(RentivoColors.secondaryInk)
        .fixedSize(horizontal: false, vertical: true)
      TextField("000000", text: $code)
        .font(RentivoTypography.code)
        .multilineTextAlignment(.center)
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($codeIsFocused)
        .disabled(isAuthenticating)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RentivoColors.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(codeIsFocused ? RentivoColors.primaryAction : RentivoColors.ink, lineWidth: 2)
        }
        .accessibilityLabel("Código do aplicativo autenticador")
        .accessibilityHint(
          "Digite ou cole 6 dígitos. A verificação começa automaticamente ao completar o código."
        )
        .accessibilityValue("\(code.count) de 6 dígitos preenchidos")
        .accessibilityIdentifier("login.mfa.code")
    }
  }

  private func codeChanged(from oldValue: String, to newValue: String) {
    guard codeKind == .totp else { return }
    let previous = TOTPCodeRules.normalize(oldValue)
    let normalized = TOTPCodeRules.normalize(newValue)
    if code != normalized { code = normalized }
    if TOTPCodeRules.shouldAutoSubmit(
      previousValue: previous,
      currentValue: normalized,
      isBusy: isAuthenticating,
      lastSubmittedValue: lastSubmittedValue
    ) {
      submitCode(submittedValue: normalized)
    }
  }

  private func submitCode(submittedValue: String? = nil) {
    guard !isAuthenticating else { return }
    let submitted = submittedValue ?? (codeKind == .totp ? code : code.trimmed)
    guard codeKind == .totp
      ? submitted.count == TOTPCodeRules.requiredLength
      : !submitted.isEmpty
    else { return }
    lastSubmittedValue = submitted
    verify(operation: codeOperation) {
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
    verify(operation: .passkey) {
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

  private func verify(
    operation requestedOperation: Operation,
    _ action: @escaping () async throws -> Void
  ) {
    validationMessage = nil
    operation = requestedOperation
    Task {
      defer { operation = nil }
      do {
        try await action()
      } catch {
        let context: AuthFeedbackContext = switch requestedOperation {
        case .totp: .mfaTOTP
        case .recovery: .mfaRecovery
        case .passkey: .mfaPasskey
        }
        let feedback = AuthFeedback.presentation(for: error, context: context)
        validationMessage = feedback.message
        if feedback.disposition == .terminal {
          code = ""
          lastSubmittedValue = nil
          isTerminal = true
          Task { @MainActor in terminalErrorIsFocused = true }
        } else if (error as? LiveAPIError)?.problemCode == "invalid_mfa_code" {
          code = ""
          lastSubmittedValue = nil
          Task { @MainActor in codeIsFocused = true }
        }
      }
    }
  }

  private func switchCodeKind() {
    guard !isAuthenticating else { return }
    codeKind = codeKind == .totp ? .recovery : .totp
    code = ""
    validationMessage = nil
    lastSubmittedValue = nil
    operation = nil
    Task { @MainActor in codeIsFocused = true }
  }
}

extension String {
  fileprivate var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
