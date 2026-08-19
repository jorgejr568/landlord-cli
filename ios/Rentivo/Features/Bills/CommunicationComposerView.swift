import SwiftUI
import UIKit

enum CommunicationComposerStep: Hashable, Sendable {
  case type
  case recipients
  case message
  case review
}

enum CommunicationComposerRules {
  static func availableTypes(for bill: Bill) -> [CommunicationType] {
    CommunicationType.allCases.filter { type in
      switch type {
      case .billReady: bill.capabilities.canSendInvoice
      case .paymentReceipt: bill.status == .paid && bill.capabilities.canSendRecibo
      }
    }
  }

  static func steps(availableTypeCount: Int) -> [CommunicationComposerStep] {
    guard availableTypeCount > 0 else { return [] }
    return (availableTypeCount > 1 ? [.type] : []) + [.recipients, .message, .review]
  }
}

enum CommunicationVariableInsertion {
  static func insert(_ token: String, into text: String, selection: NSRange) -> (String, NSRange) {
    let source = text as NSString
    let safeLocation = min(max(selection.location, 0), source.length)
    let safeLength = min(max(selection.length, 0), source.length - safeLocation)
    let safeRange = NSRange(location: safeLocation, length: safeLength)
    let updated = source.replacingCharacters(in: safeRange, with: token)
    return (updated, NSRange(location: safeLocation + (token as NSString).length, length: 0))
  }
}

struct CommunicationPreviewContext: Equatable, Sendable {
  let recipientName: String
  let values: [CommunicationVariable: String]
  let personalizationMessage: String?

  static func make(
    billing: Billing,
    bill: Bill,
    selectedRecipients: Set<RecipientID>
  ) -> Self {
    let selected = billing.recipients.filter { selectedRecipients.contains($0.id) }
    let recipientName = selected.first?.name ?? "Nome do inquilino"
    return CommunicationPreviewContext(
      recipientName: recipientName,
      values: [
        .tenantName: recipientName,
        .unit: billing.name,
        .referenceMonth: bill.referenceMonth.displayFormatted,
        .dueDate: bill.dueDate?.displayFormatted ?? "",
        .total: bill.effectiveTotal.formatted(),
      ],
      personalizationMessage: selected.count > 1
        ? "Prévia para \(recipientName). Cada destinatário receberá a mensagem com seus próprios dados."
        : nil
    )
  }
}

enum CommunicationPreviewRenderer {
  static func subject(_ source: String, context: CommunicationPreviewContext) -> String {
    CommunicationVariables.replacingTokens(in: source, values: context.values)
  }

  static func body(_ source: String, context: CommunicationPreviewContext) -> AttributedString {
    let replaced = CommunicationVariables.replacingTokens(in: source, values: context.values)
    let inertHTML = replaced.replacingOccurrences(of: "<", with: "\\<")
      .replacingOccurrences(of: ">", with: "\\>")
    return (try? AttributedString(
      markdown: inertHTML,
      options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
    )) ?? AttributedString(replaced)
  }
}

private enum CommunicationComposerFocus: Hashable {
  case recipient(RecipientID)
  case subject
  case message
}

struct CommunicationComposerView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let billing: Billing
  let bill: Bill
  let onSent: () async -> Void

  @State private var commType: CommunicationType
  @State private var selectedRecipients: Set<RecipientID>
  @State private var subject: String
  @State private var message: String
  @State private var saveAsTemplate = false
  @State private var saveScope: CommunicationSaveScope = .billing
  @State private var selectedStep: CommunicationComposerStep
  @State private var isSending = false
  @State private var sendFailure: UserFacingFailure?
  @State private var hasValidatedMessage = false
  @State private var appliedTemplateType: CommunicationType
  @State private var lastTextFocus: CommunicationComposerFocus = .message
  @State private var subjectSelection = NSRange(location: 0, length: 0)
  @State private var messageSelection = NSRange(location: 0, length: 0)
  @State private var requestedTextFocus: CommunicationComposerFocus?
  @State private var counterAnnouncementState: CounterAnnouncementState = .normal
  @FocusState private var focusedRecipient: CommunicationComposerFocus?
  @AccessibilityFocusState private var accessibilityFocusedField: CommunicationComposerFocus?
  private let initialDraftState: NativeCommunicationDraftState

  private enum CounterAnnouncementState {
    case normal
    case nearLimit
    case overLimit
  }

  init(
    billing: Billing,
    bill: Bill,
    onSent: @escaping () async -> Void = {}
  ) {
    self.billing = billing
    self.bill = bill
    self.onSent = onSent
    let available = CommunicationComposerRules.availableTypes(for: bill)
    let initialType = available.first ?? .billReady
    let recipients = Set(billing.recipients.map(\.id))
    let template = billing.template(for: initialType)
    let initialSubject = template?.subject ?? ""
    let initialMessage = template?.body ?? ""
    _commType = State(initialValue: initialType)
    _selectedRecipients = State(initialValue: recipients)
    _subject = State(initialValue: initialSubject)
    _message = State(initialValue: initialMessage)
    _selectedStep = State(initialValue: available.count > 1 ? .type : .recipients)
    _appliedTemplateType = State(initialValue: initialType)
    _subjectSelection = State(initialValue: NSRange(location: (initialSubject as NSString).length, length: 0))
    _messageSelection = State(initialValue: NSRange(location: (initialMessage as NSString).length, length: 0))
    initialDraftState = NativeCommunicationDraftState(
      commType: initialType,
      selectedRecipients: recipients,
      subject: initialSubject,
      message: initialMessage,
      saveScope: nil
    )
  }

  private var availableTypes: [CommunicationType] {
    CommunicationComposerRules.availableTypes(for: bill)
  }

  private var descriptors: [RentivoWizardStepDescriptor<CommunicationComposerStep>] {
    CommunicationComposerRules.steps(availableTypeCount: availableTypes.count).map { step in
      RentivoWizardStepDescriptor(id: step, title: stepTitle(step))
    }
  }

  private var effectiveSaveScope: CommunicationSaveScope? {
    saveAsTemplate ? saveScope : nil
  }

  private var formIssues: [ValidationIssue] {
    CommunicationFormRules.issues(subject: subject, body: message)
  }

  private var sendDisabled: Bool {
    communicationSendIsDisabled(
      isSending: isSending,
      hasSelectedRecipients: !selectedRecipients.isEmpty,
      isRenderingPDF: bill.isRenderingPDF
    ) || !bill.capabilities.canCompose || !availableTypes.contains(commType) || !formIssues.isEmpty
  }

  private var attachmentDescription: String {
    commType == .paymentReceipt ? "recibo" : "PDF da fatura"
  }

  private var previewContext: CommunicationPreviewContext {
    .make(billing: billing, bill: bill, selectedRecipients: selectedRecipients)
  }

  var body: some View {
    RentivoFormWizard(
      title: "Enviar \(commType.label.lowercased())",
      descriptors: descriptors,
      selectedStep: $selectedStep,
      isBusy: isSending,
      isPrimaryEnabled: selectedStep != .review || !sendDisabled,
      finalActionTitle: isSending ? "Enviando..." : "Enviar \(commType.label.lowercased())",
      onValidateAndAdvance: validateAndAdvance,
      onCommit: { Task { await send() } }
    ) { step in
      switch step {
      case .type: typeStep
      case .recipients: recipientsStep
      case .message: messageStep
      case .review: reviewStep
      }
    }
    .onChange(of: commType) { _, _ in applyTemplateIfNeeded() }
    .onChange(of: message.count) { _, count in announceCounterBoundary(for: count) }
    .interactiveDismissDisabled(isSending || isDirty)
  }

  private func stepTitle(_ step: CommunicationComposerStep) -> String {
    switch step {
    case .type: "O que enviar"
    case .recipients: "Destinatários"
    case .message: "Mensagem"
    case .review: "Revisar envio"
    }
  }

  private var typeStep: some View {
    RentivoWizardSection(
      "O que enviar",
      subtitle: "Escolha o documento que será anexado ao e-mail."
    ) {
      RentivoFormField(label: "Tipo") {
        Picker("", selection: $commType) {
          ForEach(availableTypes, id: \.self) { type in Text(type.label).tag(type) }
        }
        .labelsHidden()
        .accessibilityLabel("Tipo")
        .accessibilityIdentifier("comm.type")
      }
      inlineFailure
    }
  }

  private var recipientsStep: some View {
    RentivoWizardSection(
      "Destinatários",
      subtitle: "Cada destinatário recebe um e-mail separado com o \(attachmentDescription) anexado."
    ) {
      if billing.recipients.isEmpty {
        Text("Nenhum destinatário cadastrado. Adicione destinatários na cobrança antes de enviar.")
          .foregroundStyle(RentivoColors.secondaryInk)
      } else {
        ForEach(billing.recipients) { recipient in
          Toggle(isOn: binding(for: recipient.id)) {
            VStack(alignment: .leading) {
              Text(recipient.name).font(.subheadline.weight(.semibold))
              Text(recipient.email).font(.caption).foregroundStyle(RentivoColors.secondaryInk)
            }
          }
          .focused($focusedRecipient, equals: .recipient(recipient.id))
          .accessibilityFocused($accessibilityFocusedField, equals: .recipient(recipient.id))
        }
      }
      inlineFailure
    }
  }

  private var messageStep: some View {
    RentivoWizardSection(
      "Mensagem",
      subtitle: "Personalize o texto e confira a prévia antes de enviar."
    ) {
      cursorField(
        label: "Assunto",
        text: $subject,
        selection: $subjectSelection,
        focus: .subject,
        multiline: false,
        identifier: "comm.subject"
      )
      if let error = messageFieldError(.subject) { fieldError(error, id: "comm.subject.error") }

      cursorField(
        label: "Mensagem",
        text: $message,
        selection: $messageSelection,
        focus: .message,
        multiline: true,
        identifier: "comm.body"
      )
      if let error = messageFieldError(.body) { fieldError(error, id: "comm.body.error") }

      HStack(alignment: .firstTextBaseline) {
        variableMenu
        Spacer()
        Text("\(BrazilianLocaleFormatting.integer(message.count)) de 4.096 caracteres")
          .font(.footnote.monospacedDigit())
          .foregroundStyle(
            message.count > CommunicationFormRules.maximumBodyCharacterCount
              ? RentivoColors.coral : RentivoColors.secondaryInk
          )
          .accessibilityIdentifier("comm.character-count")
      }

      if message.count > CommunicationFormRules.maximumBodyCharacterCount {
        fieldError("A mensagem deve ter no máximo 4.096 caracteres.", id: "comm.character-limit")
      } else if let token = CommunicationVariables.firstUnknownToken(in: subject + "\n" + message) {
        fieldError("Revise a variável não reconhecida: \(token).", id: "comm.variable.error")
      }

      CommunicationPreviewCard(
        subject: subject,
        message: message,
        context: previewContext
      )
      inlineFailure
    }
  }

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: RentivoSpacing.section) {
      RentivoWizardSection("Revisar envio") {
        RentivoWizardReviewRow(label: "Tipo", value: commType.label)
        RentivoWizardReviewRow(
          label: "Destinatários",
          value: ptBRCount(selectedRecipients.count, singular: "destinatário", plural: "destinatários")
        )
        RentivoWizardReviewRow(label: "Anexo", value: attachmentDescription)
        CommunicationPreviewCard(subject: subject, message: message, context: previewContext)
      }
      RentivoWizardSection("Modelo") {
        Toggle("Salvar como modelo para próximos envios", isOn: $saveAsTemplate)
          .accessibilityIdentifier("comm.save-template")
        if saveAsTemplate {
          if billing.capabilities.canEdit {
            RentivoFormField(label: "Usar o modelo em") {
              Picker("", selection: $saveScope) {
                Text("Somente nesta cobrança").tag(CommunicationSaveScope.billing)
                Text(ownerScopeLabel).tag(CommunicationSaveScope.owner)
              }
              .labelsHidden()
              .accessibilityLabel("Usar o modelo em")
              .accessibilityIdentifier("comm.save-scope")
            }
          }
          Text("O assunto e a mensagem substituirão o modelo atual.")
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
      }
      if bill.isRenderingPDF {
        Label("Aguarde a geração do PDF antes de enviar.", systemImage: "clock.fill")
          .foregroundStyle(RentivoColors.secondaryInk)
      }
      inlineFailure
    }
  }

  private func cursorField(
    label: String,
    text: Binding<String>,
    selection: Binding<NSRange>,
    focus: CommunicationComposerFocus,
    multiline: Bool,
    identifier: String
  ) -> some View {
    RentivoFormField(label: label) {
      CursorTrackingTextView(
        text: text,
        selection: selection,
        multiline: multiline,
        shouldFocus: requestedTextFocus == focus,
        onFocus: {
          lastTextFocus = focus
          requestedTextFocus = nil
        }
      )
      .frame(minHeight: multiline ? 132 : 44)
      .accessibilityLabel(label)
      .accessibilityIdentifier(identifier)
      .accessibilityFocused($accessibilityFocusedField, equals: focus)
    }
  }

  private var variableMenu: some View {
    Menu {
      ForEach(CommunicationVariable.allCases, id: \.self) { variable in
        Button(variable.label) { insert(variable) }
          .accessibilityLabel("\(variable.label), inserir \(insertionDestinationLabel)")
      }
    } label: {
      Label("Inserir dado", systemImage: "curlybraces")
    }
    .accessibilityLabel("Inserir dado \(insertionDestinationLabel)")
    .accessibilityIdentifier("comm.insert-data")
  }

  private var insertionDestinationLabel: String {
    lastTextFocus == .subject ? "no assunto" : "na mensagem"
  }

  private func insert(_ variable: CommunicationVariable) {
    let target = lastTextFocus == .subject ? CommunicationComposerFocus.subject : .message
    switch target {
    case .subject:
      (subject, subjectSelection) = CommunicationVariableInsertion.insert(
        variable.token, into: subject, selection: subjectSelection)
    default:
      (message, messageSelection) = CommunicationVariableInsertion.insert(
        variable.token, into: message, selection: messageSelection)
    }
    requestedTextFocus = target
  }

  private func fieldError(_ message: String, id: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.footnote)
      .foregroundStyle(RentivoColors.coral)
      .accessibilityIdentifier(id)
  }

  @ViewBuilder
  private var inlineFailure: some View {
    if let sendFailure {
      UserFacingFailureView(failure: sendFailure) { openAuthenticatorSetup() }
        .accessibilityIdentifier("comm.error")
    }
  }

  private func validateAndAdvance() -> Bool {
    sendFailure = nil
    switch selectedStep {
    case .type:
      guard availableTypes.contains(commType) else { return false }
    case .recipients:
      guard !selectedRecipients.isEmpty else {
        sendFailure = UserFacingFailure(
          message: "Selecione ao menos um destinatário.", recovery: .none)
        if let recipient = billing.recipients.first {
          focusedRecipient = .recipient(recipient.id)
          accessibilityFocusedField = .recipient(recipient.id)
        }
        return false
      }
    case .message:
      hasValidatedMessage = true
      if let issue = formIssues.first {
        let target: CommunicationComposerFocus = issue.field == .subject ? .subject : .message
        requestedTextFocus = target
        accessibilityFocusedField = target
        return false
      }
    case .review:
      break
    }
    return true
  }

  private func messageFieldError(_ field: ValidationField) -> String? {
    guard hasValidatedMessage else { return nil }
    return formIssues.first(where: { $0.field == field })?.message
  }

  private var isDirty: Bool {
    NativeCommunicationDraftState(
      commType: commType,
      selectedRecipients: selectedRecipients,
      subject: subject,
      message: message,
      saveScope: effectiveSaveScope
    ).hasChanges(from: initialDraftState)
  }

  private var ownerScopeLabel: String {
    switch billing.owner {
    case .organization: "Todas as cobranças desta organização"
    case .user: "Todas as minhas cobranças"
    }
  }

  private func binding(for id: RecipientID) -> Binding<Bool> {
    Binding(
      get: { selectedRecipients.contains(id) },
      set: { selected in
        if selected { selectedRecipients.insert(id) } else { selectedRecipients.remove(id) }
      }
    )
  }

  private func applyTemplateIfNeeded() {
    guard appliedTemplateType != commType else { return }
    appliedTemplateType = commType
    let template = billing.template(for: commType)
    subject = template?.subject ?? ""
    message = template?.body ?? ""
    subjectSelection = NSRange(location: (subject as NSString).length, length: 0)
    messageSelection = NSRange(location: (message as NSString).length, length: 0)
  }

  private func announceCounterBoundary(for count: Int) {
    let next: CounterAnnouncementState
    if count > CommunicationFormRules.maximumBodyCharacterCount {
      next = .overLimit
    } else if count >= Int(Double(CommunicationFormRules.maximumBodyCharacterCount) * 0.9) {
      next = .nearLimit
    } else {
      next = .normal
    }
    guard next != counterAnnouncementState else { return }
    let previous = counterAnnouncementState
    counterAnnouncementState = next
    let message: String?
    switch (previous, next) {
    case (_, .overLimit):
      message = "A mensagem ultrapassou o limite de 4.096 caracteres."
    case (.overLimit, .nearLimit), (.overLimit, .normal):
      message = "A mensagem voltou ao limite permitido."
    case (.normal, .nearLimit):
      message = "A mensagem atingiu noventa por cento do limite."
    default:
      message = nil
    }
    if let message { UIAccessibility.post(notification: .announcement, argument: message) }
  }

  private func send() async {
    guard !isSending else { return }
    sendFailure = nil
    guard availableTypes.contains(commType), !bill.isRenderingPDF else {
      sendFailure = UserFacingFailure(
        message: "O documento ainda está sendo preparado. Aguarde e tente novamente.",
        recovery: .retry
      )
      return
    }
    guard !selectedRecipients.isEmpty, formIssues.isEmpty else {
      hasValidatedMessage = true
      selectedStep = selectedRecipients.isEmpty ? .recipients : .message
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
        subject: CommunicationContent.normalizedSubject(subject),
        message: CommunicationContent.normalizedMessage(message),
        acknowledgeWarning: false,
        saveScope: effectiveSaveScope
      )
      await onSent()
      dismiss()
      app.showNotice("Envio iniciado. Acompanhe o status em Comunicações.")
    } catch {
      sendFailure = UserFacingError.presentation(for: error, operation: .sendCommunication)
    }
  }

  private func openAuthenticatorSetup() {
    dismiss()
    Task { @MainActor in app.navigateToAuthenticatorSetup() }
  }
}

private struct CommunicationPreviewCard: View {
  let subject: String
  let message: String
  let context: CommunicationPreviewContext

  var body: some View {
    RentivoCard {
      VStack(alignment: .leading, spacing: RentivoSpacing.medium) {
        Text("Prévia da mensagem")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        if let personalizationMessage = context.personalizationMessage {
          Text(personalizationMessage)
            .font(.footnote)
            .foregroundStyle(RentivoColors.secondaryInk)
        }
        VStack(alignment: .leading, spacing: RentivoSpacing.tiny) {
          Text("Assunto").font(.caption).foregroundStyle(RentivoColors.secondaryInk)
          Text(CommunicationPreviewRenderer.subject(subject, context: context))
            .font(.subheadline.weight(.semibold))
        }
        Divider()
        Text(CommunicationPreviewRenderer.body(message, context: context))
          .font(.body)
          .tint(RentivoColors.emerald)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("comm.preview")
  }
}

private struct CursorTrackingTextView: UIViewRepresentable {
  @Binding var text: String
  @Binding var selection: NSRange
  let multiline: Bool
  let shouldFocus: Bool
  let onFocus: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.backgroundColor = .clear
    view.font = UIFont.preferredFont(forTextStyle: .body)
    view.adjustsFontForContentSizeCategory = true
    view.isScrollEnabled = multiline
    view.returnKeyType = multiline ? .default : .done
    view.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
    view.layer.cornerRadius = 10
    view.layer.borderWidth = 1
    view.layer.borderColor = UIColor.separator.cgColor
    view.accessibilityTraits = .updatesFrequently
    return view
  }

  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
    if view.text != text { view.text = text }
    let safeLocation = min(selection.location, (view.text as NSString).length)
    let safeLength = min(selection.length, (view.text as NSString).length - safeLocation)
    let safeSelection = NSRange(location: safeLocation, length: safeLength)
    if view.selectedRange != safeSelection { view.selectedRange = safeSelection }
    if shouldFocus, !view.isFirstResponder {
      DispatchQueue.main.async { view.becomeFirstResponder() }
    }
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: CursorTrackingTextView
    init(parent: CursorTrackingTextView) { self.parent = parent }

    func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus() }
    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      parent.selection = textView.selectedRange
    }
    func textViewDidChangeSelection(_ textView: UITextView) {
      parent.selection = textView.selectedRange
    }
    func textView(
      _ textView: UITextView,
      shouldChangeTextIn range: NSRange,
      replacementText text: String
    ) -> Bool {
      if !parent.multiline, text == "\n" {
        textView.resignFirstResponder()
        return false
      }
      return true
    }
  }
}
