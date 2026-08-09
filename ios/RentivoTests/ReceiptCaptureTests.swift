import Foundation
import Testing
import UniformTypeIdentifiers

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - `ReceiptMediaDescriptor.inferred(from:)`

@Test func receiptMediaDescriptorUsesTheFirstUsableContentType() {
  #expect(ReceiptMediaDescriptor.inferred(from: [.png, .jpeg]).mediaType == "image/png")
  #expect(ReceiptMediaDescriptor.inferred(from: [.png, .jpeg]).filenameExtension == "png")
  #expect(ReceiptMediaDescriptor.inferred(from: [.heic]).mediaType == "image/heic")
  #expect(ReceiptMediaDescriptor.inferred(from: [.pdf]).filenameExtension == "pdf")
}

@Test func receiptMediaDescriptorSkipsContentTypesWithoutAMediaTypeOrExtension() {
  let descriptor = ReceiptMediaDescriptor.inferred(from: [.item, .png])

  #expect(descriptor == ReceiptMediaDescriptor(mediaType: "image/png", filenameExtension: "png"))
}

@Test func receiptMediaDescriptorFallsBackToJPEGWithoutAUsableContentType() {
  #expect(ReceiptMediaDescriptor.inferred(from: []) == .jpeg)
  #expect(ReceiptMediaDescriptor.jpeg.mediaType == "image/jpeg")
  #expect(ReceiptMediaDescriptor.jpeg.filenameExtension == "jpg")
}

// MARK: - `ReceiptFilename.captured(at:filenameExtension:timeZone:)`

@Test func capturedReceiptFilenameStampsTheCaptureInstant() {
  var components = DateComponents()
  components.year = 2026
  components.month = 8
  components.day = 9
  components.hour = 14
  components.minute = 30
  components.second = 5
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  let date = calendar.date(from: components)!

  let filename = ReceiptFilename.captured(at: date, timeZone: TimeZone(identifier: "UTC")!)

  #expect(filename == "comprovante-20260809-143005.jpg")
}

@Test func capturedReceiptFilenameHonorsTheRequestedExtensionAndTimeZone() {
  let date = Date(timeIntervalSince1970: 0)

  let utc = ReceiptFilename.captured(
    at: date, filenameExtension: "png", timeZone: TimeZone(identifier: "UTC")!)
  let saoPaulo = ReceiptFilename.captured(
    at: date, filenameExtension: "png", timeZone: TimeZone(identifier: "America/Sao_Paulo")!)

  #expect(utc == "comprovante-19700101-000000.png")
  #expect(saoPaulo == "comprovante-19691231-210000.png")
}
