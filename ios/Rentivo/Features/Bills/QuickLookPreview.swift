import QuickLook
import SwiftUI

struct QuickLookPreview: UIViewControllerRepresentable {
  let file: DownloadedFile

  func makeCoordinator() -> Coordinator {
    Coordinator(file: file)
  }

  func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: QLPreviewController, context: Context) {
    guard context.coordinator.item.file != file else { return }
    context.coordinator.item = PreviewItem(file: file)
    controller.reloadData()
  }

  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    var item: PreviewItem

    init(file: DownloadedFile) {
      item = PreviewItem(file: file)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(
      _ controller: QLPreviewController, previewItemAt index: Int
    ) -> QLPreviewItem {
      item
    }
  }
}

final class PreviewItem: NSObject, QLPreviewItem {
  let file: DownloadedFile
  let previewItemURL: URL?
  let previewItemTitle: String?

  init(file: DownloadedFile) {
    self.file = file
    previewItemURL = file.fileURL
    previewItemTitle = file.displayName
  }
}
