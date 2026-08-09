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

// MARK: - Server-accepted media types

@Test func allowedReceiptMediaTypesMatchTheServerContract() {
  #expect(
    ReceiptMediaDescriptor.allowedMediaTypes == ["application/pdf", "image/jpeg", "image/png"])
  for mediaType in ReceiptMediaDescriptor.allowedMediaTypes {
    #expect(ReceiptMediaDescriptor.isAllowed(mediaType: mediaType))
  }
  #expect(ReceiptMediaDescriptor.isAllowed(mediaType: "IMAGE/JPEG"))
  #expect(!ReceiptMediaDescriptor.isAllowed(mediaType: "image/heic"))
  #expect(!ReceiptMediaDescriptor.isAllowed(mediaType: "application/octet-stream"))
}

@Test func onlyJPEGAndPNGLibraryPhotosSkipReencoding() {
  #expect(!ReceiptMediaDescriptor.requiresReencoding(mediaType: "image/jpeg"))
  #expect(!ReceiptMediaDescriptor.requiresReencoding(mediaType: "image/png"))
  #expect(!ReceiptMediaDescriptor.requiresReencoding(mediaType: "IMAGE/PNG"))
  #expect(ReceiptMediaDescriptor.requiresReencoding(mediaType: "image/heic"))
  #expect(ReceiptMediaDescriptor.requiresReencoding(mediaType: "image/heif"))
  #expect(ReceiptMediaDescriptor.requiresReencoding(mediaType: "image/tiff"))
  // The camera path already produces JPEG, and the library never hands back a PDF.
  #expect(ReceiptMediaDescriptor.requiresReencoding(mediaType: "application/pdf"))
}

@Test func heicPickedFromTheLibraryRequiresReencoding() {
  let descriptor = ReceiptMediaDescriptor.inferred(from: [.heic])

  #expect(!ReceiptMediaDescriptor.isAllowed(mediaType: descriptor.mediaType))
  #expect(ReceiptMediaDescriptor.requiresReencoding(mediaType: descriptor.mediaType))
}

// MARK: - `ReceiptUploadLimit`

@Test func receiptUploadLimitMirrorsTheServerCap() {
  #expect(ReceiptUploadLimit.maxByteCount == 10 * 1024 * 1024)
  #expect(ReceiptUploadLimit.label == "10 MB")
  #expect(!ReceiptUploadLimit.exceedsLimit(byteCount: 0))
  #expect(!ReceiptUploadLimit.exceedsLimit(byteCount: ReceiptUploadLimit.maxByteCount - 1))
  #expect(!ReceiptUploadLimit.exceedsLimit(byteCount: ReceiptUploadLimit.maxByteCount))
  #expect(ReceiptUploadLimit.exceedsLimit(byteCount: ReceiptUploadLimit.maxByteCount + 1))
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

// MARK: - `ReceiptFilename.reencoded(from:filenameExtension:at:timeZone:)`

@Test func reencodedReceiptFilenameKeepsTheStemAndSwapsTheExtension() {
  #expect(ReceiptFilename.reencoded(from: "recibo-agosto.heic") == "recibo-agosto.jpg")
  #expect(ReceiptFilename.reencoded(from: "scan.v2.tiff") == "scan.v2.jpg")
  #expect(ReceiptFilename.reencoded(from: "sem-extensao") == "sem-extensao.jpg")
  #expect(
    ReceiptFilename.reencoded(from: "recibo.heic", filenameExtension: "png") == "recibo.png")
}

@Test func reencodedReceiptFilenameFallsBackToAGeneratedNameWithoutAUsableStem() {
  let date = Date(timeIntervalSince1970: 0)
  let utc = TimeZone(identifier: "UTC")!

  #expect(
    ReceiptFilename.reencoded(from: "", at: date, timeZone: utc)
      == "comprovante-19700101-000000.jpg")
  #expect(
    ReceiptFilename.reencoded(from: ".heic", at: date, timeZone: utc)
      == "comprovante-19700101-000000.jpg")
}
