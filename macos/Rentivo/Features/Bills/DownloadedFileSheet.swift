import AppKit
import RentivoCore
import SwiftUI
import UniformTypeIdentifiers

extension View {
  /// Presents `DownloadShareView` for `file` and removes the downloaded file from `tmp/` once that
  /// sheet is gone.
  ///
  /// The removal is driven by the binding losing its value, never from inside `DownloadShareView`:
  /// while that sheet is on screen its `ShareLink` still needs the file on disk. Unlinking it
  /// afterwards is safe even for a file the user opened in another app — the receiving app already
  /// holds an open descriptor, and the bytes survive until it closes.
  func downloadedFileSheet(_ file: Binding<DownloadedFile?>) -> some View {
    modifier(DownloadedFileSheetModifier(file: file))
  }
}

private struct DownloadedFileSheetModifier: ViewModifier {
  @Binding var file: DownloadedFile?

  func body(content: Content) -> some View {
    content
      .sheet(item: $file) { presented in DownloadShareView(file: presented) }
      // `onChange` rather than `sheet(item:onDismiss:)`: `onDismiss` takes no argument and runs
      // after SwiftUI has already cleared the binding, leaving nothing to identify the file to
      // remove. The previous value here is exactly that file, and this also covers one download
      // replacing another without an intervening dismissal.
      .onChange(of: file) { previous, _ in
        guard let previous else { return }
        DownloadedFileStore.remove(previous)
      }
  }
}

/// Naming and typing rules for handing a downloaded file to the save panel.
enum DownloadedFileExport {
  /// The file's type, preferred from the media type the server declared and falling back to what
  /// the filename claims. `.data` is the last resort: the save panel needs *some* type, and an
  /// unrecognized one must not stop the user from saving the bytes.
  static func contentType(for file: DownloadedFile) -> UTType {
    UTType(mimeType: file.mediaType)
      ?? UTType(filenameExtension: (file.filename as NSString).pathExtension)
      ?? .data
  }

  /// The save panel appends the extension belonging to `contentType`, so the name it is seeded
  /// with is the stem alone — otherwise a "fatura.pdf" download is offered as "fatura.pdf.pdf".
  static func defaultFilename(for file: DownloadedFile) -> String {
    let stem = (file.filename as NSString).deletingPathExtension
    return stem.isEmpty ? file.filename : stem
  }
}

/// Wraps already-downloaded bytes for `fileExporter`, which writes from a document rather than
/// copying a file: the temp file is short-lived, so the export must not depend on it still
/// existing when the user finally picks a destination.
private struct DownloadedFileDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.data]

  let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

/// What the app offers for a file it just downloaded.
///
/// iOS leans entirely on `ShareLink`, whose sheet includes "Salvar em Arquivos". On macOS the two
/// things a user actually wants — save it somewhere, or just look at it — are direct buttons, and
/// sharing stays as the third option rather than the only one.
struct DownloadShareView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let file: DownloadedFile

  @State private var exportDocument: DownloadedFileDocument?
  @State private var showingExporter = false

  var body: some View {
    NavigationStack { content }
  }

  private var content: some View {
    VStack(spacing: RentivoSpacing.large) {
      Image(systemName: "doc.text.fill")
        .font(.system(size: 64))
        .foregroundStyle(RentivoColors.blue)
      Text(file.filename).font(RentivoTypography.title)
      Text("Arquivo baixado do Rentivo.").foregroundStyle(RentivoColors.secondaryInk)

      VStack(spacing: RentivoSpacing.medium) {
        Button {
          prepareExport()
        } label: {
          Label("Salvar como…", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(RentivoButtonStyle(color: RentivoColors.blue))
        .accessibilityIdentifier("download.save")

        Button {
          NSWorkspace.shared.open(file.fileURL)
        } label: {
          Label("Abrir", systemImage: "arrow.up.forward.app")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("download.open")

        ShareLink(item: file.fileURL) {
          Label("Compartilhar ou salvar arquivo", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.bordered)
      }
      .frame(maxWidth: 320)

      Spacer()
    }
    .padding(RentivoSpacing.page)
    .frame(minWidth: 420, minHeight: 380)
    .rentivoPage()
    .navigationTitle("Prévia")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Concluir") { dismiss() }
      }
    }
    .fileExporter(
      isPresented: $showingExporter,
      document: exportDocument,
      contentType: DownloadedFileExport.contentType(for: file),
      defaultFilename: DownloadedFileExport.defaultFilename(for: file)
    ) { result in
      if case .failure(let error) = result {
        app.reportFailure(error)
      }
    }
  }

  /// Reads the temp file up front so the exporter owns the bytes, and reports the rare failure
  /// (a file the system already reclaimed) instead of opening an empty save panel.
  private func prepareExport() {
    do {
      exportDocument = DownloadedFileDocument(data: try Data(contentsOf: file.fileURL))
      showingExporter = true
    } catch {
      app.showNotice("Não foi possível ler o arquivo baixado.", kind: .warning)
    }
  }
}
