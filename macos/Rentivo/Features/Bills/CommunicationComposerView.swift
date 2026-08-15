import RentivoCore
import SwiftUI

struct CommunicationComposerView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billing: Billing
  let bill: Bill

  @State private var commType: CommunicationType = .billReady
  @State private var selectedRecipients: Set<RecipientID>
  @State private var subject: String
  @State private var message: String
  @State private var saveScope: CommunicationSaveScope?
  @State private var isSending = false
  @State private var appliedTemplateType: CommunicationType
  /// Anything that stops a send, shown inside the sheet. Both the empty-recipient refusal and a
  /// server rejection used to go to `app.showNotice`, whose banner renders *behind* this sheet —
  /// so the button appeared to do nothing at all. The success notice still goes to the banner,
  /// because it fires after `dismiss()`, when there is no sheet left to hide it.
  @State private var sendError: String?

  init(billing: Billing, bill: Bill) {
    self.billing = billing
    self.bill = bill
    let initialType: CommunicationType = bill.capabilities.canSendInvoice ? .billReady : .paymentReceipt
    _commType = State(initialValue: initialType)
    _selectedRecipients = State(initialValue: Set(billing.recipients.map(\.id)))
    let template = billing.template(for: initialType)
    _subject = State(initialValue: template?.subject ?? "")
    _message = State(initialValue: template?.body ?? "")
    _appliedTemplateType = State(initialValue: initialType)
  }

  private var availableTypes: [CommunicationType] {
    CommunicationType.allCases.filter { type in
      switch type {
      case .billReady: bill.capabilities.canSendInvoice
      case .paymentReceipt: bill.status == .paid && bill.capabilities.canSendRecibo
      }
    }
  }

  private var sendDisabled: Bool {
    // Defense in depth: the detail screen already disables the entry point while the PDF renders,
    // but a composer opened just before the render started must not attach a stale document.
    communicationSendIsDisabled(
      isSending: isSending,
      hasSelectedRecipients: !selectedRecipients.isEmpty,
      isRenderingPDF: bill.isRenderingPDF
    ) || !availableTypes.contains(commType)
  }

  private var attachmentDescription: String {
    commType == .paymentReceipt ? "recibo" : "PDF da fatura"
  }

  var body: some View {
    Form {
      if billing.recipients.isEmpty {
        Section {
          Text("Nenhum destinatário cadastrado. Adicione destinatários na cobrança antes de enviar.")
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      } else {
        if availableTypes.count > 1 {
          Section {
            Picker("Tipo", selection: $commType) {
              ForEach(availableTypes, id: \.self) { type in
                Text(type.label).tag(type)
              }
            }
            .pickerStyle(.segmented)
          }
        }

        Section {
          ForEach(billing.recipients) { recipient in
            Toggle(isOn: binding(for: recipient.id)) {
              VStack(alignment: .leading) {
                Text(recipient.name).font(RentivoTypography.bodyStrong)
                Text(recipient.email)
                  .font(RentivoTypography.caption)
                  .foregroundStyle(RentivoColors.secondaryInk)
              }
            }
          }
        } header: {
          Text("Destinatários")
        } footer: {
          Text("Cada destinatário recebe um e-mail separado com o \(attachmentDescription) anexado.")
        }

        Section {
          TextField("Assunto", text: $subject)
          TextField("Corpo (Markdown — HTML não é permitido)", text: $message, axis: .vertical)
            .lineLimit(5...12)
        } header: {
          Text("Mensagem")
        } footer: {
          Text("Variáveis: {{nome_inquilino}}, {{unidade}}, {{mes}}, {{vencimento}}, {{total}}.")
        }

        Section {
          Picker("Salvar modelo", selection: $saveScope) {
            Text("Não salvar como modelo").tag(CommunicationSaveScope?.none)
            Text("Salvar para esta cobrança").tag(CommunicationSaveScope?.some(.billing))
            if billing.capabilities.canEdit {
              Text(ownerScopeLabel).tag(CommunicationSaveScope?.some(.owner))
            }
          }
        } footer: {
          Text("O modelo salvo preenche automaticamente as próximas comunicações.")
        }

        if let sendError {
          Section {
            Label(sendError, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(RentivoColors.coral)
              .accessibilityIdentifier("comm.error")
          }
        }

        Section {
          Button {
            Task { await send() }
          } label: {
            HStack(spacing: RentivoSpacing.small) {
              if isSending {
                ProgressView()
                  .controlSize(.small)
                  .tint(.white)
              }
              Text(isSending ? "Enviando..." : "Enviar \(commType.label.lowercased())")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(RentivoButtonStyle())
          .disabled(sendDisabled)
          .accessibilityIdentifier("comm.send")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Enviar \(commType.label.lowercased())")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancelar") { dismiss() }
          .disabled(isSending)
      }
    }
    .onChange(of: commType) { _, _ in applyTemplateIfNeeded() }
    .interactiveDismissDisabled(isSending)
  }

  private var ownerScopeLabel: String {
    switch billing.owner {
    case .organization: "Salvar para a organização"
    case .user: "Salvar para minha conta"
    }
  }

  private func binding(for id: RecipientID) -> Binding<Bool> {
    Binding(
      get: { selectedRecipients.contains(id) },
      set: { isOn in
        if isOn { selectedRecipients.insert(id) } else { selectedRecipients.remove(id) }
      }
    )
  }

  private func applyTemplateIfNeeded() {
    guard appliedTemplateType != commType else { return }
    appliedTemplateType = commType
    let template = billing.template(for: commType)
    subject = template?.subject ?? ""
    message = template?.body ?? ""
  }

  private func send() async {
    guard !isSending else { return }
    sendError = nil
    guard !selectedRecipients.isEmpty else {
      sendError = "Selecione ao menos um destinatário."
      return
    }
    isSending = true
    defer { isSending = false }
    do {
      let orderedIDs = billing.recipients.map(\.id).filter(selectedRecipients.contains)
      _ = try await app.dependencies.communications.sendCommunication(
        billingID: billing.id,
        billID: bill.id,
        commType: commType,
        recipientIDs: orderedIDs,
        subject: subject,
        message: message,
        acknowledgeWarning: false,
        saveScope: saveScope
      )
      dismiss()
      app.showNotice("Comunicação enfileirada para envio.")
    } catch { sendError = DemoError(error).message }
  }
}
