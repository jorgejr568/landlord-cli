import Foundation
import Testing

#if canImport(RentivoCore)
  @testable import RentivoCore
#else
  @testable import Rentivo
#endif

// MARK: - `FileUpload.from(url:)`

@Test func fileUploadFromURLReadsDataAndInfersMediaTypeFromAKnownExtension() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let fileURL = directory.appendingPathComponent("recibo.pdf")
  let contents = Data("%PDF-1.4 conteudo simulado".utf8)
  try contents.write(to: fileURL)

  let upload = try FileUpload.from(url: fileURL)

  #expect(upload.filename == "recibo.pdf")
  #expect(upload.mediaType == "application/pdf")
  #expect(upload.data == contents)
  #expect(upload.byteCount == contents.count)
}

@Test func fileUploadFromSecurityScopedURLReadsOffTheCallingActor() async throws {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("pdf")
  let contents = Data("%PDF async".utf8)
  try contents.write(to: fileURL)
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let upload = try await FileUpload.fromSecurityScoped(url: fileURL, policy: .rentivoDocument)

  #expect(upload.data == contents)
}

@Test func fileUploadFromURLInfersImageMediaTypesFromKnownExtensions() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let jpegURL = directory.appendingPathComponent("comprovante.jpg")
  try Data([0xFF, 0xD8, 0xFF]).write(to: jpegURL)
  let pngURL = directory.appendingPathComponent("comprovante.png")
  try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngURL)

  #expect(try FileUpload.from(url: jpegURL).mediaType == "image/jpeg")
  #expect(try FileUpload.from(url: pngURL).mediaType == "image/png")
}

@Test func fileUploadFromURLDefaultsToOctetStreamForAnUnknownExtension() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }

  let fileURL = directory.appendingPathComponent("dados.rentivobinario")
  try Data("bytes quaisquer".utf8).write(to: fileURL)

  let upload = try FileUpload.from(url: fileURL)

  #expect(upload.mediaType == "application/octet-stream")
  #expect(upload.filename == "dados.rentivobinario")
}

@Test func fileUploadFromURLThrowsWhenTheFileDoesNotExist() {
  let missingURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
    .appendingPathExtension("pdf")

  #expect(throws: (any Error).self) {
    _ = try FileUpload.from(url: missingURL)
  }
}

@Test func attachmentUploadRulesMirrorTheServerTypeAndSizeContract() throws {
  let valid = FileUpload(
    data: Data("pdf".utf8), filename: "contrato.pdf", mediaType: "application/pdf"
  )
  #expect(try AttachmentUploadRules.validated(valid) == valid)
  #expect(AttachmentUploadRules.maxByteCount == 10 * 1024 * 1024)

  #expect(throws: DemoError(message: "Envie um arquivo PDF, JPEG ou PNG.")) {
    try AttachmentUploadRules.validated(
      FileUpload(data: Data("texto".utf8), filename: "notas.txt", mediaType: "text/plain")
    )
  }
  #expect(throws: DemoError(message: "O arquivo excede o limite de 10 MB.")) {
    try AttachmentUploadRules.validated(
      FileUpload(
        data: Data(repeating: 0, count: AttachmentUploadRules.maxByteCount + 1),
        filename: "contrato.pdf",
        mediaType: "application/pdf"
      )
    )
  }
  #expect(throws: DemoError(message: "O arquivo selecionado está vazio.")) {
    try AttachmentUploadRules.validated(
      FileUpload(data: Data(), filename: "contrato.pdf", mediaType: "application/pdf")
    )
  }
}
