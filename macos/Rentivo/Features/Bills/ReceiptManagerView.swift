import RentivoCore
import SwiftUI

/// The receipts attached to one bill, plus the two macOS ways to add another: the file importer
/// and a Finder drag straight onto this section.
struct ReceiptManagerView: View {
  @Environment(AppModel.self) private var app
  let billingID: BillingID
  let bill: Bill
  let canWrite: Bool
  let onMutation: () async -> Void
  @State private var downloadedFile: DownloadedFile?
  @State private var showingFileImporter = false
  @State private var isDropTargeted = false
  @State private var pendingDeletion: Receipt?
  /// Covers the whole upload — the off-main read and transcode as well as the request — because
  /// all three are time the user is waiting on one file, and a second file dropped into the middle
  /// of it would race the refresh that follows.
  @State private var isUploading = false
  /// Which receipt is being fetched, so the row that started it shows the wait and a second click
  /// cannot queue a duplicate download of the same file.
  @State private var downloadingReceiptID: ReceiptID?

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      HStack {
        SectionTitle(title: "Comprovantes", symbol: "paperclip")
        if !bill.receipts.isEmpty {
          Spacer()
          Text(ptBRCount(bill.receipts.count, singular: "comprovante", plural: "comprovantes"))
            .font(RentivoTypography.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      // The card also has to appear for a bill with no receipts yet while one is being sent —
      // otherwise the very first upload has nowhere to show its progress.
      if bill.receipts.isEmpty && !isUploading {
        Text("Nenhum comprovante anexado.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        RentivoCard {
          VStack(spacing: RentivoSpacing.medium) {
            ForEach(bill.receipts) { receipt in
              HStack {
                Label(receipt.name, systemImage: "doc.fill")
                  .font(RentivoTypography.body)
                Spacer()
                if downloadingReceiptID == receipt.id {
                  ProgressView()
                    .controlSize(.small)
                }
                Menu {
                  Button("Abrir") { Task { await download(receipt) } }
                    .disabled(downloadingReceiptID != nil)
                  if canWrite {
                    Button("Excluir", role: .destructive) { pendingDeletion = receipt }
                      .disabled(isUploading)
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Mais opções para \(receipt.name)")
              }
              .rentivoHoverLift(elevated: true)
            }
            if isUploading {
              HStack(spacing: RentivoSpacing.small) {
                ProgressView()
                  .controlSize(.small)
                Text("Enviando…")
                  .font(RentivoTypography.body)
                  .foregroundStyle(RentivoColors.secondaryInk)
                Spacer()
              }
              .accessibilityIdentifier("receipt.uploading")
            }
            // Drag-to-reorder would need these rows hosted in a `List`, but this section renders
            // inside a `RentivoCard`/`VStack` (the surrounding screen is a `ScrollView`, not a
            // `List`). Kept as an explicit action instead of restructuring the whole detail
            // screen's layout around a `List`.
            if bill.receipts.count > 1 && canWrite {
              Button("Inverter ordem") { Task { await reverse() } }
                .buttonStyle(.bordered)
                .disabled(isUploading)
            }
          }
        }
      }
      if canWrite {
        Button {
          showingFileImporter = true
        } label: {
          Label("Adicionar comprovante", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .disabled(isUploading)
        // Drag-and-drop is invisible until it is named: without this line the drop target below
        // is a feature only a user who happens to try it would ever find.
        Text("Ou arraste um arquivo do Finder para esta área.")
          .font(RentivoTypography.caption)
          .foregroundStyle(RentivoColors.secondaryInk)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(canWrite ? RentivoSpacing.small : 0)
    .overlay {
      if canWrite {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(
            RentivoColors.emerald,
            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
          )
          .opacity(isDropTargeted ? 1 : 0)
      }
    }
    .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    // Only accepted while the user may write: a viewer dropping a file would otherwise get a
    // permission error from the server for a gesture the UI implied was available. Refusing the
    // drop outright while an upload is in flight is what keeps a second file from racing the
    // first one's refresh — returning `false` also tells Finder the drop was not taken.
    .dropDestination(for: URL.self) { urls, _ in
      guard canWrite, !isUploading, let url = ReceiptIntake.firstFileURL(in: urls) else {
        return false
      }
      Task { await add(fileURL: url) }
      return true
    } isTargeted: { isDropTargeted = $0 && !isUploading }
    .downloadedFileSheet($downloadedFile)
    .fileImporter(
      isPresented: $showingFileImporter,
      allowedContentTypes: ReceiptIntake.allowedContentTypes,
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else { return }
      Task { await add(fileURL: url) }
    }
    .confirmationDialog(
      "Excluir este comprovante?",
      isPresented: Binding(presence: $pendingDeletion),
      titleVisibility: .visible
    ) {
      Button("Excluir comprovante", role: .destructive) {
        if let receipt = pendingDeletion { Task { await remove(receipt) } }
      }
      Button("Cancelar", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text("O comprovante será removido permanentemente desta fatura.")
    }
  }

  private func add(fileURL: URL) async {
    // The importer and the drop target are both closed while `isUploading`, but a file importer
    // that was already open when the flag went up can still deliver — so the guard lives here,
    // where every path passes.
    guard !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    do {
      guard let upload = try await ReceiptIntake.upload(from: fileURL) else {
        app.showNotice("Não foi possível ler o arquivo selecionado.", kind: .warning)
        return
      }
      await send(upload)
    } catch let error as ReceiptIntakeError {
      app.showNotice(error.message, kind: .warning)
    } catch { app.reportFailure(error) }
  }

  private func send(_ upload: FileUpload) async {
    // The intake already refused anything the filesystem reported as oversize; this is the same
    // rule applied to the bytes that actually came out of it, which a re-encode can have grown.
    guard !ReceiptUploadLimit.exceedsLimit(byteCount: upload.byteCount) else {
      app.showNotice(ReceiptIntakeError.exceedsSizeLimit.message, kind: .warning)
      return
    }
    do {
      _ = try await app.dependencies.bills.addReceipt(
        billingID: billingID,
        billID: bill.id,
        upload: upload
      )
      await onMutation()
    } catch { app.reportFailure(error) }
  }

  private func remove(_ receipt: Receipt) async {
    do {
      try await app.dependencies.bills.deleteReceipt(
        billingID: billingID,
        billID: bill.id,
        receiptID: receipt.id
      )
      await onMutation()
    } catch { app.reportFailure(error) }
  }

  private func reverse() async {
    do {
      try await app.dependencies.bills.reorderReceipts(
        billingID: billingID, billID: bill.id, receiptIDs: Array(bill.receipts.map(\.id).reversed())
      )
      await onMutation()
    } catch { app.reportFailure(error) }
  }

  private func download(_ receipt: Receipt) async {
    guard downloadingReceiptID == nil else { return }
    downloadingReceiptID = receipt.id
    defer { downloadingReceiptID = nil }
    do {
      downloadedFile = try await app.dependencies.downloads.downloadReceipt(
        billingID: billingID, billID: bill.id, receiptID: receipt.id
      )
    } catch { app.reportFailure(error) }
  }
}
