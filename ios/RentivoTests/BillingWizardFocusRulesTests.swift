import Testing

#if canImport(Rentivo)
  @testable import Rentivo

  @Test func billingWizardPIXFocusTargetsTheFirstInvalidField() {
    #expect(BillingWizardFocusRules.pixTarget(key: "", merchantName: "", merchantCity: "") == .key)
    #expect(BillingWizardFocusRules.pixTarget(key: "chave", merchantName: "", merchantCity: "RECIFE") == .merchantName)
    #expect(BillingWizardFocusRules.pixTarget(key: "chave", merchantName: "ANA", merchantCity: "") == .merchantCity)
    #expect(
      BillingWizardFocusRules.pixTarget(
        key: "chave",
        merchantName: String(repeating: "A", count: 26),
        merchantCity: "RECIFE"
      ) == .merchantName
    )
    #expect(
      BillingWizardFocusRules.pixTarget(
        key: "chave",
        merchantName: "ANA",
        merchantCity: String(repeating: "R", count: 16)
      ) == .merchantCity
    )
  }

  @Test func billingWizardContactFocusPrioritizesInvalidNames() {
    #expect(BillingWizardFocusRules.contactTarget(name: "", email: "ana@example.com") == .name)
    #expect(
      BillingWizardFocusRules.contactTarget(
        name: String(repeating: "A", count: 256),
        email: "ana@example.com"
      ) == .name
    )
    #expect(BillingWizardFocusRules.contactTarget(name: "Ana", email: "invalido") == .email)
  }

  @Test func billingWizardFixedOverflowFocusesTheFirstFixedLineThatExceedsTheBound() {
    let maximum = Money.maximumPersistedCentavos
    let items: [BillingWizardFocusRules.ItemAmount] = [
      .init(type: .fixed, centavos: maximum - 100),
      .init(type: .variable, centavos: maximum),
      .init(type: .fixed, centavos: 101),
      .init(type: .fixed, centavos: 0),
    ]

    #expect(BillingWizardFocusRules.firstFixedOverflowIndex(in: items) == 2)
  }

  @Test func emptyBillingItemsFocusTheStableAddItemControl() {
    #expect(
      BillingWizardFocusRules.itemTarget(
        issues: [ValidationIssue(field: .items, message: "Adicione ao menos um item recorrente.")],
        items: []
      ) == .addItem
    )
  }
#endif
