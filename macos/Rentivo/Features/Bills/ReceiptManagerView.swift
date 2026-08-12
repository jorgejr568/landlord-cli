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

  var body: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
      HStack {
        BillingSectionTitle(title: "Comprovantes", symbol: "paperclip")
        if !bill.receipts.isEmpty {
          Spacer()
          Text(ptBRCount(bill.receipts.count, singular: "comprovante", plural: "comprovantes"))
            .font(.caption)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      if bill.receipts.isEmpty {
        Text("Nenhum comprovante anexado.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        RentivoCard {
          VStack(spacing: RentivoSpacing.medium) {
            ForEach(bill.receipts) { receipt in
              HStack {
                Label(receipt.name, systemImage: "doc.fill")
                  .font(.subheadline)
                Spacer()
                Menu {
                  Button("Abrir") { Task { await download(receipt) } }
                  if canWrite {
                    Button("Excluir", role: .destructive) { pendingDeletion = receipt }
                  }
                } label: {
                  Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Mais opções para \(receipt.name)")
              }
              .billingRowHover()
            }
            // Drag-to-reorder would need these rows hosted in a `List`, but this section renders
            // inside a `RentivoCard`/`VStack` (the surrounding screen is a `ScrollView`, not a
            // `List`). Kept as an explicit action instead of restructuring the whole detail
            // screen's layout around a `List`.
            if bill.receipts.count > 1 && canWrite {
              Button("Inverter ordem") { Task { await reverse() } }
                .buttonStyle(.bordered)
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
        // Drag-and-drop is invisible until it is named: without this line the drop target below
        // is a feature only a user who happens to try it would ever find.
        Text("Ou arraste um arquivo do Finder para esta área.")
          .font(.caption)
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
    // permission error from the server for a gesture the UI implied was available.
    .dropDestination(for: URL.self) { urls, _ in
      guard canWrite, let url = ReceiptIntake.firstFileURL(in: urls) else { return false }
      Task { await add(fileURL: url) }
      return true
    } isTargeted: { isDropTargeted = $0 }
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
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { isPresented in if !isPresented { pendingDeletion = nil } }
      ),
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
    do {
      guard let upload = try ReceiptIntake.upload(from: fileURL) else {
        app.showNotice("Não foi possível ler o arquivo selecionado.", kind: .warning)
        return
      }
      await send(upload)
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func send(_ upload: FileUpload) async {
    guard !ReceiptUploadLimit.exceedsLimit(byteCount: upload.byteCount) else {
      app.showNotice(
        "O comprovante excede o limite de \(ReceiptUploadLimit.label).", kind: .warning)
      return
    }
    do {
      _ = try await app.dependencies.bills.addReceipt(
        billingID: billingID,
        billID: bill.id,
        upload: upload
      )
      await onMutation()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func remove(_ receipt: Receipt) async {
    do {
      try await app.dependencies.bills.deleteReceipt(
        billingID: billingID,
        billID: bill.id,
        receiptID: receipt.id
      )
      await onMutation()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func reverse() async {
    do {
      try await app.dependencies.bills.reorderReceipts(
        billingID: billingID, billID: bill.id, receiptIDs: Array(bill.receipts.map(\.id).reversed())
      )
      await onMutation()
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }

  private func download(_ receipt: Receipt) async {
    do {
      downloadedFile = try await app.dependencies.downloads.downloadReceipt(
        billingID: billingID, billID: bill.id, receiptID: receipt.id
      )
    } catch { app.showNotice(DemoError(error).message, kind: .warning) }
  }
}
