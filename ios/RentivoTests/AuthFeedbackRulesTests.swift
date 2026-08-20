import Foundation
import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Test func untouchedOrEmptyConfirmationDoesNotProduceFeedback() {
    #expect(
      SignUpConfirmationRules.errorMessage(
        password: "uma-senha",
        confirmation: "",
        isTouched: false,
        shouldValidate: false
      ) == nil
    )
    #expect(
      SignUpConfirmationRules.errorMessage(
        password: "uma-senha",
        confirmation: "",
        isTouched: true,
        shouldValidate: true
      ) == nil
    )
  }

  @Test func confirmationMismatchUsesExactCopyAndAMatchClearsIt() {
    #expect(
      SignUpConfirmationRules.errorMessage(
        password: "uma-senha",
        confirmation: "outra-senha",
        isTouched: true,
        shouldValidate: true
      ) == "As senhas não coincidem."
    )
    #expect(
      SignUpConfirmationRules.errorMessage(
        password: "uma-senha",
        confirmation: "uma-senha",
        isTouched: true,
        shouldValidate: true
      ) == nil
    )
  }

  @Test func totpNormalizationAcceptsOnlyTheFirstSixASCIIDigits() {
    #expect(TOTPCodeRules.normalize("123456") == "123456")
    #expect(TOTPCodeRules.normalize("123 456") == "123456")
    #expect(TOTPCodeRules.normalize("a1-b2.c3 d4/e5:f6z7") == "123456")
    #expect(TOTPCodeRules.normalize("１２３٤٥٦") == "")
    #expect(TOTPCodeRules.normalize("123456789") == "123456")
  }

  @Test func totpAutoSubmitOnlyOccursOnANewIdleTransitionToSixDigits() {
    #expect(
      TOTPCodeRules.shouldAutoSubmit(
        previousValue: "12345", currentValue: "123456", isBusy: false,
        lastSubmittedValue: nil
      )
    )
    #expect(
      !TOTPCodeRules.shouldAutoSubmit(
        previousValue: "123456", currentValue: "123456", isBusy: false,
        lastSubmittedValue: nil
      )
    )
    #expect(
      !TOTPCodeRules.shouldAutoSubmit(
        previousValue: "12345", currentValue: "123456", isBusy: true,
        lastSubmittedValue: nil
      )
    )
    #expect(
      !TOTPCodeRules.shouldAutoSubmit(
        previousValue: "12345", currentValue: "123456", isBusy: false,
        lastSubmittedValue: "123456"
      )
    )
  }

  @Test func knownAuthenticationProblemCodesUseContextualCopyAndTerminality() {
    let cases: [(AuthFeedbackContext, String, String, AuthFeedbackDisposition)] = [
      (
        .signIn, "invalid_credentials",
        "E-mail ou senha incorretos. Confira os dados e tente novamente.", .recoverable
      ),
      (
        .signIn, "login_rate_limited",
        "Você fez muitas tentativas. Aguarde alguns minutos antes de tentar entrar novamente.",
        .recoverable
      ),
      (
        .signUp, "login_rate_limited",
        "Você fez muitas tentativas. Aguarde alguns minutos antes de tentar criar a conta novamente.",
        .recoverable
      ),
      (
        .signUp, "email_already_registered",
        "Este e-mail já está cadastrado. Entre com sua conta ou recupere a senha.", .recoverable
      ),
      (
        .mfaTOTP, "invalid_mfa_code",
        "Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente.",
        .recoverable
      ),
      (
        .mfaRecovery, "invalid_mfa_code",
        "Esse código de recuperação não funcionou. Confira o código e tente novamente.", .recoverable
      ),
      (
        .mfaPasskey, "invalid_passkey",
        "Não foi possível verificar sua chave de acesso. Tente novamente ou use outro método.",
        .recoverable
      ),
      (
        .totpEnrollment, "invalid_totp_code",
        "Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente.",
        .recoverable
      ),
    ]

    for (context, code, message, disposition) in cases {
      let feedback = AuthFeedback.presentation(
        for: LiveAPIError.server(message: "Detalhe técnico", statusCode: 400, code: code),
        context: context
      )
      #expect(feedback.message == message)
      #expect(feedback.disposition == disposition)
    }

    for context in [
      AuthFeedbackContext.mfaTOTP, .mfaRecovery, .mfaPasskey,
    ] {
      let limited = AuthFeedback.presentation(
        for: LiveAPIError.server(
          message: "Detalhe técnico", statusCode: 429, code: "mfa_rate_limited"),
        context: context
      )
      #expect(
        limited.message
          == "Você fez muitas tentativas. Aguarde alguns minutos e tente novamente."
      )
      #expect(limited.disposition == .recoverable)

      let expired = AuthFeedback.presentation(
        for: LiveAPIError.server(
          message: "Desafio de autenticação inválido ou expirado.", statusCode: 401,
          code: "invalid_or_expired_challenge"),
        context: context
      )
      #expect(
        expired.message
          == "Esta verificação expirou. Volte e entre novamente para iniciar uma nova."
      )
      #expect(expired.disposition == .terminal)
    }
  }

  @Test func unknownAndUncodedErrorsUseEveryContextualFallbackWithoutLeakingDetail() {
    let expected: [AuthFeedbackContext: String] = [
      .signIn: "Não foi possível entrar. Tente novamente.",
      .signUp: "Não foi possível criar sua conta. Tente novamente.",
      .mfaTOTP: "Não foi possível verificar o código. Tente novamente.",
      .mfaRecovery: "Não foi possível verificar o código de recuperação. Tente novamente.",
      .mfaPasskey:
        "Não foi possível verificar sua chave de acesso. Tente novamente ou use outro método.",
      .totpEnrollment: "Não foi possível confirmar o código. Tente novamente.",
    ]

    for context in AuthFeedbackContext.allCases {
      for error in [
        LiveAPIError.server(
          message: "RAW DETAIL MUST NOT LEAK", statusCode: 500, code: "unknown_code"),
        LiveAPIError.server(message: "RAW DETAIL MUST NOT LEAK", statusCode: 500),
        LiveAPIError.invalidResponse,
      ] {
        let feedback = AuthFeedback.presentation(for: error, context: context)
        #expect(feedback.message == expected[context])
        #expect(!feedback.message.contains("RAW DETAIL"))
        #expect(feedback.disposition == .recoverable)
      }
    }
  }
#endif
