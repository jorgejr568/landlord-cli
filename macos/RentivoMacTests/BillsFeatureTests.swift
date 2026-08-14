import AppKit
import Foundation
import RentivoCore
import Testing
import UniformTypeIdentifiers

@testable import Rentivo

/// Encodes a tiny real bitmap, so the re-encoding path is exercised against bytes `NSBitmapImageRep`
/// actually decodes rather than against a stub.
@MainActor
private func sampleImageData(_ type: NSBitmapImageRep.FileType) throws -> Data {
  let representation = try #require(
    NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 4,
      pixelsHigh: 4,
      bitsPerSample: 8,
      samplesPerPixel: 3,
      hasAlpha: false,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  )
  return try #require(representation.representation(using: type, properties: [:]))
}

/// Writes `data` to a uniquely named file so concurrently running tests cannot collide.
private func writeTemporaryFile(_ data: Data, named name: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("RentivoBillsTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let url = directory.appendingPathComponent(name)
  try data.write(to: url)
  return url
}

@Suite("Fatura line editing")
struct BillLineEditingTests {
  @Test("a line seeded from a recurring item keeps that item's server-issued id")
  func seededLineKeepsTheBillingItemIdentity() {
    let item = BillingItem(
      id: BillingItemID(rawValue: "01JABCDEF"),
      description: "Condomínio",
      amount: Money(centavos: 42_000),
      type: .variable,
      sortOrder: 1
    )

    let line = EditableBillLine(seededFrom: item, kind: .variable)

    // `createBill` keys `variable_amounts` by this id; a fresh UUID would silently drop the
    // amount the user typed for that variable item.
    #expect(line.id.rawValue == item.id.rawValue)
    #expect(line.description == "Condomínio")
    #expect(line.centavos == 42_000)
    #expect(line.kind == .variable)
  }

  @Test("an edited line round-trips into the domain with its own identity")
  func editedLineRoundTripsThroughTheDomain() {
    let original = BillLineItem(
      id: BillLineItemID(rawValue: "line-1"),
      description: "Aluguel",
      amount: Money(centavos: 245_000),
      kind: .fixed
    )

    var line = EditableBillLine(line: original)
    line.centavos = 250_000

    #expect(line.domain.id == original.id)
    #expect(line.domain.amount == Money(centavos: 250_000))
    #expect(line.domain.kind == .fixed)
  }

  @Test("a brand-new extra line mints its own identity")
  func newExtraLineMintsAnIdentity() {
    let first = EditableBillLine(kind: .extra)
    let second = EditableBillLine(kind: .extra)

    #expect(first.id != second.id)
    #expect(first.centavos == 0)
    #expect(first.description.isEmpty)
  }

  @Test("line kinds carry their PT-BR section and action copy")
  func lineKindCopyIsPTBR() {
    #expect(
      BillLineItemKind.allCases.map(\.sectionTitle)
        == ["Itens fixos", "Itens variáveis", "Itens extras"]
    )
    #expect(
      BillLineItemKind.allCases.map(\.actionLabel)
        == ["item fixo", "valor variável", "item extra"]
    )
  }

  @Test("the competência picker names every month in PT-BR")
  func referenceMonthNamesArePTBR() {
    let names = (1...12).map { BillReferenceMonthNames.label(year: 2026, month: $0) }

    #expect(
      names == [
        "Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro",
      ]
    )
  }
}

@Suite("Comprovante intake on macOS")
@MainActor
struct ReceiptIntakeTests {
  @Test("the importer and the drop target accept the same types as iOS")
  func acceptedTypesMatchIOS() {
    #expect(ReceiptIntake.allowedContentTypes == [UTType.pdf, UTType.image])
  }

  @Test("a drop keeps the first file and ignores anything without bytes")
  func dropKeepsTheFirstFileURL() throws {
    let remote = try #require(URL(string: "https://rentivo.com.br/comprovante.pdf"))
    let file = URL(fileURLWithPath: "/tmp/comprovante.pdf")

    #expect(ReceiptIntake.firstFileURL(in: [remote, file]) == file)
    #expect(ReceiptIntake.firstFileURL(in: [remote]) == nil)
    #expect(ReceiptIntake.firstFileURL(in: []) == nil)
  }

  @Test("an accepted format is uploaded byte-for-byte under its own name")
  func acceptedFormatPassesThroughUnchanged() throws {
    let pdf = Data("%PDF-1.4".utf8)
    let upload = FileUpload(data: pdf, filename: "fatura.pdf", mediaType: "application/pdf")

    let clamped = try #require(upload.clampedToAcceptedReceiptFormat())

    #expect(clamped == upload)
  }

  @Test("a format the server drops is re-encoded as JPEG and renamed to match")
  func unsupportedImageIsReencodedAsJPEG() throws {
    let tiff = try sampleImageData(.tiff)
    let upload = FileUpload(data: tiff, filename: "scan.tiff", mediaType: "image/tiff")

    let clamped = try #require(upload.clampedToAcceptedReceiptFormat())

    #expect(clamped.mediaType == ReceiptMediaDescriptor.jpeg.mediaType)
    #expect(clamped.filename == "scan.jpg")
    #expect(ReceiptMediaDescriptor.isAllowed(mediaType: clamped.mediaType))
    // The re-encoded bytes must still decode, or the "upload" would be a broken file.
    #expect(NSBitmapImageRep(data: clamped.data) != nil)
  }

  @Test("a file that is neither an accepted format nor an image is refused")
  func undecodableBytesAreRefused() {
    let upload = FileUpload(
      data: Data("nem imagem nem PDF".utf8),
      filename: "notas.bin",
      mediaType: "application/octet-stream"
    )

    #expect(upload.clampedToAcceptedReceiptFormat() == nil)
  }

  @Test("a file whose name carries no usable stem falls back to a generated one")
  func namelessFileGetsAGeneratedName() throws {
    let tiff = try sampleImageData(.tiff)
    let upload = FileUpload(data: tiff, filename: ".tiff", mediaType: "image/tiff")

    let clamped = try #require(upload.clampedToAcceptedReceiptFormat())

    #expect(clamped.filename.hasPrefix("comprovante-"))
    #expect(clamped.filename.hasSuffix(".jpg"))
  }

  @Test("reading a picked PNG produces an upload the server accepts as it is")
  func readingAPickedPNGKeepsItsBytes() async throws {
    let png = try sampleImageData(.png)
    let url = try writeTemporaryFile(png, named: "comprovante.png")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let upload = try #require(try await ReceiptIntake.upload(from: url))

    #expect(upload.filename == "comprovante.png")
    #expect(upload.mediaType == "image/png")
    #expect(upload.data == png)
    #expect(upload.byteCount == png.count)
  }

  @Test("reading a dropped TIFF clamps it before it reaches the upload")
  func readingADroppedTIFFClampsIt() async throws {
    let tiff = try sampleImageData(.tiff)
    let url = try writeTemporaryFile(tiff, named: "recibo.tiff")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let upload = try #require(try await ReceiptIntake.upload(from: url))

    #expect(upload.filename == "recibo.jpg")
    #expect(upload.mediaType == ReceiptMediaDescriptor.jpeg.mediaType)
  }

  @Test("a file that is neither an accepted format nor an image is refused on read too")
  func readingAnUndecodableFileYieldsNoUpload() async throws {
    let url = try writeTemporaryFile(Data("nem imagem nem PDF".utf8), named: "notas.txt")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let upload = try await ReceiptIntake.upload(from: url)

    #expect(upload == nil)
  }

  @Test("the size gate matches the server's 10 MB receipt limit")
  func uploadLimitMatchesTheServer() {
    #expect(ReceiptUploadLimit.label == "10 MB")
    #expect(!ReceiptUploadLimit.exceedsLimit(byteCount: ReceiptUploadLimit.maxByteCount))
    #expect(ReceiptUploadLimit.exceedsLimit(byteCount: ReceiptUploadLimit.maxByteCount + 1))
  }

  @Test("a format uploaded as it is meets the server limit before it is read")
  func theEarlyGateMatchesTheServerLimitForPassthroughFormats() {
    for mediaType in ReceiptMediaDescriptor.allowedMediaTypes {
      #expect(
        !ReceiptIntake.exceedsLimitBeforeReading(
          declaredByteCount: ReceiptUploadLimit.maxByteCount, mediaType: mediaType))
      #expect(
        ReceiptIntake.exceedsLimitBeforeReading(
          declaredByteCount: ReceiptUploadLimit.maxByteCount + 1, mediaType: mediaType))
      #expect(
        !ReceiptIntake.exceedsLimitBeforeReading(declaredByteCount: 0, mediaType: mediaType))
    }
  }

  @Test("a format that will be transcoded is judged by the read ceiling, not the server limit")
  func theEarlyGateLetsTranscodableFormatsThrough() {
    // The case the clamp exists for: a 14 MB TIFF scan uploads as a JPEG of about 1 MB, so the
    // server's limit says nothing about its weight on disk and must not refuse it here.
    #expect(
      !ReceiptIntake.exceedsLimitBeforeReading(
        declaredByteCount: 14 * 1024 * 1024, mediaType: "image/tiff"))
    #expect(
      !ReceiptIntake.exceedsLimitBeforeReading(
        declaredByteCount: ReceiptIntake.transcodeReadCeiling, mediaType: "image/heic"))
    // Past the ceiling the file is no longer worth paging into memory to find out.
    #expect(
      ReceiptIntake.exceedsLimitBeforeReading(
        declaredByteCount: ReceiptIntake.transcodeReadCeiling + 1, mediaType: "image/heic"))
    #expect(ReceiptIntake.transcodeReadCeiling > ReceiptUploadLimit.maxByteCount)
  }

  @Test("a size the filesystem will not report is never treated as a rejection")
  func anUnknownSizePassesTheEarlyGate() {
    // Silence has to mean "read it and judge the bytes", not "refuse it": a URL whose attributes
    // are unreadable is still very often a perfectly good receipt.
    #expect(
      !ReceiptIntake.exceedsLimitBeforeReading(declaredByteCount: nil, mediaType: "image/png"))
    #expect(
      !ReceiptIntake.exceedsLimitBeforeReading(declaredByteCount: nil, mediaType: "image/tiff"))
  }

  @Test("the gate reads a file's type the same way the upload itself will")
  func theEarlyGateTypesFilesLikeTheRead() throws {
    #expect(
      ReceiptIntake.mediaType(of: URL(fileURLWithPath: "/tmp/fatura.pdf")) == "application/pdf")
    #expect(ReceiptIntake.mediaType(of: URL(fileURLWithPath: "/tmp/scan.tiff")) == "image/tiff")
    // An extension nothing claims still has to produce a type, and it must not be an accepted one:
    // unknown bytes belong on the transcode path, where the decoder decides.
    let unknown = ReceiptIntake.mediaType(of: URL(fileURLWithPath: "/tmp/notas.rentivo"))
    #expect(unknown == "application/octet-stream")
    #expect(!ReceiptMediaDescriptor.isAllowed(mediaType: unknown))
  }

  @Test("the declared size is the file's own, and unreadable URLs report nothing")
  func declaredSizeComesFromTheFilesystem() throws {
    let png = try sampleImageData(.png)
    let url = try writeTemporaryFile(png, named: "comprovante.png")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    #expect(ReceiptIntake.declaredByteCount(of: url) == png.count)
    #expect(
      ReceiptIntake.declaredByteCount(
        of: url.deletingLastPathComponent().appendingPathComponent("ausente.png")) == nil)
  }

  @Test("an oversize receipt is refused with the PT-BR limit message")
  func anOversizeReceiptIsRefusedBeforeItIsRead() async throws {
    let oversize = Data(count: ReceiptUploadLimit.maxByteCount + 1)
    let url = try writeTemporaryFile(oversize, named: "video.png")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    await #expect(throws: ReceiptIntakeError.exceedsSizeLimit) {
      _ = try await ReceiptIntake.upload(from: url)
    }
    // The screens show this sentence verbatim, and it must keep naming the same limit the gate
    // enforces.
    #expect(
      ReceiptIntakeError.exceedsSizeLimit.message
        == "O comprovante excede o limite de \(ReceiptUploadLimit.label).")
  }

  @Test("a large scan in a transcodable format is read rather than refused unseen")
  func anOversizeTranscodableFileStillReachesTheDecoder() async throws {
    let oversize = Data(count: ReceiptUploadLimit.maxByteCount + 1)
    let url = try writeTemporaryFile(oversize, named: "scan.tiff")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    // The same weight that gets a PNG refused before the read gets a TIFF read, because the JPEG
    // it becomes is what the limit is actually about. These particular bytes are not a decodable
    // image, so the read ends in `nil` — but it ends *after* the gate, which is the point.
    let upload = try await ReceiptIntake.upload(from: url)

    #expect(upload == nil)
  }

  @Test("an arquivo is read as it is, with no clamping and no receipt size rule")
  func rawUploadKeepsTheBytesItWasGiven() async throws {
    let tiff = try sampleImageData(.tiff)
    let url = try writeTemporaryFile(tiff, named: "planta.tiff")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let upload = try await ReceiptIntake.rawUpload(from: url)

    // Attachments are stored exactly as uploaded, so the TIFF that a comprovante would have been
    // re-encoded into JPEG stays a TIFF here.
    #expect(upload.filename == "planta.tiff")
    #expect(upload.mediaType == "image/tiff")
    #expect(upload.data == tiff)
  }
}

@Suite("Downloaded file export")
struct DownloadedFileExportTests {
  private func file(filename: String, mediaType: String) -> DownloadedFile {
    DownloadedFile(
      fileURL: URL(fileURLWithPath: "/tmp/\(filename)"),
      filename: filename,
      mediaType: mediaType
    )
  }

  @Test("the save panel is typed from the media type the server declared")
  func contentTypeComesFromTheMediaType() {
    #expect(
      DownloadedFileExport.contentType(for: file(filename: "fatura.pdf", mediaType: "application/pdf"))
        == .pdf
    )
  }

  @Test("a missing media type falls back to what the filename claims")
  func contentTypeFallsBackToTheFilename() {
    #expect(
      DownloadedFileExport.contentType(for: file(filename: "fatura.pdf", mediaType: "")) == .pdf
    )
  }

  @Test("an unidentifiable file is still saveable as plain data")
  func contentTypeFallsBackToData() {
    #expect(DownloadedFileExport.contentType(for: file(filename: "arquivo", mediaType: "")) == .data)
  }

  @Test("the save panel is seeded with the stem, so the extension is not doubled")
  func defaultFilenameDropsTheExtension() {
    #expect(
      DownloadedFileExport.defaultFilename(for: file(filename: "recibo-2026.pdf", mediaType: "application/pdf"))
        == "recibo-2026"
    )
    #expect(
      DownloadedFileExport.defaultFilename(for: file(filename: "recibo", mediaType: "application/pdf"))
        == "recibo"
    )
  }
}
