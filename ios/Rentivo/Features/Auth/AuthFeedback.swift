import Foundation

enum SignUpConfirmationRules {
  static let mismatchMessage = "As senhas não coincidem."

  static func errorMessage(
    password: String,
    confirmation: String,
    isTouched: Bool,
    shouldValidate: Bool
  ) -> String? {
    guard isTouched, shouldValidate, !password.isEmpty, !confirmation.isEmpty else { return nil }
    return password == confirmation ? nil : mismatchMessage
  }
}

enum TOTPCodeRules {
  static let requiredLength = 6

  static func normalize(_ value: String) -> String {
    String(
      value.unicodeScalars
        .filter { (48...57).contains(Int($0.value)) }
        .prefix(requiredLength)
        .map(Character.init)
    )
  }

  static func shouldAutoSubmit(
    previousValue: String,
    currentValue: String,
    isBusy: Bool,
    lastSubmittedValue: String?
  ) -> Bool {
    !isBusy
      && previousValue.count < requiredLength
      && currentValue.count == requiredLength
      && currentValue != lastSubmittedValue
  }
}

enum AuthFeedbackContext: CaseIterable, Hashable {
  case signIn
  case signUp
  case mfaTOTP
  case mfaRecovery
  case mfaPasskey
  case totpEnrollment
}

enum AuthFeedbackDisposition: Equatable {
  case recoverable
  case terminal
}

struct AuthFeedbackPresentation: Equatable {
  let message: String
  let disposition: AuthFeedbackDisposition

  init(_ message: String, disposition: AuthFeedbackDisposition = .recoverable) {
    self.message = message
    self.disposition = disposition
  }
}

enum AuthFeedback {
  static func presentation(
    for error: Error,
    context: AuthFeedbackContext
  ) -> AuthFeedbackPresentation {
    let problemCode = (error as? LiveAPIError)?.problemCode

    if isMFAContext(context), problemCode == "invalid_or_expired_challenge" {
      return AuthFeedbackPresentation(
        "Esta verificação expirou. Volte e entre novamente para iniciar uma nova.",
        disposition: .terminal
      )
    }
    if isMFAContext(context), problemCode == "mfa_rate_limited" {
      return AuthFeedbackPresentation(
        "Você fez muitas tentativas. Aguarde alguns minutos e tente novamente."
      )
    }

    switch (context, problemCode) {
    case (.signIn, "invalid_credentials"):
      return AuthFeedbackPresentation(
        "E-mail ou senha incorretos. Confira os dados e tente novamente."
      )
    case (.signIn, "login_rate_limited"):
      return AuthFeedbackPresentation(
        "Você fez muitas tentativas. Aguarde alguns minutos antes de tentar entrar novamente."
      )
    case (.signUp, "login_rate_limited"):
      return AuthFeedbackPresentation(
        "Você fez muitas tentativas. Aguarde alguns minutos antes de tentar criar a conta novamente."
      )
    case (.signUp, "email_already_registered"):
      return AuthFeedbackPresentation(
        "Este e-mail já está cadastrado. Entre com sua conta ou recupere a senha."
      )
    case (.mfaTOTP, "invalid_mfa_code"):
      return AuthFeedbackPresentation(
        "Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente."
      )
    case (.mfaRecovery, "invalid_mfa_code"):
      return AuthFeedbackPresentation(
        "Esse código de recuperação não funcionou. Confira o código e tente novamente."
      )
    case (.mfaPasskey, "invalid_passkey"):
      return AuthFeedbackPresentation(
        "Não foi possível verificar sua chave de acesso. Tente novamente ou use outro método."
      )
    case (.totpEnrollment, "invalid_totp_code"):
      return AuthFeedbackPresentation(
        "Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente."
      )
    default:
      return AuthFeedbackPresentation(fallback(for: context))
    }
  }

  static func fallback(for context: AuthFeedbackContext) -> String {
    switch context {
    case .signIn:
      "Não foi possível entrar. Tente novamente."
    case .signUp:
      "Não foi possível criar sua conta. Tente novamente."
    case .mfaTOTP:
      "Não foi possível verificar o código. Tente novamente."
    case .mfaRecovery:
      "Não foi possível verificar o código de recuperação. Tente novamente."
    case .mfaPasskey:
      "Não foi possível verificar sua chave de acesso. Tente novamente ou use outro método."
    case .totpEnrollment:
      "Não foi possível confirmar o código. Tente novamente."
    }
  }

  private static func isMFAContext(_ context: AuthFeedbackContext) -> Bool {
    switch context {
    case .mfaTOTP, .mfaRecovery, .mfaPasskey: true
    case .signIn, .signUp, .totpEnrollment: false
    }
  }
}
