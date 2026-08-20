import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Suite struct HomePresentationRulesTests {
    @Test func noBillingsAlwaysSelectsOnboardingEvenWhenSummaryContainsValues() {
      #expect(HomePresentationRules.mode(hasBillings: false) == .onboarding)
    }

    @Test func billingsSelectPopulatedDashboardEvenWhenEveryAmountIsZero() {
      #expect(HomePresentationRules.mode(hasBillings: true) == .populated)
    }

    @Test(arguments: [-100, 0])
    func nonPositiveOverdueUsesNeutralSemantics(centavos: Int) {
      #expect(HomePresentationRules.overduePresentation(centavos: centavos) == .neutral)
    }

    @Test func positiveOverdueUsesWarningSemantics() {
      #expect(HomePresentationRules.overduePresentation(centavos: 1) == .warning)
    }
  }
#endif
