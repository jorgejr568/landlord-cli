import Foundation
import UniformTypeIdentifiers

/// Media type and filename extension for a receipt that arrives as raw bytes instead of as a file
/// on disk — a photo taken with the camera or picked from the photo library.
public struct ReceiptMediaDescriptor: Hashable, Sendable {
  public let mediaType: String
  public let filenameExtension: String

  public init(mediaType: String, filenameExtension: String) {
    self.mediaType = mediaType
    self.filenameExtension = filenameExtension
  }

  public static let jpeg = Self(mediaType: "image/jpeg", filenameExtension: "jpg")

  /// Mirrors `ALLOWED_RECEIPT_TYPES` in `backend/rentivo/models/receipt.py`. Anything else is
  /// dropped by the server without an error, so the client never sends it.
  public static let allowedMediaTypes: Set<String> = [
    "application/pdf", "image/jpeg", "image/png",
  ]

  public static func isAllowed(mediaType: String) -> Bool {
    allowedMediaTypes.contains(mediaType.lowercased())
  }

  /// Photo-library assets keep the format they were stored in — HEIC on any recent iPhone — which
  /// the server rejects, so those bytes have to be re-encoded as JPEG before they are uploaded.
  public static func requiresReencoding(mediaType: String) -> Bool {
    mediaType.lowercased() != jpeg.mediaType && mediaType.lowercased() != "image/png"
  }

  /// Picker items advertise their content types in preference order. The first type that maps to
  /// both a MIME type and a filename extension wins; anything else falls back to JPEG, which is
  /// what the photo library hands back for camera-originated assets anyway.
  public static func inferred(from contentTypes: [UTType]) -> Self {
    for type in contentTypes {
      if let mediaType = type.preferredMIMEType,
        let filenameExtension = type.preferredFilenameExtension
      {
        return Self(mediaType: mediaType, filenameExtension: filenameExtension)
      }
    }
    return .jpeg
  }
}

public enum ReceiptUploadLimit {
  /// Mirrors `MAX_RECEIPT_SIZE` in `backend/rentivo/models/receipt.py`.
  public static let maxByteCount = 10 * 1024 * 1024

  /// How the limit is named in user-facing PT-BR copy.
  public static let label = "10 MB"

  public static func exceedsLimit(byteCount: Int) -> Bool { byteCount > maxByteCount }
}

public enum ReceiptFilename {
  /// Names a receipt captured from the camera or the photo library, which carries no filename of
  /// its own: `comprovante-20260809-143005.jpg`.
  public static func captured(
    at date: Date = Date(),
    filenameExtension: String = ReceiptMediaDescriptor.jpeg.filenameExtension,
    timeZone: TimeZone = .current
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "comprovante-\(formatter.string(from: date)).\(filenameExtension)"
  }

  /// Renames a file whose bytes had to be re-encoded, so the extension keeps matching the media
  /// type actually uploaded. The stem the user already recognizes is kept; a name that carries no
  /// usable stem — empty, or nothing but an extension — falls back to a generated one.
  public static func reencoded(
    from filename: String,
    filenameExtension: String = ReceiptMediaDescriptor.jpeg.filenameExtension,
    at date: Date = Date(),
    timeZone: TimeZone = .current
  ) -> String {
    // An empty path resolves against the working directory, so it never reaches `URL`.
    let stem =
      filename.isEmpty
      ? "" : URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    guard !stem.isEmpty, !stem.hasPrefix(".") else {
      return captured(at: date, filenameExtension: filenameExtension, timeZone: timeZone)
    }
    return "\(stem).\(filenameExtension)"
  }
}
