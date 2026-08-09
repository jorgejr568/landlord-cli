import PhotosUI
import SwiftUI
import UIKit

/// Where a new receipt comes from.
enum ReceiptSource: String, Identifiable, CaseIterable {
  case files
  case camera
  case photos

  var id: String { rawValue }

  var label: String {
    switch self {
    case .files: "Arquivos"
    case .camera: "Câmera"
    case .photos: "Fotos"
    }
  }

  /// The camera is dropped on devices that have none — notably the simulator, where presenting
  /// `UIImagePickerController` with `.camera` traps.
  @MainActor static var available: [ReceiptSource] {
    allCases.filter { $0 != .camera || UIImagePickerController.isSourceTypeAvailable(.camera) }
  }
}

/// `PhotosPicker` covers the library but never the camera, so capture still goes through
/// `UIImagePickerController`.
struct ReceiptCameraPicker: UIViewControllerRepresentable {
  let onCapture: (UIImage) -> Void
  let onCancel: () -> Void
  let onFailure: () -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(picker: self) }

  @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate
  {
    private let picker: ReceiptCameraPicker

    init(picker: ReceiptCameraPicker) {
      self.picker = picker
    }

    func imagePickerController(
      _ controller: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      guard let image = info[.originalImage] as? UIImage else {
        picker.onFailure()
        return
      }
      picker.onCapture(image)
    }

    func imagePickerControllerDidCancel(_ controller: UIImagePickerController) {
      picker.onCancel()
    }
  }
}

extension UIImage {
  /// `jpegData` leaves the pixels as captured and records the rotation as EXIF metadata, which not
  /// every consumer of the uploaded receipt honors. Redrawing through a renderer bakes the
  /// orientation into the pixels, so the encoded bytes are upright on their own.
  fileprivate func uprightJPEGData(compressionQuality: CGFloat) -> Data? {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = scale
    format.opaque = true
    let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: size))
    }
    return upright.jpegData(compressionQuality: compressionQuality)
  }
}

extension FileUpload {
  /// A captured photo only exists as pixels, so it is re-encoded as JPEG and named here.
  static func capturedPhoto(_ image: UIImage, compressionQuality: CGFloat = 0.8) -> Self? {
    guard let data = image.uprightJPEGData(compressionQuality: compressionQuality) else {
      return nil
    }
    let descriptor = ReceiptMediaDescriptor.jpeg
    return Self(
      data: data,
      filename: ReceiptFilename.captured(filenameExtension: descriptor.filenameExtension),
      mediaType: descriptor.mediaType
    )
  }

  /// Library bytes are uploaded as they are when the server already accepts their format, and are
  /// otherwise decoded and re-encoded as JPEG. Returns `nil` when the bytes are not a decodable
  /// image, which is the only case the caller cannot recover from.
  static func libraryPhoto(data: Data, descriptor: ReceiptMediaDescriptor) -> Self? {
    guard ReceiptMediaDescriptor.requiresReencoding(mediaType: descriptor.mediaType) else {
      return Self(
        data: data,
        filename: ReceiptFilename.captured(filenameExtension: descriptor.filenameExtension),
        mediaType: descriptor.mediaType
      )
    }
    guard let image = UIImage(data: data) else { return nil }
    return capturedPhoto(image)
  }

  /// The file importer accepts any image, so a file picked from Arquivos can carry a format the
  /// server drops — an iCloud HEIC, a TIFF scan. Accepted formats pass through untouched, anything
  /// else is decoded and re-encoded as JPEG under its own name, and `nil` means the bytes were not
  /// a decodable image.
  func clampedToAcceptedReceiptFormat() -> Self? {
    guard !ReceiptMediaDescriptor.isAllowed(mediaType: mediaType) else { return self }
    guard let image = UIImage(data: data), let reencoded = Self.capturedPhoto(image) else {
      return nil
    }
    return Self(
      data: reencoded.data,
      filename: ReceiptFilename.reencoded(
        from: filename, filenameExtension: ReceiptMediaDescriptor.jpeg.filenameExtension),
      mediaType: reencoded.mediaType
    )
  }
}

extension PhotosPickerItem {
  /// Loads the picked asset's bytes in a format the server accepts. Returns `nil` when the item
  /// carries no data representation the picker can hand over, or when those bytes are neither an
  /// accepted format nor a decodable image.
  func receiptUpload() async throws -> FileUpload? {
    guard let data = try await loadTransferable(type: Data.self) else { return nil }
    return FileUpload.libraryPhoto(
      data: data,
      descriptor: ReceiptMediaDescriptor.inferred(from: supportedContentTypes)
    )
  }
}
