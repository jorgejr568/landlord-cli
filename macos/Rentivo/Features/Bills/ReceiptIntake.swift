import AppKit
import Foundation
import RentivoCore
import UniformTypeIdentifiers

/// Where a receipt comes from on macOS.
///
/// iOS offers three sources through UIKit — Arquivos, Câmera and Fotos. A Mac has no camera
/// picker worth presenting (most Macs have only a webcam pointed at the user, and
/// `UIImagePickerController` has no AppKit counterpart), and the photo library is reachable from
/// the standard open panel's sidebar, so both collapse into the file importer. Dragging a file
/// out of Finder onto the receipts section is the second, more Mac-native path.
///
/// Both paths end in the same `FileUpload`, validated and named by the same `RentivoCore` rules
/// the iOS app applies, so the bytes that reach the server are identical on both platforms.
@MainActor
enum ReceiptIntake {
  /// What the file importer and the drop target accept, matching the iOS importer.
  static let allowedContentTypes: [UTType] = [.pdf, .image]

  /// The first dropped item that is actually a file. A Finder drag delivers file URLs; dragging a
  /// link out of a browser delivers a remote one, which carries no bytes to upload.
  static func firstFileURL(in urls: [URL]) -> URL? {
    urls.first(where: \.isFileURL)
  }

  /// Reads `url` and clamps it to a format the server stores, or returns `nil` when the bytes are
  /// neither an accepted format nor a decodable image.
  ///
  /// A file that arrives from the open panel or from a Finder drag is reachable only through a
  /// security-scoped resource, which the sandbox expects to be claimed for the read and released
  /// immediately after.
  static func upload(from url: URL) throws -> FileUpload? {
    let accessGranted = url.startAccessingSecurityScopedResource()
    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
    return try FileUpload.from(url: url).clampedToAcceptedReceiptFormat()
  }
}

extension FileUpload {
  /// The importer accepts any image, so a picked or dropped file can carry a format the server
  /// drops — an iCloud HEIC, a TIFF scan. Accepted formats pass through untouched, anything else
  /// is decoded and re-encoded as JPEG under its own name, and `nil` means the bytes were not a
  /// decodable image. Mirrors the iOS `clampedToAcceptedReceiptFormat()` exactly.
  @MainActor
  func clampedToAcceptedReceiptFormat() -> Self? {
    guard !ReceiptMediaDescriptor.isAllowed(mediaType: mediaType) else { return self }
    guard let reencoded = Self.jpegData(from: data) else { return nil }
    return Self(
      data: reencoded,
      filename: ReceiptFilename.reencoded(
        from: filename, filenameExtension: ReceiptMediaDescriptor.jpeg.filenameExtension),
      mediaType: ReceiptMediaDescriptor.jpeg.mediaType
    )
  }

  /// Decodes `data` as an image and re-encodes it as JPEG. `NSBitmapImageRep` reads the source's
  /// orientation while decoding and hands back upright pixels, so — unlike the iOS path, which
  /// has to redraw a `UIImage` to bake its EXIF rotation in — no extra pass is needed here.
  /// Returns `nil` for bytes that are not a decodable image.
  @MainActor
  static func jpegData(from data: Data, compressionQuality: Double = 0.8) -> Data? {
    guard let representation = NSBitmapImageRep(data: data) else { return nil }
    return representation.representation(
      using: .jpeg,
      properties: [.compressionFactor: compressionQuality]
    )
  }
}
