import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

@Test func invoiceAndGeneratedReceiptUseBillingAndCompetenceNames() {
  let referenceMonth = ReferenceMonth(year: 2026, month: 8)

  let invoice = DocumentPresentation.invoice(
    billingName: "Apartamento 202", referenceMonth: referenceMonth)
  #expect(invoice.displayName == "Fatura - Apartamento 202 - agosto 2026")
  #expect(invoice.suggestedFilename == "Fatura - Apartamento 202 - agosto 2026.pdf")

  let receipt = DocumentPresentation.generatedReceipt(
    billingName: "Apartamento 202", referenceMonth: referenceMonth)
  #expect(receipt.displayName == "Recibo - Apartamento 202 - agosto 2026")
  #expect(receipt.suggestedFilename == "Recibo - Apartamento 202 - agosto 2026.pdf")
}

@Test(arguments: [
  (" Contrato de locação ", "contrato-servidor.pdf", "Contrato de locação"),
  ("  ", " contrato-servidor.pdf ", "contrato-servidor.pdf"),
  ("\n", "\t", "Arquivo"),
])
func attachmentDisplayNameUsesNameThenFilenameThenFallback(
  name: String, filename: String, expected: String
) {
  let presentation = DocumentPresentation.attachment(
    name: name, filename: filename, mediaType: "application/pdf")

  #expect(presentation.displayName == expected)
}

@Test func uploadedReceiptUsesServerFilenameOrContextualFallback() {
  let referenceMonth = ReferenceMonth(year: 2026, month: 8)

  let serverNamed = DocumentPresentation.uploadedReceipt(
    filename: " comprovante-pix.pdf ",
    billingName: "Apartamento 202",
    referenceMonth: referenceMonth,
    mediaType: "application/pdf"
  )
  #expect(serverNamed.displayName == "comprovante-pix")
  #expect(serverNamed.suggestedFilename == "comprovante-pix.pdf")

  let fallback = DocumentPresentation.uploadedReceipt(
    filename: "  ",
    billingName: "Apartamento 202",
    referenceMonth: referenceMonth,
    mediaType: "image/jpeg"
  )
  #expect(fallback.displayName == "Comprovante - Apartamento 202 - agosto 2026")
  #expect(fallback.suggestedFilename == "Comprovante - Apartamento 202 - agosto 2026.jpg")
}

@Test func serverIdentifierRemainsAnExplicitLastResortDownloadFallback() {
  let presentation = DocumentPresentation.serverFallback(
    serverName: "01J8Y8P3BK4P8K5V7G6A9N2Q1R",
    mediaType: "application/pdf"
  )

  #expect(presentation.displayName == "01J8Y8P3BK4P8K5V7G6A9N2Q1R")
  #expect(presentation.suggestedFilename == "01J8Y8P3BK4P8K5V7G6A9N2Q1R.pdf")
}

@Test(arguments: [
  ("arquivo", "application/pdf", "arquivo.pdf"),
  ("foto", "image/jpeg", "foto.jpg"),
  ("imagem", "image/png", "imagem.png"),
  ("dados", "text/csv", "dados.csv"),
  ("planilha", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "planilha.xlsx"),
  ("contrato.txt", "application/pdf", "contrato.pdf"),
])
func resolvedShareFilenameUsesTheResponseMediaType(
  filename: String, mediaType: String, expected: String
) {
  #expect(
    DocumentPresentation.resolvedFilename(filename, mediaType: mediaType) == expected
  )
}

@Test func filesystemFilenameIsSanitizedWithoutChangingTheVisibleName() {
  let presentation = DocumentPresentation(
    displayName: "Contrato / Loja: \"A\"\n2026",
    suggestedFilename: "Contrato / Loja: \"A\"\r\n2026.pdf"
  )

  #expect(presentation.displayName == "Contrato / Loja: \"A\"\n2026")
  #expect(presentation.sanitizedFilename == "Contrato  Loja A2026.pdf")
  #expect(DocumentPresentation.sanitizedFilename("/\r\n:\"\u{0007}") == "arquivo")
}

@Test func filesystemFilenameFitsAFileSystemComponentWithoutDroppingItsExtension() {
  let longASCIIName = String(repeating: "a", count: 300) + ".pdf"
  let sanitizedASCIIName = DocumentPresentation.sanitizedFilename(longASCIIName)
  #expect(sanitizedASCIIName.utf8.count <= 255)
  #expect(sanitizedASCIIName.hasSuffix(".pdf"))

  let longUnicodeName = String(repeating: "locação 🏠 ", count: 40) + ".pdf"
  let sanitizedUnicodeName = DocumentPresentation.sanitizedFilename(longUnicodeName)
  #expect(sanitizedUnicodeName.utf8.count <= 255)
  #expect(sanitizedUnicodeName.hasSuffix(".pdf"))
  #expect(String(data: Data(sanitizedUnicodeName.utf8), encoding: .utf8) == sanitizedUnicodeName)
}

@Test(arguments: [
  ("application/pdf", "anything.bin", "doc.richtext.fill"),
  ("image/heic", "anything.bin", "photo.fill"),
  ("application/octet-stream", "photo.png", "photo.fill"),
  ("text/csv", "anything.bin", "tablecells.fill"),
  ("application/vnd.ms-excel", "anything.bin", "tablecells.fill"),
  ("application/octet-stream", "sheet.xlsx", "tablecells.fill"),
  ("application/octet-stream", "anything.bin", "doc.fill"),
])
func fileTypeSymbolUsesMediaTypeThenFilename(
  mediaType: String, filename: String, expected: String
) {
  #expect(DocumentPresentation.symbolName(mediaType: mediaType, filename: filename) == expected)
}

@Test func metadataLineContainsSizeAndOptionalBrazilianCreationDate() throws {
  let createdAt = try #require(ISO8601DateFormatter().date(from: "2026-08-19T12:00:00Z"))
  let saoPaulo = try #require(TimeZone(identifier: "America/Sao_Paulo"))

  #expect(DocumentPresentation.metadataLine(byteCount: 1_500_000) == "1,5 MB")
  #expect(
    DocumentPresentation.metadataLine(
      byteCount: 1_500_000, createdAt: createdAt, timeZone: saoPaulo)
      == "1,5 MB • 19/08/2026"
  )
}
