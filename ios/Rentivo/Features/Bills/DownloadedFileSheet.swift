import SwiftUI

extension View {
  /// Presents the shared Quick Look preview for `file` and removes its private temporary directory
  /// once that sheet is gone.
  ///
  /// The removal is driven by the binding losing its value, never from inside `DownloadShareView`:
  /// while that sheet is on screen its `ShareLink` still needs the file on disk. That is safe
  /// because every activity the user can pick from the share sheet (Mail, Mensagens, Salvar em
  /// Arquivos, AirDrop, third-party extensions) presents its own UI *above* this sheet, so this
  /// sheet cannot be dismissed — and the binding cannot be cleared — while one of them is still
  /// reading the file.
  func downloadedFileSheet(_ file: Binding<DownloadedFile?>) -> some View {
    modifier(DownloadedFileSheetModifier(file: file))
  }
}

private struct DownloadedFileSheetModifier: ViewModifier {
  @Binding var file: DownloadedFile?

  func body(content: Content) -> some View {
    content
      .sheet(item: $file) { presented in
        DownloadShareView(file: presented)
          .presentationDetents([.large])
      }
      // `onChange` rather than `sheet(item:onDismiss:)`: `onDismiss` takes no argument and runs
      // after SwiftUI has already cleared the binding, leaving nothing to identify the file to
      // remove. The previous value here is exactly that file, and this also covers one download
      // replacing another without an intervening dismissal. `onDisappear` on the sheet's content
      // is not equivalent — UIKit fires appearance transitions on a view controller covered by a
      // full-screen presentation, which could fire it while a share is still in flight.
      .onChange(of: file) { previous, _ in
        guard let previous else { return }
        DownloadedFileStore.shared.remove(previous)
      }
  }
}
