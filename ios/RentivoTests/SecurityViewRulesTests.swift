import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Test func securitySummaryFailureWithTheMFASetupRequiredCodeRoutesToSetupOnly() {
    #expect(SecurityViewRules.isMFASetupRequiredFailure(problemCode: "mfa_setup_required"))
  }

  @Test func otherProblemCodesFallThroughToTheGenericFailureScreen() {
    // Any other 403 (e.g. a plain permission error) — or one with no machine-readable code at
    // all — must still hit `PageStateView`'s normal retry screen, not the setup-only view: that
    // view offers exactly one action (start TOTP enrollment), which is wrong for a failure TOTP
    // setup cannot fix.
    #expect(!SecurityViewRules.isMFASetupRequiredFailure(problemCode: "permission_denied"))
    #expect(!SecurityViewRules.isMFASetupRequiredFailure(problemCode: nil))
  }

  @Test func invalidAuthenticatorEnrollmentCodeUsesFriendlyCopy() {
    let error = LiveAPIError.server(
      message: "Código TOTP inválido",
      statusCode: 400,
      code: "invalid_totp_code"
    )

    #expect(
      SecurityViewRules.authenticatorEnrollmentErrorMessage(for: error)
        == "Esse código não funcionou. Confira os 6 dígitos no aplicativo autenticador e tente novamente."
    )
  }

  @Test func unknownAuthenticatorEnrollmentFailureUsesContextualFallback() {
    let error = LiveAPIError.server(
      message: "Internal detail that must not be displayed",
      statusCode: 500,
      code: "unexpected"
    )

    #expect(
      SecurityViewRules.authenticatorEnrollmentErrorMessage(for: error)
        == "Não foi possível confirmar o código. Tente novamente."
    )
  }
#endif
