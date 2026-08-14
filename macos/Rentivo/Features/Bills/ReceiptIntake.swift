import AppKit
import Foundation
import RentivoCore
import UniformTypeIdentifiers

/// Why a picked or dropped file never reached the network.
///
/// Deliberately separate from the repository's errors: these are decided locally, before a request
/// exists, so each case carries the PT-BR sentence the screen shows for it. Letting `DemoError`
/// translate them instead would put generic network copy on a file the app itself refused.
enum ReceiptIntakeError: Error, Equatable {
  /// The file weighs more than can end well: either the filesystem already reports it as larger
  /// than the server accepts, or it is so far past that limit that transcoding it could not bring
  /// it back under.
  case exceedsSizeLimit

  var message: String {
    switch self {
    case .exceedsSizeLimit:
      "O comprovante excede o limite de \(ReceiptUploadLimit.label)."
    }
  }
}

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

  /// The ceiling for a file that still has to be transcoded before it can be uploaded.
  ///
  /// A TIFF or HEIC scan is routinely several times the weight of the JPEG it becomes, so the
  /// server's 10 MB rule says nothing useful about its bytes on disk — a 14 MB TIFF is an ordinary
  /// receipt that uploads as about 1 MB. This is not that rule: it is only the line past which a
  /// file is not worth paging into memory to find out, which is what the pre-read gate exists for.
  /// `nonisolated` because the gate that consults it runs off the main actor, like the read it
  /// guards.
  nonisolated static let transcodeReadCeiling = 100 * 1024 * 1024

  /// Reads `url` off the main actor and clamps it to a format the server stores. Returns `nil` when
  /// the bytes are neither an accepted format nor a decodable image, and throws
  /// `ReceiptIntakeError.exceedsSizeLimit` for a file the filesystem already reports as too large
  /// for the path it is on — see `exceedsLimitBeforeReading(declaredByteCount:mediaType:)` for the
  /// two tiers that phrase covers.
  ///
  /// `nonisolated` plus `async` is what moves the work off the window: such a function never
  /// inherits its caller's actor, so everything below runs on the cooperative pool even though
  /// every call site is a `@MainActor` view. Both halves needed that. `Data(contentsOf:)` blocks
  /// for as long as the bytes take to arrive — up to the 10 MB a receipt may weigh, and
  /// unboundedly for an iCloud file the system still has to download — and the decode plus JPEG
  /// re-encode below is pure CPU that `NSBitmapImageRep` is happy to do on any thread.
  ///
  /// The security-scoped resource is claimed and released around the read *here*, inside the
  /// off-main work, rather than by the caller: the claim only has to outlive the read, and the read
  /// no longer happens where the caller stands.
  nonisolated static func upload(from url: URL) async throws -> FileUpload? {
    let accessGranted = url.startAccessingSecurityScopedResource()
    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
    guard
      !exceedsLimitBeforeReading(
        declaredByteCount: declaredByteCount(of: url), mediaType: mediaType(of: url))
    else {
      throw ReceiptIntakeError.exceedsSizeLimit
    }
    return try FileUpload.from(url: url).clampedToAcceptedReceiptFormat()
  }

  /// Reads `url` off the main actor without touching its format, for the files the server stores
  /// exactly as uploaded — arquivos, not comprovantes. Same off-main and security-scope reasoning
  /// as `upload(from:)`; only the receipt-specific clamping and size rule are absent.
  nonisolated static func rawUpload(from url: URL) async throws -> FileUpload {
    let accessGranted = url.startAccessingSecurityScopedResource()
    defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
    return try FileUpload.from(url: url)
  }

  /// What the filesystem says `url` weighs, or `nil` when it will not say. Silence is not evidence
  /// of anything, so an unreadable attribute leaves the decision to the bytes themselves.
  nonisolated static func declaredByteCount(of url: URL) -> Int? {
    (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
  }

  /// The media type the read would give `url`, decided from its name exactly as
  /// `FileUpload.from(url:)` does. The pre-read gate needs it to know which path the bytes are
  /// heading down, and deriving it the same way is what keeps the two in step.
  nonisolated static func mediaType(of url: URL) -> String {
    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
  }

  /// Whether a receipt can be refused before a single byte is read, in two tiers.
  ///
  /// A file the server already accepts as it is — PDF, JPEG, PNG — is uploaded byte-for-byte, so
  /// its declared size *is* the size that will be sent and the 10 MB rule applies to it directly.
  /// Anything else is transcoded to JPEG first, and its size on disk predicts nothing about the
  /// result: a 14 MB TIFF scan becomes a ~1 MB JPEG, and refusing it here would refuse the exact
  /// case `clampedToAcceptedReceiptFormat()` exists to handle. Those formats get only
  /// `transcodeReadCeiling`, which keeps the memory protection this gate was written for and
  /// leaves the verdict on the bytes to the post-encode check in `ReceiptManagerView.send()`.
  ///
  /// Either way this does not replace that check: an unknown size skips the gate entirely, and
  /// re-encoding moves the count in both directions, so both sides of the read keep their guard.
  nonisolated static func exceedsLimitBeforeReading(
    declaredByteCount: Int?, mediaType: String
  ) -> Bool {
    guard let declaredByteCount else { return false }
    guard ReceiptMediaDescriptor.isAllowed(mediaType: mediaType) else {
      return declaredByteCount > transcodeReadCeiling
    }
    return ReceiptUploadLimit.exceedsLimit(byteCount: declaredByteCount)
  }
}

extension FileUpload {
  /// The importer accepts any image, so a picked or dropped file can carry a format the server
  /// drops — an iCloud HEIC, a TIFF scan. Accepted formats pass through untouched, anything else
  /// is decoded and re-encoded as JPEG under its own name, and `nil` means the bytes were not a
  /// decodable image. Mirrors the iOS `clampedToAcceptedReceiptFormat()` exactly.
  ///
  /// Nonisolated on purpose: the transcode is the expensive half of `ReceiptIntake.upload(from:)`
  /// and has to be callable from the cooperative pool it runs on.
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
  ///
  /// Nothing here touches AppKit's view hierarchy, so it needs no main thread and does not claim
  /// one; the representation is created and consumed inside this call.
  static func jpegData(from data: Data, compressionQuality: Double = 0.8) -> Data? {
    guard let representation = NSBitmapImageRep(data: data) else { return nil }
    return representation.representation(
      using: .jpeg,
      properties: [.compressionFactor: compressionQuality]
    )
  }
}
