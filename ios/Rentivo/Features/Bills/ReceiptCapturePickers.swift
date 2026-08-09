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
        picker.onCancel()
        return
      }
      picker.onCapture(image)
    }

    func imagePickerControllerDidCancel(_ controller: UIImagePickerController) {
      picker.onCancel()
    }
  }
}

extension FileUpload {
  /// A captured photo only exists as pixels, so it is re-encoded as JPEG and named here.
  static func capturedPhoto(_ image: UIImage, compressionQuality: CGFloat = 0.8) -> Self? {
    guard let data = image.jpegData(compressionQuality: compressionQuality) else { return nil }
    let descriptor = ReceiptMediaDescriptor.jpeg
    return Self(
      data: data,
      filename: ReceiptFilename.captured(filenameExtension: descriptor.filenameExtension),
      mediaType: descriptor.mediaType
    )
  }
}

extension PhotosPickerItem {
  /// Loads the picked asset's bytes tagged with its own media type. Returns `nil` when the item
  /// carries no data representation the picker can hand over.
  func receiptUpload() async throws -> FileUpload? {
    guard let data = try await loadTransferable(type: Data.self) else { return nil }
    let descriptor = ReceiptMediaDescriptor.inferred(from: supportedContentTypes)
    return FileUpload(
      data: data,
      filename: ReceiptFilename.captured(filenameExtension: descriptor.filenameExtension),
      mediaType: descriptor.mediaType
    )
  }
}
