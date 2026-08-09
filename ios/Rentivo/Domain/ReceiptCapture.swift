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
}
