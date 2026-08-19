import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func brazilianYearNeverUsesGroupingSeparators() {
  let formatted = BrazilianLocaleFormatting.year(2026)

  #expect(formatted == "2026")
  #expect(!formatted.contains("."))
  #expect(!formatted.contains(","))
}

@Test func brazilianIntegerUsesGroupingSeparators() {
  #expect(BrazilianLocaleFormatting.integer(10_000) == "10.000")
}

@Test func everyReferenceMonthHasSentenceStandaloneAndDocumentPresentations() {
  let expected = [
    "janeiro", "fevereiro", "março", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
  ]

  for (index, monthName) in expected.enumerated() {
    let month = ReferenceMonth(year: 2026, month: index + 1)
    let standaloneMonth = String(monthName.prefix(1)).uppercased(
      with: BrazilianLocaleFormatting.locale)
      + monthName.dropFirst()

    #expect(month.displayFormatted == "\(monthName) de 2026")
    #expect(month.standaloneDisplayFormatted == "\(standaloneMonth) de 2026")
    #expect(month.standaloneMonthName == standaloneMonth)
    #expect(month.documentDisplayFormatted == "\(monthName) 2026")
    #expect(!month.standaloneDisplayFormatted.contains(" De "))
  }
}

@Test func augustAndMarchKeepCorrectPortugueseCasingAndAccent() {
  let august = ReferenceMonth(year: 2026, month: 8)
  #expect(august.displayFormatted == "agosto de 2026")
  #expect(august.standaloneDisplayFormatted == "Agosto de 2026")
  #expect(august.documentDisplayFormatted == "agosto 2026")

  let march = ReferenceMonth(year: 2026, month: 3)
  #expect(march.displayFormatted == "março de 2026")
  #expect(march.standaloneDisplayFormatted == "Março de 2026")
}

@Test func dateOnlyUsesBrazilianNumericOrder() {
  #expect(DateOnly(year: 2026, month: 8, day: 10).displayFormatted == "10/08/2026")
}

@Test func dateFormattingUsesTheExplicitSaoPauloDayNearUTCMidnight() throws {
  let date = try #require(ISO8601DateFormatter().date(from: "2026-08-10T01:30:00Z"))
  let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))

  #expect(
    date.formattedPTBR(date: .numeric, time: .omitted, timeZone: saoPaulo)
      == "09/08/2026"
  )
}

@Test func fileSizesUseTheExplicitBrazilianPresentation() {
  #expect(BrazilianLocaleFormatting.fileSize(0) == "0 byte")
  #expect(BrazilianLocaleFormatting.fileSize(512_000) == "512 kB")
  #expect(BrazilianLocaleFormatting.fileSize(1_500_000) == "1,5 MB")
}

@Test func brazilianCountsUseGroupedNumbersAndOnlyOneIsSingular() {
  #expect(ptBRCount(0, singular: "arquivo", plural: "arquivos") == "0 arquivos")
  #expect(ptBRCount(1, singular: "arquivo", plural: "arquivos") == "1 arquivo")
  #expect(ptBRCount(2, singular: "arquivo", plural: "arquivos") == "2 arquivos")
  #expect(ptBRCount(1_000, singular: "arquivo", plural: "arquivos") == "1.000 arquivos")
}

@Test func sharedMoneyPresentationKeepsExactBRLSpacingAndCentavos() {
  #expect(Money(centavos: 350).formatted() == "R$\u{00A0}3,50")
  #expect(Money(centavos: 120_000).formatted() == "R$\u{00A0}1.200,00")
  #expect(Money.zero.formatted() == "R$\u{00A0}0,00")
  #expect(Money(centavos: -350).formatted() == "-R$\u{00A0}3,50")
}
