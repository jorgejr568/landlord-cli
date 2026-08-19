import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func moneyAddsCentavosWithoutFloatingPoint() {
  #expect(Money(centavos: 180_000) + Money(centavos: 65_000) == Money(centavos: 245_000))
}

@Test func moneySubtractsCentavosWithoutFloatingPoint() {
  #expect(Money(centavos: 180_000) - Money(centavos: 65_000) == Money(centavos: 115_000))
}

@Test func moneyFormatsBrazilianCurrency() {
  #expect(Money(centavos: 245_000).formatted(locale: Locale(identifier: "pt_BR")) == "R$ 2.450,00")
  #expect(Money(centavos: 350).formatted() == "R$\u{00A0}3,50")
  #expect(Money(centavos: 120_000).formatted() == "R$\u{00A0}1.200,00")
}

// The separator between "R$" and the digits is a non-breaking space (U+00A0), written as an escape
// here so a reformat or a copy-paste cannot silently turn it into a plain space. These pin the two
// amounts the balance rows actually reach: a settled billing (zero) and a credit (negative).
@Test func moneyFormatsZeroWithTheCurrencyPrefix() {
  #expect(Money.zero.formatted() == "R$\u{00A0}0,00")
}

@Test func moneyFormatsNegativeAmountsWithTheSignBeforeTheCurrency() {
  #expect(Money(centavos: -1).formatted() == "-R$\u{00A0}0,01")
  #expect(Money(centavos: -123_456).formatted() == "-R$\u{00A0}1.234,56")
}

@Test func moneyFormatsTheSameWithTheDefaultLocaleAsWithAnExplicitBrazilianOne() {
  #expect(Money(centavos: 245_000).formatted() == Money(centavos: 245_000).formatted(locale: Locale(identifier: "pt_BR")))
}

@Test func moneySortsByCentavos() {
  #expect(Money(centavos: -1) < .zero)
  #expect(Money.zero < Money(centavos: 1))
}

@Test func moneyInputTreatsEveryDigitAsCentavosWithoutFloatingPoint() {
  #expect(MoneyInputRules.centavos(from: "1") == 1)
  #expect(MoneyInputRules.centavos(from: "12") == 12)
  #expect(MoneyInputRules.centavos(from: "120000") == 120_000)
  #expect(MoneyInputRules.centavos(from: "R$ 1.200,00") == 120_000)
  #expect(MoneyInputRules.centavos(from: "R$ 0,1") == 1)
  #expect(MoneyInputRules.centavos(from: "") == 0)
  #expect(Money(centavos: 120_000).formatted() == "R$\u{00A0}1.200,00")
}
