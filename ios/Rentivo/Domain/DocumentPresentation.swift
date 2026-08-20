import Foundation

/// Customer-visible naming and filesystem-safe sharing metadata for a downloaded document.
public struct DocumentPresentation: Hashable, Sendable {
  public let displayName: String
  public let suggestedFilename: String
  public let mediaType: String

  public init(
    displayName: String,
    suggestedFilename: String,
    mediaType: String = "application/pdf"
  ) {
    self.displayName = displayName
    self.suggestedFilename = suggestedFilename
    self.mediaType = mediaType
  }

  public var sanitizedFilename: String {
    Self.sanitizedFilename(suggestedFilename)
  }

  public static func invoice(
    billingName: String, referenceMonth: ReferenceMonth
  ) -> DocumentPresentation {
    generated(prefix: "Fatura", billingName: billingName, referenceMonth: referenceMonth)
  }

  public static func generatedReceipt(
    billingName: String, referenceMonth: ReferenceMonth
  ) -> DocumentPresentation {
    generated(prefix: "Recibo", billingName: billingName, referenceMonth: referenceMonth)
  }

  public static func uploadedReceipt(
    filename: String,
    billingName: String,
    referenceMonth: ReferenceMonth,
    mediaType: String
  ) -> DocumentPresentation {
    let filename = trimmed(filename)
    guard !filename.isEmpty else {
      let displayName = "Comprovante - \(trimmed(billingName)) - \(referenceMonth.documentDisplayFormatted)"
      return DocumentPresentation(
        displayName: displayName,
        suggestedFilename: resolvedFilename(displayName, mediaType: mediaType),
        mediaType: mediaType
      )
    }
    return DocumentPresentation(
      displayName: deletingPathExtension(filename),
      suggestedFilename: filename,
      mediaType: mediaType
    )
  }

  public static func attachment(
    name: String, filename: String, mediaType: String
  ) -> DocumentPresentation {
    let name = trimmed(name)
    let filename = trimmed(filename)
    let displayName = !name.isEmpty ? name : (!filename.isEmpty ? filename : "Arquivo")
    let suggestedFilename = !filename.isEmpty
      ? filename
      : resolvedFilename(displayName, mediaType: mediaType)
    return DocumentPresentation(
      displayName: displayName, suggestedFilename: suggestedFilename, mediaType: mediaType)
  }

  /// Compatibility fallback for callers that do not own richer document context yet.
  public static func serverFallback(
    serverName: String, mediaType: String
  ) -> DocumentPresentation {
    let serverName = trimmed(serverName)
    guard !serverName.isEmpty else {
      return DocumentPresentation(
        displayName: "Arquivo",
        suggestedFilename: resolvedFilename("Arquivo", mediaType: mediaType),
        mediaType: mediaType
      )
    }
    return DocumentPresentation(
      displayName: deletingPathExtension(serverName),
      suggestedFilename: resolvedFilename(serverName, mediaType: mediaType),
      mediaType: mediaType
    )
  }

  public static func resolvedFilename(_ filename: String, mediaType: String) -> String {
    let filename = trimmed(filename)
    let base = deletingPathExtension(filename)
    let currentExtension = pathExtension(filename)
    guard let resolvedExtension = filenameExtension(for: mediaType) else {
      if !currentExtension.isEmpty { return filename }
      return "\(filename.isEmpty ? "arquivo" : filename).bin"
    }
    let resolvedBase = base.isEmpty ? "arquivo" : base
    return "\(resolvedBase).\(resolvedExtension)"
  }

  public static func sanitizedFilename(_ filename: String) -> String {
    let filename = trimmed(filename)
    let rawExtension = pathExtension(filename)
    let rawBase = rawExtension.isEmpty ? filename : deletingPathExtension(filename)
    let forbidden = CharacterSet.controlCharacters.union(
      CharacterSet(charactersIn: "/\\:\"")
    )
    let base = rawBase.unicodeScalars.filter { !forbidden.contains($0) }
      .map(String.init).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
    let safeBase = base.isEmpty ? "arquivo" : base
    let filteredExtension = rawExtension.unicodeScalars.filter {
      CharacterSet.alphanumerics.contains($0)
    }.map(String.init).joined().lowercased()
    // APFS limits one path component to 255 UTF-8 bytes. Keep room for the extension so a long
    // customer-facing billing name cannot make an otherwise valid download fail at the final move.
    let safeExtension = utf8Prefix(filteredExtension, maximumByteCount: 32)
    let suffix = safeExtension.isEmpty ? "" : ".\(safeExtension)"
    let maximumBaseByteCount = 255 - suffix.utf8.count
    let limitedBase = utf8Prefix(safeBase, maximumByteCount: maximumBaseByteCount)
    return "\(limitedBase.isEmpty ? "arquivo" : limitedBase)\(suffix)"
  }

  public static func symbolName(mediaType: String, filename: String) -> String {
    let normalizedMediaType = mediaType.split(separator: ";", maxSplits: 1).first?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if normalizedMediaType == "application/pdf" { return "doc.richtext.fill" }
    if normalizedMediaType.hasPrefix("image/") { return "photo.fill" }
    if normalizedMediaType == "text/csv"
      || normalizedMediaType == "application/csv"
      || normalizedMediaType == "application/vnd.ms-excel"
      || normalizedMediaType
        == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    {
      return "tablecells.fill"
    }
    switch pathExtension(filename).lowercased() {
    case "pdf": return "doc.richtext.fill"
    case "jpg", "jpeg", "png", "heic", "gif", "webp", "tif", "tiff": return "photo.fill"
    case "csv", "xls", "xlsx": return "tablecells.fill"
    default: return "doc.fill"
    }
  }

  public static func metadataLine(
    byteCount: Int, createdAt: Date? = nil, timeZone: TimeZone = .current
  ) -> String {
    let size = BrazilianLocaleFormatting.fileSize(byteCount)
    guard let createdAt else { return size }
    return "\(size) • \(createdAt.formattedPTBR(date: .numeric, timeZone: timeZone))"
  }

  private static func generated(
    prefix: String, billingName: String, referenceMonth: ReferenceMonth
  ) -> DocumentPresentation {
    let displayName = "\(prefix) - \(trimmed(billingName)) - \(referenceMonth.documentDisplayFormatted)"
    return DocumentPresentation(displayName: displayName, suggestedFilename: "\(displayName).pdf")
  }

  private static func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func pathExtension(_ filename: String) -> String {
    guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else { return "" }
    return String(filename[filename.index(after: dot)...])
  }

  private static func deletingPathExtension(_ filename: String) -> String {
    guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else { return filename }
    return String(filename[..<dot])
  }

  private static func filenameExtension(for mediaType: String) -> String? {
    switch mediaType.split(separator: ";", maxSplits: 1).first?
      .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    {
    case "application/pdf": "pdf"
    case "image/jpeg": "jpg"
    case "image/png": "png"
    case "image/heic", "image/heif": "heic"
    case "text/csv", "application/csv": "csv"
    case "application/vnd.ms-excel": "xls"
    case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx"
    case "text/plain": "txt"
    default: nil
    }
  }

  private static func utf8Prefix(_ value: String, maximumByteCount: Int) -> String {
    var result = ""
    var byteCount = 0
    for character in value {
      let characterByteCount = String(character).utf8.count
      guard byteCount + characterByteCount <= maximumByteCount else { break }
      result.append(character)
      byteCount += characterByteCount
    }
    return result
  }
}
